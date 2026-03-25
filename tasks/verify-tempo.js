require("hardhat/config");

const fs = require("fs");
const semver = require("semver");
const { task, types } = require("hardhat/config");
const { parseFullyQualifiedName } = require("hardhat/utils/contract-names");
const { TASK_COMPILE } = require("hardhat/builtin-tasks/task-names");
const { Bytecode, extractMatchingContractInformation } = require("@nomiclabs/hardhat-etherscan/dist/src/solc/bytecode");
const { getLongVersion } = require("@nomiclabs/hardhat-etherscan/dist/src/solc/version");
const { retrieveContractBytecode } = require("@nomiclabs/hardhat-etherscan/dist/src/network/prober");
const { getLibraryLinks } = require("@nomiclabs/hardhat-etherscan/dist/src/solc/libraries");

const TEMPO_VERIFIER_URL = "https://contracts.tempo.xyz";
const TEMPO_EXPLORER_URL = "https://explore.tempo.xyz";
const BUNDLED_BUILD_INFO_PATHS = [
  "node_modules/@openzeppelin/upgrades-core/artifacts/build-info.json",
  "node_modules/@openzeppelin/upgrades-core/artifacts/build-info-v5.json",
];

let bundledBuildInfos;

const sleep = async (ms) => new Promise(resolve => setTimeout(resolve, ms));

const parseJsonResponse = async (response) => {
  const text = await response.text();
  if (!text) {
    return {};
  }

  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`Tempo verifier returned a non-JSON response: ${text}`);
  }
};

const requestTempo = async (url, options = {}) => {
  const response = await fetch(url, options);
  const data = await parseJsonResponse(response);

  if (!response.ok) {
    throw new Error(
      `Tempo verifier request failed (${response.status} ${response.statusText}) at ${url}: ${JSON.stringify(data)}`
    );
  }

  return data;
};

const getAlreadyVerifiedContract = async (chainId, address) => {
  const response = await fetch(`${TEMPO_VERIFIER_URL}/v2/contract/${chainId}/${address}`);
  if (response.status === 404) {
    return null;
  }

  const data = await parseJsonResponse(response);
  if (!response.ok) {
    throw new Error(
      `Tempo verifier lookup failed (${response.status} ${response.statusText}): ${JSON.stringify(data)}`
    );
  }

  return data;
};

const getBundledBuildInfos = () => {
  if (bundledBuildInfos) {
    return bundledBuildInfos;
  }

  bundledBuildInfos = BUNDLED_BUILD_INFO_PATHS
    .filter(path => fs.existsSync(path))
    .map(path => ({
      path,
      buildInfo: JSON.parse(fs.readFileSync(path, "utf8")),
    }));

  return bundledBuildInfos;
};

const getBundledBuildInfoMatches = async (contractFQN, deployedBytecode) => {
  const matches = [];
  const buildInfoEntries = getBundledBuildInfos();

  if (contractFQN) {
    const { sourceName, contractName } = parseFullyQualifiedName(contractFQN);
    for (const { path, buildInfo } of buildInfoEntries) {
      const buildInfoContracts = buildInfo.output.contracts[sourceName];
      if (!buildInfoContracts || !buildInfoContracts[contractName]) {
        continue;
      }

      const contractInformation = await extractMatchingContractInformation(
        sourceName,
        contractName,
        buildInfo,
        deployedBytecode
      );

      if (contractInformation !== null) {
        matches.push({
          path,
          buildInfo,
          contractInformation,
        });
      }
    }

    return matches;
  }

  for (const { path, buildInfo } of buildInfoEntries) {
    for (const [sourceName, contracts] of Object.entries(buildInfo.output.contracts)) {
      for (const [contractName, compiledContract] of Object.entries(contracts)) {
        if (!compiledContract.evm || !compiledContract.evm.deployedBytecode || !compiledContract.evm.deployedBytecode.object) {
          continue;
        }

        const contractInformation = await extractMatchingContractInformation(
          sourceName,
          contractName,
          buildInfo,
          deployedBytecode
        );

        if (contractInformation !== null) {
          matches.push({
            path,
            buildInfo,
            contractInformation,
          });
        }
      }
    }
  }

  return matches;
};

const getBundledContractInformation = async (contractFQN, deployedBytecode, resolvedLibraries) => {
  let matches;

  try {
    matches = await getBundledBuildInfoMatches(contractFQN, deployedBytecode);
  } catch (err) {
    return null;
  }

  if (matches.length === 0) {
    return null;
  }

  if (matches.length > 1) {
    const matchList = matches
      .map(({ buildInfo, contractInformation }) => (
        `${contractInformation.sourceName}:${contractInformation.contractName} (solc ${buildInfo.solcVersion})`
      ))
      .join("\n");

    throw new Error(
      `More than one bundled OpenZeppelin contract matched the deployed bytecode.\nUse --contract with one of:\n${matchList}`
    );
  }

  const match = matches[0];
  const { libraryLinks, undetectableLibraries } = await getLibraryLinks(match.contractInformation, resolvedLibraries);

  return {
    compilerVersion: match.buildInfo.solcLongVersion,
    contractInformation: {
      ...match.contractInformation,
      libraryLinks,
      undetectableLibraries,
    },
  };
};

task("verify-tempo", "Verifies contract source on Tempo")
  .addOptionalPositionalParam("address", "Address of the smart contract to verify")
  .addOptionalParam(
    "constructorArgs",
    "File path to a javascript module that exports the list of constructor arguments. Accepted for CLI compatibility with hardhat verify.",
    undefined,
    types.inputFile
  )
  .addOptionalParam(
    "contract",
    "Fully qualified name of the contract to verify. Use if the deployed bytecode matches more than one contract in your project."
  )
  .addOptionalParam(
    "libraries",
    "File path to a javascript module that exports the dictionary of library addresses for your contract.",
    undefined,
    types.inputFile
  )
  .addOptionalParam(
    "creationTxHash",
    "Creation transaction hash to include if Tempo cannot resolve deployment bytecode automatically."
  )
  .addOptionalParam(
    "pollInterval",
    "Polling interval in milliseconds while waiting for verification.",
    3000,
    types.int
  )
  .addOptionalParam(
    "timeout",
    "Maximum time in milliseconds to wait for verification to finish.",
    180000,
    types.int
  )
  .addOptionalVariadicPositionalParam(
    "constructorArgsParams",
    "Contract constructor arguments. Accepted for CLI compatibility with hardhat verify.",
    []
  )
  .addFlag("noCompile", "Don't compile before running this task")
  .setAction(async ({
    address,
    constructorArgs,
    constructorArgsParams,
    contract,
    libraries,
    creationTxHash,
    pollInterval,
    timeout,
    noCompile,
  }, hre) => {
    if (address === undefined) {
      throw new Error("You didn’t provide any address. Re-run the task with the contract address you want to verify.");
    }

    const { isAddress } = require("@ethersproject/address");
    if (!isAddress(address)) {
      throw new Error(`${address} is an invalid address.`);
    }

    const constructorArguments = await hre.run("verify:get-constructor-arguments", {
      constructorArgsModule: constructorArgs,
      constructorArgsParams,
    });
    const resolvedLibraries = await hre.run("verify:get-libraries", {
      librariesModule: libraries,
    });

    if (!noCompile) {
      await hre.run(TASK_COMPILE);
    }

    const { chainId } = await hre.ethers.provider.getNetwork();
    const alreadyVerified = await getAlreadyVerifiedContract(chainId, address);
    if (alreadyVerified) {
      console.log(`The contract ${address} is already verified on Tempo.`);
      console.log(`${TEMPO_EXPLORER_URL}/address/${address}`);
      return alreadyVerified;
    }

    const deployedBytecodeHex = await retrieveContractBytecode(address, hre.network.provider, hre.network.name);
    const deployedBytecode = new Bytecode(deployedBytecodeHex);
    const bundledContract = await getBundledContractInformation(contract, deployedBytecode, resolvedLibraries);
    let contractInformation;
    let compilerVersion;

    if (bundledContract !== null) {
      contractInformation = bundledContract.contractInformation;
      compilerVersion = bundledContract.compilerVersion;
    } else {
      const compilerVersions = await hre.run("verify:get-compiler-versions");
      const inferredSolcVersion = deployedBytecode.getInferredSolcVersion();
      const matchingCompilerVersions = compilerVersions.filter(version => semver.satisfies(version, inferredSolcVersion));

      if (matchingCompilerVersions.length === 0 && !deployedBytecode.isOvmInferred()) {
        let configuredCompilersFragment;
        if (compilerVersions.length > 1) {
          configuredCompilersFragment = `your configured compiler versions are: ${compilerVersions.join(", ")}`;
        } else {
          configuredCompilersFragment = `your configured compiler version is: ${compilerVersions[0]}`;
        }

        throw new Error(
          `The contract you want to verify was compiled with solidity ${inferredSolcVersion}, but ${configuredCompilersFragment}.`
        );
      }

      contractInformation = await hre.run("verify:get-contract-information", {
        contractFQN: contract,
        deployedBytecode,
        matchingCompilerVersions,
        libraries: resolvedLibraries,
      });

      compilerVersion = deployedBytecode.isOvmInferred()
        ? contractInformation.solcVersion.replace(/^v/, "")
        : await getLongVersion(contractInformation.solcVersion);
    }

    if (constructorArguments.length > 0) {
      console.log("Constructor arguments were provided, but Tempo's verifier derives deployment data from the chain.");
      console.log("If Tempo cannot resolve the creation bytecode, rerun with --creation-tx-hash <TX_HASH>.");
      console.log();
    }

    const stdJsonInput = JSON.parse(JSON.stringify(contractInformation.compilerInput));
    stdJsonInput.settings = stdJsonInput.settings || {};
    stdJsonInput.settings.libraries = contractInformation.libraryLinks;

    const contractIdentifier = `${contractInformation.sourceName}:${contractInformation.contractName}`;
    const body = {
      stdJsonInput,
      compilerVersion,
      contractIdentifier,
    };

    if (creationTxHash) {
      body.creationTransactionHash = creationTxHash;
    }

    const submitUrl = `${TEMPO_VERIFIER_URL}/v2/verify/${chainId}/${address}`;
    const submitResponse = await requestTempo(submitUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!submitResponse.verificationId) {
      throw new Error(`Tempo verifier did not return a verificationId: ${JSON.stringify(submitResponse)}`);
    }

    console.log(`Submitted ${contractIdentifier} at ${address} for verification on Tempo.`);
    console.log(`Verification ID: ${submitResponse.verificationId}`);
    console.log("Waiting for verification result...");
    console.log();

    const statusUrl = `${TEMPO_VERIFIER_URL}/v2/verify/${submitResponse.verificationId}`;
    const deadline = Date.now() + timeout;

    while (Date.now() < deadline) {
      await sleep(pollInterval);

      const status = await requestTempo(statusUrl);
      if (!status.isJobCompleted) {
        continue;
      }

      const match = status.contract?.match;
      if (match === "exact_match" || match === "match") {
        console.log(`Successfully verified ${contractIdentifier} on Tempo (${match}).`);
        console.log(`${TEMPO_EXPLORER_URL}/address/${address}`);
        return status;
      }

      throw new Error(`Tempo verification failed: ${JSON.stringify(status, null, 2)}`);
    }

    throw new Error(`Timed out after ${timeout}ms waiting for Tempo verification. Check status manually at ${statusUrl}`);
  });
