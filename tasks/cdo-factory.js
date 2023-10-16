require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { task } = require("hardhat/config");
const HypernativeModuleAbi = require("../abi/HypernativeModule.json");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const polygonContracts = addresses.IdleTokens.polygon;
const polygonZKContracts = addresses.IdleTokens.polygonZK;
const optimismContracts = addresses.IdleTokens.optimism;

const getNetworkContracts = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  if (isMatic) {
    return polygonContracts;
  } else if (isPolygonZK) {
    return polygonZKContracts;
  } else if (isOptimism) {
    return optimismContracts;
  }
  return mainnetContracts;
}

const getDeployTokens = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  if (isMatic) {
    return addresses.deployTokensPolygon;
  } else if (isPolygonZK) {
    return addresses.deployTokensPolygonZK;
  } else if (isOptimism) {
    return addresses.deployTokensOptimism;
  }
  return addresses.deployTokens;
}

/**
 * @name deploy
 * deploy factory for CDOs
 */
task("hypernative-setup", "Deploy IdleCDOFactory")
  .setAction(async (args) => {
    const networkContracts = getNetworkContracts(hre);
    const signer = await helpers.getSigner();
    const pauseModule = new ethers.Contract(networkContracts.hypernativeModule, HypernativeModuleAbi, signer);
    console.log(`Setting contract to hypernative pauser module ${networkContracts.hypernativeModule}`);

    const tx = await pauseModule.replaceProtectedContracts([
      // best yield
      { contractAddress: '0x3fE7940616e5Bc47b0775a0dccf6237893353bB4', contractType: 0 },
      { contractAddress: '0x5274891bEC421B39D23760c04A6755eCB444797C', contractType: 0 },
      { contractAddress: '0xF34842d05A1c888Ca02769A633DF37177415C2f8', contractType: 0 },
      { contractAddress: '0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80', contractType: 0 },
      { contractAddress: '0xeC9482040e6483B7459CC0Db05d51dfA3D3068E1', contractType: 0 },
      { contractAddress: '0xDc7777C771a6e4B3A82830781bDDe4DBC78f320e', contractType: 0 },
      { contractAddress: '0xfa3AfC9a194BaBD56e743fA3b7aA2CcbED3eAaad', contractType: 0 },
      { contractAddress: '0x62A0369c6BB00054E589D12aaD7ad81eD789514b', contractType: 0 },
      // tranches
      { contractAddress: '0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8', contractType: 1 },
      { contractAddress: '0xF87ec7e1Ee467d7d78862089B92dd40497cBa5B8', contractType: 1 },
      { contractAddress: '0x1329E8DB9Ed7a44726572D44729427F132Fa290D', contractType: 1 },
      { contractAddress: '0x5dcA0B3Ed7594A6613c1A2acd367d56E1f74F92D', contractType: 1 },
      { contractAddress: '0xc4574C60a455655864aB80fa7638561A756C5E61', contractType: 1 },
      { contractAddress: '0xE7C6A4525492395d65e736C3593aC933F33ee46e', contractType: 1 },
      { contractAddress: '0x9C13Ff045C0a994AF765585970A5818E1dB580F8', contractType: 1 },
      { contractAddress: '0xDB82dDcb7e2E4ac3d13eBD1516CBfDb7b7CE0ffc', contractType: 1 },
      { contractAddress: '0x440ceAd9C0A0f4ddA1C81b892BeDc9284Fc190dd', contractType: 1 },
      { contractAddress: '0xb3F717a5064D2CBE1b8999Fdfd3F8f3DA98339a6', contractType: 1 },
      { contractAddress: '0x8E0A8A5c1e5B3ac0670Ea5a613bB15724D51Fc37', contractType: 1 },
      { contractAddress: '0xd12f9248dEb1D972AA16022B399ee1662d51aD22', contractType: 1 },
    ]);
    await tx.wait();
    console.log('Hypernative setup done');
  })

/**
 * @name deploy
 * deploy factory for CDOs
 */
task("deploy-cdo-factory", "Deploy IdleCDOFactory")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    console.log("creator: ", creator);
    console.log("network: ", hre.network.name);
    await helpers.prompt("continue? [y/n]", true);

    const cdoFactory = await helpers.deployContract("IdleCDOFactory", [], signer);
    console.log("cdoFactory deployed at", cdoFactory.address);
    return cdoFactory;
  });

/**
 * @name deploy-cdo-with-factory
 * subtask to deploy CDO with factory and params provided
 */
subtask("deploy-cdo-with-factory", "Deploy IdleCDO using IdleCDOFactory with all params provided")
  .addParam('cdoImplementation', "The CDO implementation address", "", types.string, true)
  .addParam('cloneFromProxy', "The CDO proxy to clone the implementation from", "", types.string, true)
  .addParam('proxyAdmin', "The ProxyAdmin address", "", types.string, true)
  .addParam('cdoUnderlying', "The CDO's underlying address", "", types.string, true)
  .addParam('limit', "CDO param _limit")
  .addParam('governanceFund', "CDO param _governanceFund")
  .addParam('strategy', "CDO param _strategy")
  .addParam('trancheAPRSplitRatio', "CDO param _trancheAPRSplitRatio")
  .addParam('trancheIdealWeightRatio', "CDO param _trancheIdealWeightRatio")
  .addParam('incentiveTokens', "A comma separated list of incentive tokens", undefined, types.string, true)
  .setAction(async (args) => {
    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    let proxyAdminAddress = args.proxyAdmin;
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const networkContracts = getNetworkContracts(hre);

    if (!proxyAdminAddress) {
      const defaultProxyAdminAddress = networkContracts.proxyAdmin;
      console.log("⚠️  proxyAdmin not specified. Using the default one: ", defaultProxyAdminAddress);
      proxyAdminAddress = defaultProxyAdminAddress;
    }

    if (helpers.isEmptyString(args.cdoImplementation) && helpers.isEmptyString(args.cloneFromProxy)) {
      throw("cdoImplementationAddress or cloneFromProxy must be specified");
    }

    let cdoImplementationAddress = args.cdoImplementation;
    if (helpers.isEmptyString(cdoImplementationAddress)) {
      console.log("\n🔎 Retrieving implementation from proxy (", args.cloneFromProxy, ")");
      cdoImplementationAddress = await getImplementationAddress(hre.ethers.provider, args.cloneFromProxy);
      console.log("🔎 using implementation address", cdoImplementationAddress);
    }

    let cdoFactoryAddress = networkContracts.cdoFactory;
    const limit = args.limit;
    const governanceFund = args.governanceFund;
    const strategyAddress = args.strategy;
    const trancheAPRSplitRatio = args.trancheAPRSplitRatio;
    const trancheIdealWeightRatio = args.trancheIdealWeightRatio;
    const incentiveTokens = args.incentiveTokens ? args.incentiveTokens.split(",").map(s => s.trim()) : [];

    console.log("🔎 Retrieving underlying token from strategy (", strategyAddress, ")");
    const strategy = await ethers.getContractAt("IIdleCDOStrategy", strategyAddress, signer);
    const underlyingAddress = await strategy.token();
    const underlyingAddressCDO = args.cdoUnderlying;
    const underlyingToken = await ethers.getContractAt("IERC20Detailed", underlyingAddress, signer);
    const underlyingName = await underlyingToken.name();
    const underlyingTokenCDO = await ethers.getContractAt("IERC20Detailed", underlyingAddressCDO, signer);
    const underlyingNameCDO = await underlyingTokenCDO.name();

    if (hre.network.name === 'hardhat' && !cdoFactoryAddress) {
      console.log("\n⚠️  Local network - cdoFactoryAddress is undefined, deploying CDOFactory\n");
      const cdoFactory = await hre.run("deploy-cdo-factory");
      cdoFactoryAddress = cdoFactory.address;
    }

    if (helpers.isEmptyString(cdoFactoryAddress)) {
      console.log("🛑 cdoFactoryAddress must be specified")
      return;
    }

    console.log()
    console.log("🟩🟩🟩 IdleCDO params 🟩🟩🟩");
    console.log("creator:                 ", creator);
    console.log("network:                 ", hre.network.name);
    console.log("proxyAdmin:              ", proxyAdminAddress);
    console.log("factory:                 ", cdoFactoryAddress);
    console.log("underlying (strategy):   ", `${underlyingAddress} (${underlyingName})`);
    console.log("underlying (cdo):        ", `${underlyingAddressCDO} (${underlyingNameCDO})`);
    console.log("cdoImplementation:       ", cdoImplementationAddress);
    console.log("limit:                   ", limit.toString());
    console.log("governanceFund:          ", governanceFund);
    console.log("Strategy address:        ", strategyAddress);
    console.log("trancheAPRSplitRatio:    ", trancheAPRSplitRatio.toString());
    console.log("trancheIdealWeightRatio: ", trancheIdealWeightRatio.toString());
    console.log("incentiveTokens:         ", incentiveTokens.toString());
    console.log()
    
    await helpers.prompt("continue? [y/n]", true);
    
    let cdoFactory = await ethers.getContractAt("IdleCDOFactory", cdoFactoryAddress, signer);
    cdoFactory = cdoFactory.connect(signer);
    let contractName = isMatic ? "IdleCDOPolygon" : "IdleCDO";
    if (isPolygonZK) {
      contractName = "IdleCDOPolygonZK";
    } else if (isOptimism) {
      contractName = "IdleCDOOptimism";
    }
    const idleCDO = await ethers.getContractAt(contractName, cdoImplementationAddress, signer);
    
    const initMethodCall = idleCDO.interface.encodeFunctionData("initialize", [
      limit,
      underlyingAddressCDO,
      governanceFund, // recovery address
      creator, // guardian
      networkContracts.rebalancer,
      strategyAddress,
      trancheAPRSplitRatio,
      trancheIdealWeightRatio,
      incentiveTokens
    ]);
    
    console.log("deploying with factory...");
    let res = await cdoFactory.deployCDO(cdoImplementationAddress, proxyAdminAddress, initMethodCall);
    res = await res.wait();
    const cdoDeployFilter = cdoFactory.filters.CDODeployed;
    const events = await cdoFactory.queryFilter(cdoDeployFilter, "latest");
    const proxyAddress = events[0].args.proxy;
    helpers.log(`📤 IdleCDO created (proxy via CDOFactory): ${proxyAddress} @tx: ${res.hash}, (gas ${res.cumulativeGasUsed.toString()})`);
    return proxyAddress;
  });
  
/**
 * @name deploy-with-factory
 * task to deploy CDO and staking rewards with factory and basic params from utils/addresses.js
 */
task("deploy-with-factory", "Deploy IdleCDO with CDOFactory, IdleStrategy and Staking contract for rewards with default parameters")
  .addParam('cdoname')
  .addParam('proxyCdoAddress')
  .addOptionalParam('strategyAddress', 'Strategy address to use', '')
  .addOptionalParam('strategyName', 'Strategy name for the interface to use', '')
  .addOptionalParam('limit', 'Strategy cap', '1000000')
  .addOptionalParam('aaRatio', '% of interest that goes to AA holders (100000 is 100%)', '10000')
  .addOptionalParam('aaStaking', 'flag whether AA staking is active', true, types.boolean)
  .addOptionalParam('bbStaking', 'flag whether BB staking is active', false, types.boolean)
  .addOptionalParam('stkAAVEActive', 'flag whether the IdleCDO receives stkAAVE', true, types.boolean)
  .setAction(async (args) => {
    const cdoname = args.cdoname;
    let cdoProxyAddressToClone = args.proxyCdoAddress;
    const strategyAddress = args.strategyAddress;
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;

    const networkTokens = getDeployTokens(hre);

    // Get config params
    const deployToken = networkTokens[args.cdoname];
    const networkContracts = getNetworkContracts(hre);
    
    if (deployToken === undefined) {
      console.log(`🛑 deployToken not found with specified cdoname (${cdoname})`)
      return;
    } 
    
    const signer = await helpers.getSigner();
    let strategy = await ethers.getContractAt(args.strategyName, strategyAddress, signer);
    const incentiveTokens = deployToken.incentiveTokens || [];
    const creator = await signer.getAddress();
    let networkCDOName = isMatic ? 'IdleCDOPolygon' : 'IdleCDO';
    if (isPolygonZK) {
      networkCDOName = 'IdleCDOPolygonZK';
    } else if (isOptimism) {
      networkCDOName = 'IdleCDOOptimism';
    }
    let idleCDOAddress;
    const contractName = deployToken.cdoVariant || networkCDOName;

    if (helpers.isEmptyString(cdoProxyAddressToClone)) {
      console.log("🛑 cdoProxyAddressToClone must be specified");
      await helpers.prompt(`Deploy a new instance of ${contractName}? [y/n]`, true);

      const newCDO = await helpers.deployUpgradableContract(
        contractName,
        [
          BN(args.limit).mul(ONE_TOKEN(deployToken.decimals)), // limit
          deployToken.underlying,
          networkContracts.treasuryMultisig, // recovery address
          creator, // guardian
          networkContracts.rebalancer,
          strategy.address,
          BN(args.aaRatio), // apr split: 10% interest to AA and 90% BB
          BN('50000'), // ideal value: 50% AA and 50% BB tranches
          incentiveTokens
        ],
        signer
      );
      idleCDOAddress = newCDO.address;
    } else {
      await helpers.prompt("continue? [y/n]", true);
  
      const deployParams = {
        cdoUnderlying: deployToken.underlying,
        cloneFromProxy: cdoProxyAddressToClone,
        limit: BN(args.limit).mul(ONE_TOKEN(deployToken.decimals)).toString(), // limit
        governanceFund: networkContracts.treasuryMultisig, // recovery address
        strategy: strategy.address,
        trancheAPRSplitRatio: BN(args.aaRatio).toString(), // apr split: 10% interest to AA and 80% BB
        trancheIdealWeightRatio: BN('50000').toString(), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens: incentiveTokens.join(","),
      }
      idleCDOAddress = await hre.run("deploy-cdo-with-factory", deployParams);
    }

    const idleCDO = await ethers.getContractAt(contractName, idleCDOAddress, signer);
    console.log('owner idleCDO', await idleCDO.owner());

    if (strategy.setWhitelistedCDO) {
      console.log("Setting whitelisted CDO");
      await strategy.connect(signer).setWhitelistedCDO(idleCDO.address);
    }

    const AAaddr = await idleCDO.AATranche();
    const BBaddr = await idleCDO.BBTranche();
    console.log(`AATranche: ${AAaddr}, BBTranche: ${BBaddr}`);
    console.log()

    const ays = await idleCDO.isAYSActive();
    if (args.isAYSActive && !ays) {
      console.log("Turning on AYS");
      await idleCDO.connect(signer).setIsAYSActive(true);
    }
    console.log(`isAYSActive: ${await idleCDO.isAYSActive()}`);

    console.log(`Transfer ownership of strategy to DL multisig ${networkContracts.devLeagueMultisig}`);
    await strategy.connect(signer).transferOwnership(networkContracts.devLeagueMultisig);
    
    console.log(`Set guardian of CDO to Pause multisig ${networkContracts.pauserMultisig}`);
    await idleCDO.connect(signer).setGuardian(networkContracts.pauserMultisig);

    const feeReceiver = await idleCDO.feeReceiver();
    if ((isMatic || isPolygonZK || isOptimism) && feeReceiver != networkContracts.feeReceiver) {
      console.log('Setting fee receiver to Treasury Multisig')
      await idleCDO.connect(signer).setFeeReceiver(networkContracts.feeReceiver);
    }

    if (deployToken.unlent == 0) {
      console.log('Setting unlent to 0')
      await idleCDO.connect(signer).setUnlentPerc(0);
    }

    console.log(`Transfer ownership of CDO to TL multisig ${networkContracts.treasuryMultisig}`);
    await idleCDO.connect(signer).transferOwnership(networkContracts.treasuryMultisig);

    if (!(isMatic || isPolygonZK || isOptimism)) {
      const pauseModule = new ethers.Contract(networkContracts.hypernativeModule, HypernativeModuleAbi, signer);
      console.log(`Setting contract to hypernative pauser module ${networkContracts.hypernativeModule}`);
      const tx = await pauseModule.updateProtectedContracts([{
        contractAddress: idleCDO.address, 
        contractType: 1 // tranche contract
      }]);
      await tx.wait();
      console.log('isContractProtected: ', await pauseModule.isContractProtected(idleCDO.address));
      console.log(`IMPORTANT: manually add contract to watchlists in hypernative module`);
    }

    // // adding CDO to IdleCDO registry (TODO multisig)
    // const reg = await ethers.getContractAt("IIdleCDORegistry", mainnetContracts.idleCDORegistry);
    // const isValid = await reg.isValidCdo(idleCDO.address);
    // if (!isValid) {
    //   console.log("Adding CDO to IdleCDO registry");
    //   await reg.connect(signer).toggleCDO(idleCDO.address, true);
    // }
    
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

/**
 * @name deploy-with-factory-params
 * task to deploy CDO with strategy, staking rewards via factory with all params from utils/addresses.js
 */
task("deploy-with-factory-params", "Deploy IdleCDO with a new strategy and optionally staking rewards via CDOFactory")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");
    // Check that cdoname is passed
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    
    const networkTokens = getDeployTokens(hre);

    // Get config params
    const deployToken = networkTokens[args.cdoname];
    
    // Check that args has strategyName and strategyParams
    if (!deployToken.strategyName || !deployToken.strategyParams) {
      console.log("🛑 strategyName and strategyParams must be specified");
      return;
    }
    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();

    console.log(`Deploying with ${addr}`);
    console.log()

    // Replace owner as last param
    const params = deployToken.strategyParams.map(
      p => p === 'owner' ? addr : p
    );  

    console.log("Deploying Strategy:      ", deployToken.strategyName);
    console.log("Strategy params:         ", JSON.stringify(params));
    console.log()

    // Deploy strategy
    const strategy = await helpers.deployUpgradableContract(
      deployToken.strategyName, 
      params,
      signer
    );
    
    // Deploy IdleCDO with new strategy
    await hre.run("deploy-with-factory", {
      cdoname: args.cdoname,
      cdoVariant: deployToken.cdoVariant,
      proxyCdoAddress: deployToken.proxyCdoAddress,
      strategyAddress: strategy.address,
      strategyName: deployToken.strategyName,
      aaStaking: deployToken.AAStaking,
      bbStaking: deployToken.BBStaking,
      stkAAVEActive: deployToken.stkAAVEActive,
      limit: deployToken.limit,
      aaRatio: deployToken.AARatio,
      isAYSActive: deployToken.isAYSActive,
    });
});
