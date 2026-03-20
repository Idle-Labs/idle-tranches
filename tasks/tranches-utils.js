require("hardhat/config")
const fs = require("fs");
const path = require("path");
const { ethers: etherslib } = require("ethers");
const { BigNumber } = require("@ethersproject/bignumber");
const { getAdminAddress, getImplementationAddress } = require("@openzeppelin/upgrades-core");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const polygonContracts = addresses.IdleTokens.polygon;
const polygonZKContracts = addresses.IdleTokens.polygonZK;
const optimismContracts = addresses.IdleTokens.optimism;
const arbitrumContracts = addresses.IdleTokens.arbitrum;
const baseContracts = addresses.IdleTokens.base;
const avaxContracts = addresses.IdleTokens.avax;
const mainnetCDOs = addresses.CDOs;
const polygonCDOs = addresses.polygonCDOs;
const polygonZKCDOs = addresses.polygonZKCDOs;
const optimismCDOs = addresses.optimismCDOs;
const arbitrumCDOs = addresses.arbitrumCDOs;
const baseCDOs = addresses.baseCDOs;
const avaxCDOs = addresses.avaxCDOs;
const ICurveRegistryAbi = require("../abi/ICurveRegistry.json")
const CV_UPGRADE_PLAN_KIND = "credit-vault-upgrade-batch";
const CV_UPGRADE_PLAN_VERSION = 1;
const CV_UPGRADE_DIR = ".timelock-upgrades";
const CV_COMPONENT_ORDER = ["cdo", "strategy", "queue", "writeoff"];
const PROXY_ADMIN_UPGRADE_IFACE = new etherslib.utils.Interface([
  "function upgrade(address proxy, address implementation)",
]);

const getNetworkContracts = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;
  const isBase = _hre.network.name == 'base' || _hre.network.config.chainId == 8453;
  const isAvax = _hre.network.name == 'avax' || _hre.network.config.chainId == 43114;

  if (isMatic) {
    return polygonContracts;
  } else if (isPolygonZK) {
    return polygonZKContracts;
  } else if (isOptimism) {
    return optimismContracts;
  } else if (isArbitrum) {
    return arbitrumContracts;
  } else if (isBase) {
    return baseContracts;
  } else if (isAvax) {
    return avaxContracts;
  }
  return mainnetContracts;
}

const getDeployTokens = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;
  const isBase = _hre.network.name == 'base' || _hre.network.config.chainId == 8453;
  const isAvax = _hre.network.name == 'avax' || _hre.network.config.chainId == 43114;

  if (isMatic) {
    return addresses.deployTokensPolygon;
  } else if (isPolygonZK) {
    return addresses.deployTokensPolygonZK;
  } else if (isOptimism) {
    return addresses.deployTokensOptimism;
  } else if (isArbitrum) {
    return addresses.deployTokensArbitrum;
  } else if (isBase) {
    return addresses.deployTokensBase;
  } else if (isAvax) {
    return addresses.deployTokensAvax;
  }
  return addresses.deployTokens;
}

const getNetworkCDOs = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;
  const isBase = _hre.network.name == 'base' || _hre.network.config.chainId == 8453;
  const isAvax = _hre.network.name == 'avax' || _hre.network.config.chainId == 43114;

  if (isMatic) {
    return polygonCDOs;
  } else if (isPolygonZK) {
    return polygonZKCDOs;
  } else if (isOptimism) {
    return optimismCDOs;
  } else if (isArbitrum) {
    return arbitrumCDOs;
  } else if (isBase) {
    return baseCDOs;
  } else if (isAvax) {
    return avaxCDOs;
  }
  return mainnetCDOs;
}

const getProviderChainId = async (_hre) => {
  const { chainId } = await _hre.ethers.provider.getNetwork();
  return chainId.toString();
}

const parseCsv = (value) => (value || "")
  .split(",")
  .map(v => v.trim())
  .filter(Boolean);

const normalizeCvUpgradeComponent = (value) => {
  const component = value.toLowerCase();
  if (component === "writeoff" || component === "writeoffescrow" || component === "escrow") {
    return "writeoff";
  }
  if (component === "cdo" || component === "strategy" || component === "queue") {
    return component;
  }
  throw new Error(`Unsupported component "${value}". Allowed values: ${CV_COMPONENT_ORDER.join(", ")}`);
}

const getRequestedCvUpgradeComponents = (rawComponents) => {
  const components = parseCsv(rawComponents).map(normalizeCvUpgradeComponent);
  if (components.length === 0) {
    throw new Error("components must be provided");
  }
  return [...new Set(components)].sort((a, b) => CV_COMPONENT_ORDER.indexOf(a) - CV_COMPONENT_ORDER.indexOf(b));
}

const getRequestedCreditVaultNames = (_hre, networkCDOs, rawNames) => {
  const cdoNames = parseCsv(rawNames);
  if (cdoNames.length === 0) {
    throw new Error("No credit vaults selected. Pass --cdonames name1,name2");
  }

  for (const cdoName of cdoNames) {
    if (!networkCDOs[cdoName]) {
      throw new Error(`Unknown credit vault "${cdoName}" for network ${_hre.network.name}`);
    }
  }

  return [...new Set(cdoNames)].sort();
}

const getCreditVaultCdoContractName = (_hre, deployToken) => {
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;
  const isBase = _hre.network.name == 'base' || _hre.network.config.chainId == 8453;

  let contractName = isPolygonZK ? 'IdleCDOPolygonZK' : 'IdleCDO';
  if (isOptimism) {
    contractName = 'IdleCDOOptimism';
  } else if (isArbitrum) {
    contractName = 'IdleCDOArbitrum';
  } else if (isBase) {
    contractName = 'IdleCDOBase';
  }
  if (deployToken.cdoVariant) {
    contractName = deployToken.cdoVariant;
  }
  return contractName;
}

const getCreditVaultUpgradeTarget = (_hre, networkTokens, networkCDOs, cdoName, component) => {
  const deployToken = networkTokens[cdoName];
  const networkCdo = networkCDOs[cdoName];
  if (!deployToken || !networkCdo) {
    throw new Error(`Missing config for ${cdoName}`);
  }

  const targetByComponent = {
    cdo: {
      contractName: getCreditVaultCdoContractName(_hre, deployToken),
      proxyAddress: networkCdo.cdoAddr,
    },
    strategy: {
      contractName: deployToken.strategyName,
      proxyAddress: networkCdo.strategy,
    },
    queue: {
      contractName: 'IdleCDOEpochQueue',
      proxyAddress: networkCdo.queue,
    },
    writeoff: {
      contractName: 'IdleCreditVaultWriteOffEscrow',
      proxyAddress: networkCdo.writeOff,
    },
  };

  const target = targetByComponent[component];
  if (!target || !target.contractName || !target.proxyAddress || target.proxyAddress === ethers.constants.AddressZero) {
    throw new Error(`${cdoName} does not have a valid ${component} proxy configured`);
  }

  return {
    cdoName,
    component,
    contractName: target.contractName,
    proxyAddress: ethers.utils.getAddress(target.proxyAddress),
  };
}

const getDefaultCvUpgradePlanPath = (_hre) => {
  const fileName = `${_hre.network.name}-cv-upgrades-${Date.now()}.json`;
  return path.join(process.cwd(), CV_UPGRADE_DIR, fileName);
}

const writeCvUpgradePlan = (filePath, plan) => {
  const resolvedPath = path.resolve(filePath);
  if (fs.existsSync(resolvedPath)) {
    throw new Error(`Refusing to overwrite existing plan file ${resolvedPath}`);
  }
  fs.mkdirSync(path.dirname(resolvedPath), { recursive: true });
  fs.writeFileSync(resolvedPath, `${JSON.stringify(plan, null, 2)}\n`);
  return resolvedPath;
}

const readCvUpgradePlan = (filePath) => {
  const resolvedPath = path.resolve(filePath);
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Plan file not found: ${resolvedPath}`);
  }
  return {
    path: resolvedPath,
    plan: JSON.parse(fs.readFileSync(resolvedPath, "utf8")),
  };
}

const formatCvUpgradeContractName = (contractName) => {
  const parts = contractName.split(":");
  return parts[parts.length - 1];
}

const decodeCvUpgradePlanCalls = (plan) => {
  const rows = [];

  for (let i = 0; i < plan.targets.length; i++) {
    const target = plan.targets[i];
    const payload = plan.payloads[i];

    try {
      const [proxyAddress, newImplementation] = PROXY_ADMIN_UPGRADE_IFACE.decodeFunctionData("upgrade", payload);
      rows.push({
        index: i + 1,
        proxyAdmin: etherslib.utils.getAddress(target),
        proxyAddress: etherslib.utils.getAddress(proxyAddress),
        newImplementation: etherslib.utils.getAddress(newImplementation),
      });
    } catch (err) {
      rows.push({
        index: i + 1,
        proxyAdmin: etherslib.utils.getAddress(target),
        rawPayload: payload,
      });
    }
  }

  return rows;
}

const logCvUpgradePlanSummary = (plan, summaryRows = []) => {
  console.log(`Plan type:      ${plan.kind} v${plan.version}`);
  console.log(`Chain id:       ${plan.chainId}`);
  console.log(`Timelock:       ${plan.timelock}`);
  console.log(`Operation id:   ${plan.operationId}`);
  console.log(`Timelock calls: ${plan.targets.length}`);

  if (summaryRows.length > 0) {
    console.log(`Upgrades:       ${summaryRows.length}`);
    for (const [index, row] of summaryRows.entries()) {
      console.log(`${index + 1}. ${row.cdoName} / ${row.component}`);
      console.log(`   proxy:        ${row.proxyAddress}`);
      console.log(`   contract:     ${formatCvUpgradeContractName(row.contractName)}`);
      console.log(`   current impl: ${row.currentImplementation}`);
      console.log(`   new impl:     ${row.newImplementation}`);
    }
    return;
  }

  const decodedCalls = decodeCvUpgradePlanCalls(plan);
  for (const row of decodedCalls) {
    console.log(`${row.index}. proxy admin call`);
    console.log(`   proxy admin:  ${row.proxyAdmin}`);
    if (row.proxyAddress) {
      console.log(`   proxy:        ${row.proxyAddress}`);
      console.log(`   new impl:     ${row.newImplementation}`);
    } else {
      console.log(`   payload:      ${row.rawPayload}`);
    }
  }
}

const buildCvUpgradePlan = async (_hre, { cdoNames, components, signer, timelock }) => {
  const networkTokens = getDeployTokens(_hre);
  const networkCDOs = getNetworkCDOs(_hre);
  const chainId = await getProviderChainId(_hre);
  const timelockAddress = ethers.utils.getAddress(timelock.address);
  const targets = [];

  for (const cdoName of cdoNames) {
    for (const component of components) {
      targets.push(getCreditVaultUpgradeTarget(_hre, networkTokens, networkCDOs, cdoName, component));
    }
  }

  targets.sort((a, b) => {
    if (a.cdoName === b.cdoName) {
      return CV_COMPONENT_ORDER.indexOf(a.component) - CV_COMPONENT_ORDER.indexOf(b.component);
    }
    return a.cdoName.localeCompare(b.cdoName);
  });

  const proxyAdmins = new Map();
  for (const target of targets) {
    target.proxyAdmin = ethers.utils.getAddress(await getAdminAddress(ethers.provider, target.proxyAddress));
    target.currentImplementation = ethers.utils.getAddress(await getImplementationAddress(ethers.provider, target.proxyAddress));

    if (!proxyAdmins.has(target.proxyAdmin)) {
      const proxyAdmin = await ethers.getContractAt("IProxyAdmin", target.proxyAdmin);
      const proxyAdminOwner = ethers.utils.getAddress(await proxyAdmin.owner());
      if (proxyAdminOwner !== timelockAddress) {
        throw new Error(`ProxyAdmin ${target.proxyAdmin} for ${target.cdoName}/${target.component} is owned by ${proxyAdminOwner}, not timelock ${timelockAddress}`);
      }
      proxyAdmins.set(target.proxyAdmin, proxyAdmin);
    }
  }

  const groups = new Map();
  for (const target of targets) {
    const key = `${target.contractName}:${target.currentImplementation}`;
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key).push(target);
  }

  for (const groupTargets of groups.values()) {
    const sample = groupTargets[0];
    let newImplementation = await helpers.prepareContractUpgrade(sample.proxyAddress, sample.contractName, signer);
    newImplementation = ethers.utils.getAddress(newImplementation);
    if (newImplementation === sample.currentImplementation) {
      throw new Error(`Prepared implementation for ${sample.contractName} matches current implementation ${sample.currentImplementation}`);
    }
    for (const target of groupTargets) {
      target.newImplementation = newImplementation;
    }
  }

  const batchTargets = [];
  const batchValues = [];
  const batchPayloads = [];
  for (const target of targets) {
    const proxyAdmin = proxyAdmins.get(target.proxyAdmin);
    batchTargets.push(target.proxyAdmin);
    batchValues.push(0);
    batchPayloads.push(
      proxyAdmin.interface.encodeFunctionData("upgrade", [target.proxyAddress, target.newImplementation])
    );
  }

  const predecessor = ethers.constants.HashZero;
  const salt = ethers.constants.HashZero;
  const delay = (await timelock.getMinDelay()).toString();
  const operationId = await timelock.hashOperationBatch(
    batchTargets,
    batchValues,
    batchPayloads,
    predecessor,
    salt
  );

  return {
    delay,
    summaryRows: targets.map(target => ({
      cdoName: target.cdoName,
      component: target.component,
      contractName: target.contractName,
      proxyAddress: target.proxyAddress,
      currentImplementation: target.currentImplementation,
      newImplementation: target.newImplementation,
    })),
    plan: {
      version: CV_UPGRADE_PLAN_VERSION,
      kind: CV_UPGRADE_PLAN_KIND,
      chainId,
      timelock: timelockAddress,
      operationId,
      predecessor,
      salt,
      targets: batchTargets,
      values: batchValues,
      payloads: batchPayloads,
    },
  };
}

/**
 * @name info
 */
task("info", "IdleCDO info")
  .addParam("cdo")
  .setAction(async (args) => {
    console.log(args.cdo);
    let idleCDO = await ethers.getContractAt("IdleCDO", args.cdo);
    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`AATranche: ${await idleCDO.AATranche()}, BBTranche: ${await idleCDO.BBTranche()}`);
    console.log(`IdleStrategy: ${await idleCDO.strategy()}`);
  });

/**
 * @name upgrade-cdo
 */
task("upgrade-cdo", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];

    const contractAddress = deployToken.cdo.cdoAddr;
    if (!contractAddress) {
      console.log(`IdleCDO Must be deployed`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');
    let contractName = 'IdleCDO';
    if (deployToken.cdoVariant) {
      contractName = deployToken.cdoVariant;
    }
    await helpers.upgradeContract(contractAddress, contractName, signer);
    console.log(`IdleCDO upgraded`);
  });

task("gen-calldata", 'Generate bytes calldata')
  .addParam('contract')
  .addParam('address')
  .addParam('method')
  .addParam('params')
  .setAction(async (args) => {
    const contract = await ethers.getContractAt(args.contract, args.address);
    const calldata = contract.interface.encodeFunctionData(args.method, [args.params]);
    console.log('calldata:', calldata);
  });

/**
 * @name upgrade-cdo-multisig
 */
task("upgrade-cdo-multisig", "Upgrade IdleCDO instance with multisig")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;
    const isBase = hre.network.name == 'base' || hre.network.config.chainId == 8453;
    const isAvax = hre.network.name == 'avax' || hre.network.config.chainId == 43114;

    let contractName = isPolygonZK ? 'IdleCDOPolygonZK' : 'IdleCDO';
    if (isOptimism) {
      contractName = 'IdleCDOOptimism';
    } else if (isArbitrum) {
      contractName = 'IdleCDOArbitrum';
    } else if (isBase) {
      contractName = 'IdleCDOBase';
    } else if (isAvax) {
      contractName = 'IdleCDOAvax';
    }
    if (deployToken.cdoVariant) {
      contractName = deployToken.cdoVariant;
    }
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName,
      contractKey: 'cdoAddr',
      // initMethod: '_init',
      // initParams: []
    });
  });

/**
 * @name upgrade-cdo-multisig-timelock
 */
task("upgrade-cdo-multisig-timelock", "Upgrade IdleCDO instance with multisig timelock module")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;
    const isBase = hre.network.name == 'base' || hre.network.config.chainId == 8453;
    const isAvax = hre.network.name == 'avax' || hre.network.config.chainId == 43114;

    let contractName = isPolygonZK ? 'IdleCDOPolygonZK' : 'IdleCDO';
    if (isOptimism) {
      contractName = 'IdleCDOOptimism';
    } else if (isArbitrum) {
      contractName = 'IdleCDOArbitrum';
    } else if (isBase) {
      contractName = 'IdleCDOBase';
    } else if (isAvax) {
      contractName = 'IdleCDOAvax';
    }
    if (deployToken.cdoVariant) {
      contractName = deployToken.cdoVariant;
    }
    await run("upgrade-with-multisig-timelock", {
      cdoname: args.cdoname,
      contractName,
      contractKey: 'cdoAddr',
      // initMethod: '_init',
      // initParams: []
    });
  });

/**
 * @name upgrade-strategy
 */
task("upgrade-strategy", "Upgrade IdleCDO strategy")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName: deployToken.strategyName,
      contractKey: 'strategy' // check eg CDOs.idleDAI.*
    });
  });

/**
 * @name upgrade-strategy-timelock
 */
task("upgrade-strategy-timelock", "Upgrade IdleCDO strategy")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    
    await run("upgrade-with-multisig-timelock", {
      cdoname: args.cdoname,
      contractName: deployToken.strategyName,
      contractKey: 'strategy' // check eg CDOs.idleDAI.*
    });
  });

/**
 * @name upgrade-queue-timelock
 */
task("upgrade-queue-timelock", "Upgrade IdleCDO queue")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    
    await run("upgrade-with-multisig-timelock", {
      cdoname: args.cdoname,
      contractName: 'IdleCDOEpochQueue',
      contractKey: 'queue' // check eg CDOs.idleDAI.*
    });
  });

/**
 * @name transfer-ownership-cdo
 */
task("transfer-ownership-cdo", "Transfer IdleCDO ownership")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    // #### Change this if needed (avoid passing it via cli)
    const to = getNetworkContracts(_hre).devLeagueMultisig;
    // ####

    console.log('NEW OWNER: ', to);
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    console.log('deployToken', deployToken)
    const proxyAdminAddress = deployToken.cdo.proxyAdmin;
    const contractAddress = deployToken.cdo.cdoAddr;
    const strategyAddress = deployToken.cdo.strategy;
    if (!contractAddress || !strategyAddress || !proxyAdminAddress || !to) {
      console.log(`IdleCDOAddress, to, strategyAddress and proxyAdminAddress Must be defined`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');

    console.log('Transfer ownership of IdleCDOStrategy');
    let strategy = await ethers.getContractAt("IdleStrategy", strategyAddress);
    await strategy.connect(signer).transferOwnership(to);
    console.log('New Owner', await strategy.owner());

    console.log('Transfer ownership of IdleCDO');
    let cdo = await ethers.getContractAt("IdleCDO", contractAddress);
    await cdo.connect(signer).transferOwnership(to);
    console.log('New Owner', await cdo.owner());

    let admin = await ethers.getContractAt("IProxyAdmin", proxyAdminAddress);
    const currProxyOwner = await admin.owner();
    if (currProxyOwner != to) {
      console.log('Transfer owner of proxyAdmin for all');
      await admin.connect(signer).transferOwnership(to);
      console.log('New Owner', await admin.owner());
    }
  });

/**
 * @name pause-cdo-multisig
 */
task("pause-cdo-multisig", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    console.log('deployToken', deployToken)
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    const multisig = await run('get-multisig-or-fake');
    await cdo.connect(multisig).pause();
    console.log('Is Paused ? ', await cdo.paused());
  });

/**
 * @name emergency-shutdown-cdo-multisig
 */
task("emergency-shutdown-cdo-multisig", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    console.log('deployToken', deployToken)
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    const multisig = await run('get-multisig-or-fake');
    await cdo.connect(multisig).emergencyShutdown();
    console.log('Is Paused ? ', await cdo.paused());
    console.log('Allow AA withdraw ? ', await cdo.allowAAWithdraw());
    console.log('Allow BB withdraw ? ', await cdo.allowBBWithdraw());
  });

/**
 * @name test-convex-tranche
 */
task("test-convex-harvest", "Test harvest on convex tranche")
  .addParam('cdoname')
  .setAction(async (args) => {
    const signer = await run('get-multisig-or-fake', {fakeAddress: addresses.idleDeployer});
    const deployToken = addresses.deployTokens[args.cdoname];
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    let strategy = await ethers.getContractAt(deployToken.strategyName, deployToken.cdo.strategy);
    cdo = cdo.connect(signer);
    strategy = strategy.connect(signer);

    let bal = await helpers.getTokenBalance(await cdo.strategyToken(), cdo.address);
    console.log('StrategyTokens', BN(bal).toString());

    const newSigner = await helpers.getSigner();
    await helpers.fundAndDeposit('AA', cdo, newSigner.address, ONE_TOKEN(18));
    
    await run('increase-time-mine', {time: (60 * 60 * 24 * 3).toString()});
    await harvest(cdo, {isFirst: true, paramsType: ['uint256', 'uint256'], params: [1,0]});
    console.log('Apr: ', (await strategy.getApr()).toString());
  });

/**
 * @name change-rewards
 */
task("change-rewards", "Update rewards IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    const multisig = await run('get-multisig-or-fake');

    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];

    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    cdo = cdo.connect(multisig);

    console.log('AA ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.AATranche)).toString());
    console.log('BB ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.BBTranche)).toString());

    // Only Senior (AA) tranches will get IDLE rewards
    await cdo.setStakingRewards(deployToken.cdo.AArewards, addresses.addr0);
    console.log('AA staking ', await cdo.AAStaking());
    console.log('BB staking ', await cdo.BBStaking());

    // Split interest received 10/90 (10% to AA)
    await cdo.setTrancheAPRSplitRatio(BN('10000'))
    console.log('APR split ratio ', (await cdo.trancheAPRSplitRatio()).toString());

    console.log('AA ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.AATranche)).toString());
    console.log('BB ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.BBTranche)).toString());
  });

/**
 * @name find-convex-params
 * find params for a convex strategy (convexPoolId, depositPosition)
 */
task("find-convex-params", "Find depositPosition for depositToken of a convex pool of the given lpToken")
  .addParam('lpToken')
  .addParam('depositToken')
  .setAction(async (args) => {
    const lpToken = args.lpToken;
    const depositToken = args.depositToken;

    const crvReg = await hre.ethers.getContractAt(ICurveRegistryAbi, '0x90e00ace148ca3b23ac1bc8c240c2a7dd9c2d7f5');
    const poolAddr = await crvReg.get_pool_from_lp_token(lpToken);
    const poolName = await crvReg.get_pool_name(poolAddr);
    let coins = await crvReg.get_coins(poolAddr);
    let uCoins = await crvReg.get_underlying_coins(poolAddr);

    const curveWETHAddr = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
    // if a coin is equal to curveWETHAddr then replace the value with the real WETH address
    coins = coins.map(coin => (coin == curveWETHAddr ? mainnetContracts.WETH : coin).toLowerCase());
    uCoins = uCoins.map(coin => (coin == curveWETHAddr ? mainnetContracts.WETH : coin).toLowerCase());

    console.log({ poolName, poolAddr, lpToken, depositToken, coins, uCoins });

    const position = coins.indexOf(depositToken);
    const uPosition = uCoins.indexOf(depositToken);
    
    if (position >= 0) {
      console.log('deposit position: ', position);
    } else if (uPosition >= 0) {
      console.log('deposit position (underlying): ', uPosition);
    } else {
      console.log('deposit token not found in pool');
    }
  });

/**
* @name base58
*/
task("fetch-morpho-rewards-old")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    if (!deployToken.urds.length) {
      console.log("🛑 No URDs defined");
      return;
    }
    console.log('cdoAddr:', cdoAddr);
    console.log('urds:', deployToken.urds);

    for (let i = 0; i < deployToken.urds.length; i++) {
      const urd = deployToken.urds[i];
      console.log('urd:', urd);
      const urdContract = await ethers.getContractAt("IUniversalRewardsDistributor", urd);
      const ipfsHash = await urdContract.ipfsHash();
      // converts hash to base58
      const hash_base58 = ethers.utils.base58.encode(
        // 0x12 is the hash method (sha256), and 0x20 is the data size (32)
        Buffer.from("1220" + ipfsHash.slice(2), "hex")
      );
      const link = `https://dweb.link/ipfs/${hash_base58}`;
      console.log("Ipfs link:", link);
      // fetch json from link
      const response = await fetch(link);
      const json = await response.json();
      // find user reward
      const userRewards = json.rewards[cdoAddr];
      console.log('CDO rewards:', userRewards);
      console.log('---');
    }
  });

task("collect-morpho-rewards")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    console.log('cdoAddr:', cdoAddr);
    const cdoContract = await ethers.getContractAt("IdleCDO", cdoAddr);
    const strategyAddr = await cdoContract.strategy();
    const strategyContract = await ethers.getContractAt("MetaMorphoStrategy", strategyAddr);
    const currentRewards = await strategyContract.getRewardTokens();
    console.log('current rewards: ');
    for (let r = 0; r < currentRewards.length; r++) {
      const reward = currentRewards[r];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward} (${rewardSymbol})`);
    }
    console.log('-----------------');

    // fetch last distributions
    const response = await fetch(`https://rewards.morpho.org/v1/users/${cdoAddr}/distributions`);
    const json = await response.json();

    console.log('reward pages:', json.pagination.total_pages);
    if (json.pagination.totalPages > 1) {
      console.log('WARN: this script supports only 1 page of rewards and there are more!');
    }
    const rewards = json.data;
    const txs = [];
    for (let i = 0; i < rewards.length; i++) {
      const reward = rewards[i];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward.asset.address);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward.asset.address} (${rewardSymbol})`);
      console.log('distributor', reward.distributor.address);
      console.log('amount', reward.claimable);
      // console.log('proof', reward.proof);
      // console.log('txData', reward.tx_data);

      txs.push({
        to: reward.distributor.address,
        value: '0',
        data: reward.tx_data
      })
    }

    if (txs.length == 0) {
      return;
    }
    const signer = await run('get-signer-or-fake');
    await helpers.batchTxsEOA(txs.map(tx => ({ target: tx.to, callData: tx.data })), signer);

    // // do the same with multisig
    // const networkContracts = getNetworkContracts(hre);
    // await helpers.proposeBatchTxsMainnet(networkContracts.devLeagueMultisig, txs);
  });

task("collect-usual-rewards")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    const cdoContract = await ethers.getContractAt("IdleCDOUsualVariant", cdoAddr);
    const strategyAddr = await cdoContract.strategy();
    const strategyContract = await ethers.getContractAt("IdleUsualStrategy", strategyAddr);
    const currentRewards = await strategyContract.getRewardTokens();
    console.log('strategy:', strategyAddr);
    console.log('cdoAddr :', cdoAddr);
    console.log('current rewards: ');
    for (let r = 0; r < currentRewards.length; r++) {
      const reward = currentRewards[r];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward} (${rewardSymbol})`);
    }
    console.log('-----------------');

    const usualDistributor = await ethers.getContractAt("IUsualDistributor", '0x75cc0c0ddd2ccafe6ec415be686267588011e36a');
    const offChainDistrData = await usualDistributor.getOffChainDistributionData();
    const latestRoot = offChainDistrData.merkleRoot;
    console.log('latestRoot ', latestRoot);

    // fetch last distributions
    const response = await fetch(`https://app.usual.money/api/rewards/${strategyAddr}`);
    const rewards = await response.json();
    const claimed = await usualDistributor.getOffChainTokensClaimed(strategyAddr);
    const responseCDO = await fetch(`https://app.usual.money/api/rewards/${cdoAddr}`);
    const rewardsCDO = await responseCDO.json();
    const claimedCDO = await usualDistributor.getOffChainTokensClaimed(cdoAddr);

    const txs = [];
    // If first element root is equal to the latestRoot then we can claim
    // process strategy rewards
    if (rewards.length > 0 && rewards[0].merkleRoot == latestRoot) {
      const reward = rewards[0];
      console.log('amount Strategy', reward.value);
      console.log('receiver Strategy', strategyAddr);
      if (BN(claimed).eq(BN(reward.value))) {
        console.log('Already claimed strategy');
      } else {
        // console.log('proof', reward.merkleProof);
        const data = usualDistributor.interface.encodeFunctionData(
          'claimOffChainDistribution',
          [strategyAddr, reward.value, reward.merkleProof]
        );
        // console.log('data', data);
        txs.push({to: usualDistributor.address, value: '0', data});
      }
    } else {
      console.log('Nothing to claim for strategy');
    }

    // process cdo rewards
    if (rewardsCDO.length > 0 && rewardsCDO[0].merkleRoot == latestRoot) {
      const reward = rewardsCDO[0];
      console.log('amount CDO', reward.value);
      console.log('receiver CDO', cdoAddr);
      // console.log('proof', reward.merkleProof);
      if (BN(claimedCDO).eq(BN(reward.value))) {
        console.log('Already claimed CDO');
      } else {
        const data = usualDistributor.interface.encodeFunctionData(
          'claimOffChainDistribution',
          [cdoAddr, reward.value, reward.merkleProof]
        );
        // console.log('data', data);
        txs.push({to: usualDistributor.address, value: '0', data});
      }
    } else {
      console.log('Nothing to claim for CDO');
    }

    if (txs.length == 0) {
      console.log('No transactions to process.');
      return;
    }
    const signer = await run('get-signer-or-fake');
    await helpers.batchTxsEOA(txs.map(tx => ({ target: tx.to, callData: tx.data })), signer);
  });

task("fetch-morpho-rewards")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    console.log('cdoAddr:', cdoAddr);
    const cdoContract = await ethers.getContractAt("IdleCDO", cdoAddr);
    const strategyAddr = await cdoContract.strategy();
    const strategyContract = await ethers.getContractAt("MetaMorphoStrategy", strategyAddr);
    const currentRewards = await strategyContract.getRewardTokens();
    console.log('current rewards: ');
    for (let r = 0; r < currentRewards.length; r++) {
      const reward = currentRewards[r];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward} (${rewardSymbol})`);
    }
    console.log('-----------------');

    // fetch last distributions
    const response = await fetch(`https://rewards.morpho.org/v1/users/${cdoAddr}/distributions`);
    const json = await response.json();

    console.log('reward pages:', json.pagination.total_pages);
    if (json.pagination.totalPages > 1) {
      console.log('WARN: this script supports only 1 page of rewards and there are more!');
    }
    const rewards = json.data;
    for (let i = 0; i < rewards.length; i++) {
      const reward = rewards[i];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward.asset.address);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward.asset.address} (${rewardSymbol})`);
      console.log('distributor', reward.distributor.address);
      console.log('amount', reward.claimable);
      console.log('proof', reward.proof);
    }
  });

/**
 * @name upgrade-with-multisig
 */
subtask("upgrade-with-multisig", "Upgrade contract with multisig")
  .addParam('cdoname')
  .addParam('contractName')
  .addParam('contractKey')
  .addOptionalParam('initMethod')
  .addOptionalParam('initParams')
  .setAction(async (args) => {
    await run("compile");
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const contractName = args.contractName;

    const contractAddress = deployToken.cdo[args.contractKey];
    console.log(`To upgrade: ${contractName} @ ${contractAddress}`)
    console.log('deployToken', deployToken)

    if (!contractAddress || !contractName) {
      console.log(`contractAddress and contractName must be defined`);
      return;
    }

    await helpers.prompt("continue? [y/n]", true);
    let signer = await run('get-signer-or-fake');
    // deploy implementation with any signer
    let newImpl = await helpers.prepareContractUpgrade(contractAddress, contractName, signer);
    // to checksum address
    newImpl = ethers.utils.getAddress(newImpl);
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    if (isPolygonZK) {
      console.log('PolygonZK: continue with multisig UI');
      return;
    }
  
    signer = await run('get-multisig-or-fake');
    // Use multisig for calling upgrade or upgradeAndCall
    const proxyAdminAddress = deployToken.cdo.proxyAdmin;
    if (!newImpl || !proxyAdminAddress) {
      console.log(`New impl or proxyAdmin address are null`);
      return;
    }

    let admin = await ethers.getContractAt("IProxyAdmin", proxyAdminAddress);
    admin = admin.connect(signer);

    if (args.initMethod) {
      let contract = await ethers.getContractAt(contractName, contractAddress);
      const initMethodCall = contract.interface.encodeFunctionData(args.initMethod, args.initParams || []);
      await admin.upgradeAndCall(contractAddress, newImpl, initMethodCall);
    } else {
      await admin.upgrade(contractAddress, newImpl);
    }

    console.log(`${args.contractKey} (contract: ${contractName}) Upgraded, new impl ${newImpl}`);
  });

/**
* @name upgrade-all-cv-multisig-timelock
*/
task("upgrade-all-cv-multisig-timelock", "Upgrade all credit vaults with multisig timelock module")
  .addOptionalParam('strategy')
  .setAction(async (args) => {
    await run("compile");
    const isStrategy = args.strategy;
    const networkTokens = getDeployTokens(hre);
    const networkContracts = getNetworkContracts(hre);
    let cvNames = Object.keys(addresses.CDOs).filter(name => name.startsWith('credit') && !name.includes('test'));
    // or use a fixed list like this:
    // let cvNames = [
    //   'creditfasanarausdc',
    //   'creditbastionusdc',
    //   'creditadaptivefrontierusdc',
    //   'creditfalconxusdc',
    //   'creditroxusdc',
    //   'creditabraxasv2usdc',
    //   'creditpsalionweth',
    //   'creditpsalionwbtc',
    //   'creditpsalionusdc',
    //   'creditcarpathianweth'
    // ];

    console.log('cvNames', cvNames);
    console.log('isStrategy', isStrategy);
    await helpers.prompt("continue? [y/n]", true);

    if (!networkContracts.timelock || !networkContracts.proxyAdminWithTimelock) {
      console.log('timelock or proxyAdminWithTimelock not defined');
      return;
    }

    // get current signer
    let signer;
    // get timelock
    let timelock = await ethers.getContractAt("Timelock", networkContracts.timelock);
    console.log('Timelock: ', timelock.address);
    // get proxyAdminWithTimelock
    let proxyAdminWithTimelock = await ethers.getContractAt("IProxyAdmin", networkContracts.proxyAdminWithTimelock);
    console.log('ProxyAdmin with timelock: ', proxyAdminWithTimelock.address);

    let newImpl;
    let batchTargets = [];
    let batchValues = [];
    let batchPayloads = [];

    for (let i = 0; i < cvNames.length; i++) {
      const cdoname = cvNames[i];
      const deployToken = networkTokens[cdoname];
      const contractName = deployToken[isStrategy ? "strategyName" : "cdoVariant"];
      const contractAddress = deployToken.cdo[isStrategy ? "strategy" : "cdoAddr"];

      if (!contractAddress || !contractName) {
        console.log(`contractAddress and contractName must be defined`);
        return;
      }

      // deploy new implementation
      // if already deployed newImpl then reuse it
      if (!newImpl) {
        console.log('Deploying new implementation for', contractName);
        // signer = await run('get-signer-or-fake');
        // newImpl = await helpers.prepareContractUpgrade(contractAddress, contractName, signer);
        // // to checksum address
        // newImpl = ethers.utils.getAddress(newImpl);

        if (!isStrategy) {
          // CDO impl
          newImpl = '0x6De6ea8659C8cEa1f2aaf29758E40Ff4C8a1A53F';
        } else {
          // Strategy impl
          newImpl = '0xc499925d7991ff8204967ac58455293f2db3855a';
        }
      }

      console.log(`Upgrading ${cdoname} : ${contractAddress} with new impl ${newImpl}`);

      batchTargets.push(proxyAdminWithTimelock.address);
      batchValues.push(0);
      batchPayloads.push(
        proxyAdminWithTimelock.interface.encodeFunctionData(
          'upgrade', [contractAddress, newImpl]
        )
      );

      console.log('payload', batchPayloads[i]);
      console.log('---');
    }

    if (!newImpl) {
      console.log(`New impl address is null`);
      return;
    }

    signer = await run('get-multisig-or-fake');
    timelock = timelock.connect(signer);
    await timelock.scheduleBatch(
      batchTargets,
      batchValues,
      batchPayloads,
      ethers.constants.HashZero,
      ethers.constants.HashZero,
      await timelock.getMinDelay()
    );

    console.log(`Upgrade queued, new impl ${newImpl}`);
  });

/**
* @name schedule-cv-upgrades-timelock
*/
task("schedule-cv-upgrades-timelock", "Schedule a timelock batch to upgrade selected credit vault components")
  .addParam("cdonames", "Comma-separated credit vault names")
  .addParam("components", "Comma-separated components: cdo,strategy,queue,writeoff")
  .addOptionalParam("out", "Optional output path for the generated plan file")
  .setAction(async (args) => {
    await run("compile");

    const networkContracts = getNetworkContracts(hre);
    if (!networkContracts.timelock) {
      throw new Error("timelock not defined for this network");
    }

    const chainId = await getProviderChainId(hre);
    const cdoNames = getRequestedCreditVaultNames(hre, getNetworkCDOs(hre), args.cdonames);
    const components = getRequestedCvUpgradeComponents(args.components);
    const planPath = path.resolve(args.out || getDefaultCvUpgradePlanPath(hre));
    if (fs.existsSync(planPath)) {
      throw new Error(`Refusing to overwrite existing plan file ${planPath}`);
    }

    console.log(`Network:        ${hre.network.name} (${chainId})`);
    console.log(`Credit vaults:  ${cdoNames.join(", ")}`);
    console.log(`Components:     ${components.join(", ")}`);
    console.log(`Plan path:      ${planPath}`);
    await helpers.prompt("deploy implementations and build the plan? [y/n]", true);

    let timelock = await ethers.getContractAt("Timelock", networkContracts.timelock);
    const signer = await run("get-signer-or-fake");
    const { plan, delay, summaryRows } = await buildCvUpgradePlan(hre, {
      cdoNames,
      components,
      signer,
      timelock,
    });

    logCvUpgradePlanSummary(plan, summaryRows);
    await helpers.prompt("schedule this timelock batch? [y/n]", true);

    const multisigSigner = await run("get-multisig-or-fake");
    timelock = timelock.connect(multisigSigner);
    await timelock.callStatic.scheduleBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt,
      delay
    );

    const tx = await timelock.scheduleBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt,
      delay
    );
    writeCvUpgradePlan(planPath, plan);

    if (tx.hash) {
      console.log(`Schedule tx:     ${tx.hash}`);
    }
    console.log(`Plan written to: ${planPath}`);
  });

/**
* @name execute-cv-upgrades-timelock
*/
task("execute-cv-upgrades-timelock", "Execute a previously scheduled credit vault upgrade timelock batch")
  .addParam("plan", "Path to the plan file created by schedule-cv-upgrades-timelock")
  .setAction(async (args) => {
    const { path: planPath, plan } = readCvUpgradePlan(args.plan);
    if (plan.kind !== CV_UPGRADE_PLAN_KIND || plan.version !== CV_UPGRADE_PLAN_VERSION) {
      throw new Error(`Unsupported plan format in ${planPath}`);
    }
    if (
      !Array.isArray(plan.targets) ||
      !Array.isArray(plan.values) ||
      !Array.isArray(plan.payloads) ||
      plan.targets.length === 0 ||
      plan.targets.length !== plan.values.length ||
      plan.targets.length !== plan.payloads.length
    ) {
      throw new Error(`Invalid batch payload shape in ${planPath}`);
    }

    const currentChainId = await getProviderChainId(hre);
    if (plan.chainId !== currentChainId) {
      throw new Error(`Plan chainId ${plan.chainId} does not match current chainId ${currentChainId}`);
    }

    const networkContracts = getNetworkContracts(hre);
    if (networkContracts.timelock && ethers.utils.getAddress(plan.timelock) !== ethers.utils.getAddress(networkContracts.timelock)) {
      throw new Error(`Plan timelock ${plan.timelock} does not match configured timelock ${networkContracts.timelock}`);
    }

    let timelock = await ethers.getContractAt("Timelock", plan.timelock);
    const operationId = await timelock.hashOperationBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt
    );
    if (operationId !== plan.operationId) {
      throw new Error(`Operation id mismatch for ${planPath}`);
    }
    if (await timelock.isOperationDone(operationId)) {
      throw new Error(`Operation ${operationId} is already executed`);
    }

    const readyAt = await timelock.getTimestamp(operationId);
    if (readyAt.eq(0)) {
      throw new Error(`Operation ${operationId} is not scheduled`);
    }
    if (!(await timelock.isOperationReady(operationId))) {
      throw new Error(`Operation ${operationId} is not ready yet. Ready at ${new Date(Number(readyAt.toString()) * 1000).toISOString()}`);
    }

    logCvUpgradePlanSummary(plan);
    await helpers.prompt("execute this timelock batch? [y/n]", true);

    const executorSigner = await run("get-signer-or-fake");
    timelock = timelock.connect(executorSigner);
    await timelock.callStatic.executeBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt
    );

    const tx = await timelock.executeBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt
    );

    if (tx.hash) {
      console.log(`Execute tx:      ${tx.hash}`);
    }

    console.log(`Executed plan:   ${planPath}`);
  });

/**
 * @name upgrade-with-multisig-timelock
 */
subtask("upgrade-with-multisig-timelock", "Upgrade contract with multisig timelock module")
  .addParam('cdoname')
  .addParam('contractName')
  .addParam('contractKey')
  .addOptionalParam('initMethod')
  .addOptionalParam('initParams')
  .setAction(async (args) => {
    await run("compile");
    const networkTokens = getDeployTokens(hre);
    const networkContracts = getNetworkContracts(hre);
    const deployToken = networkTokens[args.cdoname];
    const contractName = args.contractName;

    const contractAddress = deployToken.cdo[args.contractKey];
    console.log(`To upgrade: ${contractName} @ ${contractAddress}`)
    console.log('deployToken', deployToken)

    if (!contractAddress || !contractName) {
      console.log(`contractAddress and contractName must be defined`);
      return;
    }

    await helpers.prompt("continue? [y/n]", true);
    let signer = await run('get-signer-or-fake');
    // deploy implementation with any signer
    let newImpl = await helpers.prepareContractUpgrade(contractAddress, contractName, signer);
    // to checksum address
    newImpl = ethers.utils.getAddress(newImpl);
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    if (isPolygonZK) {
      console.log('PolygonZK: continue with multisig UI');
      return;
    }

    signer = await run('get-multisig-or-fake');

    // we need to get the timelock and proxyWithTimelock address or exit
    if (!networkContracts.timelock || !networkContracts.proxyAdminWithTimelock) {
      console.log('timelock or proxyAdminWithTimelock not defined');
      return;
    }
    
    let timelock = await ethers.getContractAt("Timelock", networkContracts.timelock);
    timelock = timelock.connect(signer);
    console.log('Timelock: ', timelock.address);

    let proxyAdminWithTimelock = await ethers.getContractAt("IProxyAdmin", deployToken.cdo.proxyAdmin);
    proxyAdminWithTimelock = proxyAdminWithTimelock.connect(signer);
    console.log('ProxyAdmin with timelock: ', proxyAdminWithTimelock.address);
    
    if (!newImpl) {
      console.log(`New impl address is null`);
      return;
    }

    console.log(`Upgrading ${contractName} (addr: ${contractAddress}) with new impl ${newImpl}`);
    const bytes0 = ethers.constants.HashZero;

    if (args.initMethod) {
      let contract = await ethers.getContractAt(contractName, contractAddress);
      const initMethodCall = contract.interface.encodeFunctionData(args.initMethod, args.initParams || []);

      await timelock.schedule(
        proxyAdminWithTimelock.address, // to
        0, // value
        proxyAdminWithTimelock.interface.encodeFunctionData(
          'upgradeAndCall', [contractAddress, newImpl, initMethodCall]
        ), // data
        bytes0, // predecessor (the id of a prev scehduled operation if dependent)
        bytes0, // salt
        await timelock.getMinDelay() // delay
      );
    } else {
      await timelock.schedule(
        proxyAdminWithTimelock.address,
        0,
        proxyAdminWithTimelock.interface.encodeFunctionData(
          'upgrade', [contractAddress, newImpl]
        ),
        bytes0,
        bytes0,
        await timelock.getMinDelay()
      );
    }

    console.log(`${args.contractKey} (contract: ${contractName}) Upgrade queued, new impl ${newImpl}`);
  });

/**
 * @name get-signer-or-fake
 */
subtask("get-signer-or-fake", "Get signer")
  .setAction(async (args) => {
    let signer;
    if (hre.network.name !== 'mainnet' && hre.network.name !== 'matic' && hre.network.name !== 'polygonzk' && hre.network.name !== 'optimism' && hre.network.name !== 'arbitrum' && hre.network.name !== 'base' && hre.network.name !== 'avax') {
      signer = await helpers.impersonateSigner(args.fakeAddress || addresses.idleDeployer);
    } else {
      signer = await helpers.getSigner();
    }
    console.log('Using signer with address: ', await signer.getAddress());
    return signer;
  });

/**
 * @name get-multisig-or-fake
 */
subtask("get-multisig-or-fake", "Get multisig signer")
  .setAction(async (args) => {
    let signer;
    const networkContracts = getNetworkContracts(hre);
    if (hre.network.name !== 'mainnet' && hre.network.name !== 'matic' && hre.network.name !== 'polygonzk' && hre.network.name !== 'optimism' && hre.network.name !== 'arbitrum' && hre.network.name !== 'base' && hre.network.name !== 'avax') {
      signer = await helpers.impersonateSigner(args.fakeAddress || networkContracts.treasuryMultisig);
    } else {
      signer = await helpers.getMultisigSigner();
    }
    console.log('Using signer with address: ', await signer.getAddress());
    return signer;
  });

const harvest = async (cdo, { isFirst, params, paramsType, static, flags } = {isFirst: false, params: [], paramsType: [], static: false, flags: []}) => {
  // encode params for redeemRewards: uint256[], bool[], uint256, uint256
  if (!params || !params.length) {
    params = [
      [1, 1],
      [false, false],
      1,
      1
    ];
    paramsType = ['uint256[]', 'bool[]', 'uint256', 'uint256'];
  }
  const extraData = helpers.encodeParams(paramsType, params);

  if (static) {
    return await helpers.sudoStaticCall(mainnetContracts.rebalancer, cdo, 'harvest', [
      flags.length ? flags : [isFirst, isFirst, isFirst, isFirst], 
      [], [], [],
      extraData
    ]);
  }

  const res = await helpers.sudoCall(mainnetContracts.rebalancer, cdo, 'harvest', [
    flags.length ? flags : [isFirst, isFirst, isFirst, isFirst], 
    [], [], [],
    extraData
  ]);
  
  console.log('Harvest Gas: ', res[2].cumulativeGasUsed.toString());
};

const waitBlocks = async (n) => {
  console.log(`mining ${n} blocks...`);
  for (var i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine");
  };
}
