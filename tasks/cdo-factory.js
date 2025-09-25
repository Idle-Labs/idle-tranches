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
const arbitrumContracts = addresses.IdleTokens.arbitrum;
const mainnetCDOs = addresses.CDOs;
const polygonCDOs = addresses.polygonCDOs;
const polygonZKCDOs = addresses.polygonZKCDOs;
const optimismCDOs = addresses.optimismCDOs;
const arbitrumCDOs = addresses.arbitrumCDOs;

const getNetworkCDOs = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;
  if (isMatic) {
    return polygonCDOs;
  } else if (isPolygonZK) {
    return polygonZKCDOs;
  } else if (isOptimism) {
    return optimismCDOs;
  } else if (isArbitrum) {
    return arbitrumCDOs;
  }
  return mainnetCDOs;
}

const getNetworkContracts = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;
  if (isMatic) {
    return polygonContracts;
  } else if (isPolygonZK) {
    return polygonZKContracts;
  } else if (isOptimism) {
    return optimismContracts;
  } else if (isArbitrum) {
    return arbitrumContracts;
  }
  return mainnetContracts;
}

const getDeployTokens = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;

  if (isMatic) {
    return addresses.deployTokensPolygon;
  } else if (isPolygonZK) {
    return addresses.deployTokensPolygonZK;
  } else if (isOptimism) {
    return addresses.deployTokensOptimism;
  } else if (isArbitrum) {
    return addresses.deployTokensArbitrum;
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
      // best yield / USP contracts
      // USP
      { contractAddress: '0x97cCC1C046d067ab945d3CF3CC6920D3b1E54c88', contractType: 0 },
      // USP queue
      { contractAddress: '0xA7780086ab732C110E9E71950B9Fb3cb2ea50D89', contractType: 0 },
      // sUSP
      { contractAddress: '0x271C616157e69A43B4977412A64183Cf110Edf16', contractType: 0 },

      // tranches
      // lido
      { contractAddress: '0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8', contractType: 1 },
      // instasteth
      { contractAddress: '0x8E0A8A5c1e5B3ac0670Ea5a613bB15724D51Fc37', contractType: 1 },
      // mmusdcsteakusdc
      { contractAddress: '0x87E53bE99975DA318056af5c4933469a6B513768', contractType: 1 },
      // ethenasusde
      { contractAddress: '0x1EB1b47D0d8BCD9D761f52D26FCD90bBa225344C', contractType: 1 },
      // gearboxweth
      { contractAddress: '0xbc48967C34d129a2ef25DD4dc693Cc7364d02eb9', contractType: 1 },
      // gearboxusdc
      { contractAddress: '0xdd4D030A4337CE492B55bc5169F6A9568242C0Bc', contractType: 1 },

      // credit vaults
      // fasanara usdc 
      { contractAddress: '0xf6223C567F21E33e859ED7A045773526E9E3c2D5', contractType: 1 },
      // bastion usdc 
      { contractAddress: '0x4462eD748B8F7985A4aC6b538Dfc105Fce2dD165', contractType: 1 },

      // DEPRECATED BY
      // { contractAddress: '0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80', contractType: 0 },
      // { contractAddress: '0xeC9482040e6483B7459CC0Db05d51dfA3D3068E1', contractType: 0 },
      // { contractAddress: '0xDc7777C771a6e4B3A82830781bDDe4DBC78f320e', contractType: 0 },
      // { contractAddress: '0xfa3AfC9a194BaBD56e743fA3b7aA2CcbED3eAaad', contractType: 0 },
      // { contractAddress: '0x62A0369c6BB00054E589D12aaD7ad81eD789514b', contractType: 0 },

      // DEPRECATED Tranches
      // cpfasusdt
      // { contractAddress: '0xc4574C60a455655864aB80fa7638561A756C5E61', contractType: 1 },
      // cpwincusdc
      // { contractAddress: '0xd12f9248dEb1D972AA16022B399ee1662d51aD22', contractType: 1 },
      // morphoaaveusdc
      // { contractAddress: '0x9C13Ff045C0a994AF765585970A5818E1dB580F8', contractType: 1 },
      // morphoaavedai
      // { contractAddress: '0xDB82dDcb7e2E4ac3d13eBD1516CBfDb7b7CE0ffc', contractType: 1 },
      // morphoaaveusdt
      // { contractAddress: '0x440ceAd9C0A0f4ddA1C81b892BeDc9284Fc190dd', contractType: 1 },
      // morphoaaveweth
      // { contractAddress: '0xb3F717a5064D2CBE1b8999Fdfd3F8f3DA98339a6', contractType: 1 },
      // amphorwsteth
      // { contractAddress: '0x9e0c5ee5e4B187Cf18B23745FCF2b6aE66a9B52f', contractType: 1 },
      // mmwethbbweth
      // { contractAddress: '0x260D1E0CB6CC9E34Ea18CE39bAB879d450Cdd706', contractType: 1 },
      // // cpPOR_USDC
      // { contractAddress: '0x1329E8DB9Ed7a44726572D44729427F132Fa290D', contractType: 1 },
      // // cpPOR_DAI
      // { contractAddress: '0x5dcA0B3Ed7594A6613c1A2acd367d56E1f74F92D', contractType: 1 },
      // // cpfasusdc
      // { contractAddress: '0xE7C6A4525492395d65e736C3593aC933F33ee46e', contractType: 1 },
      // // mmwethre7weth
      // { contractAddress: '0xA8d747Ef758469e05CF505D708b2514a1aB9Cc08', contractType: 1 },
      // // mmwethre7wethfarm
      // { contractAddress: '0xD071EA5D2575E155E4e9c2234968D1E11B8a920E', contractType: 1 },
    ]);
    await tx.wait();
    console.log('Hypernative setup done');
  })

/**
* @name deploy
* deploy factory for CDOs
*/
task("deploy-hypernative-pauser", "Deploy HypernativeBatchPauser")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const networkContracts = getNetworkContracts(hre);
    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    const contractName = "HypernativeBatchPauser";

    console.log("creator: ", creator);
    console.log("network: ", hre.network.name);
    
    const pauser = networkContracts.hypernativePauserEOA;
    const protectedContracts = [
    ];
    console.log("Params :");
    console.log("pauser: ", pauser);
    console.log("protectedContracts: ", protectedContracts);

    await helpers.prompt("continue? [y/n]", true);

    const contract = await helpers.deployContract(contractName, [pauser, protectedContracts], signer);
    console.log(`${contractName} deployed at ${contract.address}`);
  
    await run("verify:verify", {
      constructorArguments: [pauser, protectedContracts],
      address: contract.address,
      contract: "contracts/HypernativeBatchPauser.sol:HypernativeBatchPauser"
    });

    return contract.address;
  });

/**
 * @name deploy
 * deploy factory for CDOs
 */
task("deploy-generic-contract", "Deploy generic contract")
  .addParam('contractname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const contractName = args.contractname;
    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    console.log("creator: ", creator);
    console.log("network: ", hre.network.name);
    console.log("contractName: ", contractName);
    await helpers.prompt("continue? [y/n]", true);

    const contractAddr = await helpers.deployContract(contractName, [], signer);
    console.log(`${contractName} deployed at ${contractAddr}`);
    return contractAddr;
  });

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
  .setAction(async (args) => {
    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    let proxyAdminAddress = args.proxyAdmin;
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;

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
    console.log()
    
    await helpers.prompt("continue? [y/n]", true);
    
    let cdoFactory = await ethers.getContractAt("IdleCDOFactory", cdoFactoryAddress, signer);
    cdoFactory = cdoFactory.connect(signer);
    let contractName = isMatic ? "IdleCDOPolygon" : "IdleCDO";
    if (isPolygonZK) {
      contractName = "IdleCDOPolygonZK";
    } else if (isOptimism) {
      contractName = "IdleCDOOptimism";
    } else if (isArbitrum) {
      contractName = "IdleCDOArbitrum";
    }
    const idleCDO = await ethers.getContractAt(contractName, cdoImplementationAddress, signer);
    
    const initMethodCall = idleCDO.interface.encodeFunctionData("initialize", [
      limit,
      underlyingAddressCDO,
      governanceFund, // recovery address
      creator, // guardian
      networkContracts.rebalancer,
      strategyAddress,
      trancheAPRSplitRatio
    ]);
    
    console.log("deploying with factory...");
    let res = await cdoFactory.deployCDO(cdoImplementationAddress, proxyAdminAddress, initMethodCall);
    res = await res.wait();
    const cdoDeployFilter = cdoFactory.filters.CDODeployed;
    const events = await cdoFactory.queryFilter(cdoDeployFilter, "latest");
    console.log('events', events);
    console.log('res.events', res.events);
    const proxyAddress = res.events[7].args.proxy;
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
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;

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
    const creator = await signer.getAddress();
    let networkCDOName = isMatic ? 'IdleCDOPolygon' : 'IdleCDO';
    if (isPolygonZK) {
      networkCDOName = 'IdleCDOPolygonZK';
    } else if (isOptimism) {
      networkCDOName = 'IdleCDOOptimism';
    } else if (isArbitrum) {
      networkCDOName = 'IdleCDOArbitrum';
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
          BN(args.aaRatio) // apr split: 10% interest to AA and 90% BB
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
      }
      idleCDOAddress = await hre.run("deploy-cdo-with-factory", deployParams);
    }

    const idleCDO = await ethers.getContractAt(contractName, idleCDOAddress, signer);
    console.log('owner idleCDO', await idleCDO.owner());

    const AAaddr = await idleCDO.AATranche();
    const BBaddr = await idleCDO.BBTranche();
    console.log(`AATranche: ${AAaddr}, BBTranche: ${BBaddr}`);
    console.log()

    if (strategy.setWhitelistedCDO) {
      console.log("Setting whitelisted CDO");
      await strategy.connect(signer).setWhitelistedCDO(idleCDO.address);
    }

    const ays = await idleCDO.isAYSActive();
    if (args.isAYSActive != ays) {
      console.log("Toggling AYS");
      await idleCDO.connect(signer).setIsAYSActive(args.isAYSActive);
    }
    console.log(`isAYSActive: ${await idleCDO.isAYSActive()}`);

    if (deployToken.rewardsData && deployToken.rewardsData.length > 0) {
      console.log('setting metamorpho rewards data');
      for (let i = 0; i < deployToken.rewardsData.length; i++) {
        const data = deployToken.rewardsData[i];
        console.log('setting reward data', { id: data.id, sender: data.sender, urd: data.urd, reward: data.reward, marketId: data.marketId, uniV3Path: data.uniV3Path});
        await strategy.connect(signer).setRewardData(data.id, data.sender, data.urd, data.reward, data.marketId, data.uniV3Path);
      }
    }

    const feeReceiver = await idleCDO.feeReceiver();
    if ((isMatic || isPolygonZK || isOptimism || isArbitrum) && feeReceiver.toLowerCase() != networkContracts.feeReceiver.toLowerCase()) {
      console.log('Setting fee receiver to Treasury Multisig')
      await idleCDO.connect(signer).setFeeReceiver(networkContracts.feeReceiver);
    }

    if (deployToken.unlent == 0) {
      console.log('Setting unlent to 0')
      await idleCDO.connect(signer).setUnlentPerc(0);
    }

    if (deployToken.farmTranche) {
      console.log('Farming CDO: Setting loss always socialized')
      await idleCDO.connect(signer).setLossToleranceBps(100000);
    }

    if (deployToken.isCreditVault) {
      console.log('Setting credit vault');
      let cdoEpoch;
      if (isOptimism) {
        cdoEpoch = await ethers.getContractAt('IdleCDOEpochVariantOptimism', idleCDOAddress, signer);
      } else {
        cdoEpoch = await ethers.getContractAt('contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant', idleCDOAddress, signer);
      }
      if (deployToken.epochDuration || deployToken.bufferPeriod) {
        console.log(`Setting epoch duration to ${deployToken.epochDuration}, buffer period to ${deployToken.bufferPeriod}`);
        await cdoEpoch.connect(signer).setEpochParams(BN(deployToken.epochDuration), BN(deployToken.bufferPeriod));
      }
      if (deployToken.disableInstantWithdraw || deployToken.instantWithdrawDelay || deployToken.instantWithdrawAprDelta) {
        console.log(`Setting instant withdraw params disable: ${deployToken.disableInstantWithdraw}, instant delay: ${deployToken.instantWithdrawDelay}, instant apr delta ${deployToken.instantWithdrawAprDelta}`);
        await cdoEpoch.connect(signer).setInstantWithdrawParams(
          BN(deployToken.instantWithdrawDelay), 
          BN(deployToken.instantWithdrawAprDelta), 
          deployToken.disableInstantWithdraw
        );
      }
      if (deployToken.keyring) {
        console.log(`Setting keyring ${deployToken.keyring}, policy ${deployToken.keyringPolicy}`);
        await cdoEpoch.connect(signer).setKeyringParams(deployToken.keyring, deployToken.keyringPolicy, deployToken.keyringAllowWithdraw);
      }
      if (deployToken.fees) {
        console.log(`Setting fees ${deployToken.fees}`);
        await cdoEpoch.connect(signer).setFee(deployToken.fees);
      }
      if (deployToken.queue) {
        await hre.run("deploy-queue", { cdo: idleCDOAddress, owner: networkContracts.treasuryMultisig, isaa: 'true' });
      }
    }

    console.log(`Set guardian of CDO to Pause multisig ${networkContracts.pauserMultisig}`);
    await idleCDO.connect(signer).setGuardian(networkContracts.pauserMultisig);
    
    console.log(`Transfer ownership of strategy to DL multisig ${networkContracts.devLeagueMultisig}`);
    await strategy.connect(signer).transferOwnership(networkContracts.devLeagueMultisig);

    console.log(`Transfer ownership of CDO to TL multisig ${networkContracts.treasuryMultisig}`);
    await idleCDO.connect(signer).transferOwnership(networkContracts.treasuryMultisig);

    await hre.run("protect-cdo", { cdo: idleCDOAddress });
    
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

task("protect-cdo", "Add cdo to hypernative pauser module")
  .addParam('cdo')
  .setAction(async (args) => {
    const networkContracts = getNetworkContracts(hre); 
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;
    const signer = await helpers.getSigner();

    const cdoAddress = args.cdo;
    if (!cdoAddress) {
      console.log("🛑 cdo address must be specified");
      return;
    }

    // In mainnet
    if (!(isMatic || isPolygonZK || isOptimism || isArbitrum)) {
      const pauseModule = new ethers.Contract(networkContracts.hypernativeModule, HypernativeModuleAbi, signer);
      console.log(`Setting contract to hypernative pauser module ${networkContracts.hypernativeModule}`);
      const tx = await pauseModule.updateProtectedContracts([{
        contractAddress: cdoAddress,
        contractType: 1 // tranche contract
      }]);
      await tx.wait();
      console.log('isContractProtected: ', await pauseModule.isContractProtected(cdoAddress));
      console.log(`IMPORTANT: manually add contract to watchlists in hypernative module`);
    }

    if (networkContracts.hypernativePauserEOA) {
      const pauseModule = await ethers.getContractAt("HypernativeBatchPauser", networkContracts.pauserMultisig, signer);
      console.log(`Setting contract to hypernative batch pauser ${networkContracts.pauserMultisig}`);
      const tx = await pauseModule.addProtectedContracts([cdoAddress]);
      await tx.wait();

      // This contract do not have `isContractProtected` method so we try to get first 20 protected contracts
      // if it reverts it means that we reached the end of the list, the last contract should be the idleCDO
      // that we just deployed
      let contractProtected;
      for (let i = 0; i < 20; i++) {
        try {
          contractProtected = await pauseModule.protectedContracts(i);
        } catch (error) {
          // This should be the contract we just added
          contractProtected = await pauseModule.protectedContracts(i - 1);
          break;
        }
      }

      console.log('isContractProtected: ', contractProtected.toLowerCase() == cdoAddress.toLowerCase());
      console.log(`IMPORTANT: manually add contract to watchlists in hypernative module`);
    }
  });

task("watch-cdo", "Add cdo to hypernative watchlists and Custom agents")
  .addParam('cdo')
  .addParam('name')
  .addParam('id', 'id of the watchlist to add the cdo to')
  .setAction(async (args) => {
    console.log(`Adding CDO ${args.cdo} (${args.name}) to hypernative watchlists with id ${args.id}`);
    const clientId = process.env.HYPERNATIVE_CLIENT_ID;
    const clientSecret = process.env.HYPERNATIVE_CLIENT_SECRET;
    if (!clientId || !clientSecret) {
      console.log('🛑 HYPERNATIVE_CLIENT_ID and HYPERNATIVE_CLIENT_SECRET env vars must be set');
      return;
    }
    if (!args.cdo || !args.id || !args.name) {
      console.log('🛑 cdo id name params must be set');
      return;
    }

    try {
      const res = await fetch(`https://api.hypernative.xyz/watchlists/${args.id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'accept': 'application/json',
          'x-client-id': clientId,
          'x-client-secret': clientSecret,
        },
        body: JSON.stringify({
          assets: [{
            "chain": "ethereum",
            "type": "Contract",
            "address": args.cdo
          }],
          mode: 'add'
        })
      });
      if (!res.ok) {
        const responseBody = await res.text();
        throw new Error(`Error adding CDO to watchlist: ${res.status} ${res.statusText} ${responseBody}`);
      }
      console.log(`Added CDO to watchlist ${args.id}`);

      // Update hypernative tag for the cdo
      const res2 = await fetch(`https://api.hypernative.xyz/lists/4ad4b133-2c72-42d4-9f79-a74c9f3ba20a`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'accept': 'application/json',
          'x-client-id': clientId,
          'x-client-secret': clientSecret,
        },
        body: JSON.stringify({
          assets: [{
            "chain": "ethereum",
            "note": `[ETH] credit ${args.name}`,
            "address": args.cdo
          }],
          mode: 'add'
        })
      });
      if (!res2.ok) {
        const responseBody = await res2.text();
        throw new Error(`Error adding tag to CDO: ${res2.status} ${res2.statusText} ${responseBody}`);
      }
      console.log(`Added CDO tag ${args.name}`);
    } catch (error) {
      console.log('Error adding CDO to watchlist', error.message);
    }
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

/**
 * @name deploy-cv-with-factory
 * task to deploy CDO with strategy, staking rewards via factory with all params from utils/addresses.js
 * This can be used only for standard credit vaults (IdleCDOEpochVariant) and standard strategies (IdleCreditVault)
 */
task("deploy-cv-with-factory", "Deploy IdleCDOEpochVariant with associated strategy")
  .addParam('cdoname')
  .addParam('copyname')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");
    // Check that cdoname is passed
    if (!args.cdoname || !args.copyname) {
      console.log("🛑 cdoname and copyname must be defined");
      return;
    }
    
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const networkContracts = getNetworkContracts(hre);
    const networkCDOs = getNetworkCDOs(hre);
    const deployToken = networkTokens[args.cdoname];
    const proxyAdmin = networkContracts.proxyAdmin;
    const copyToken = networkCDOs[args.copyname];
    const addr0 = '0x0000000000000000000000000000000000000000';

    // Check that args has strategyName and strategyParams
    if (!proxyAdmin || !deployToken.strategyParams) {
      console.log("🛑 proxyAdmin and strategyParams must be specified");
      return;
    }

    // Get signer
    const signer = await helpers.getSigner();
    // const signer = await helpers.getSigner("0xE5Dab8208c1F4cce15883348B72086dBace3e64B");
    const addr = await signer.getAddress();
    console.log(`Deploying with ${addr}`);
    console.log()

    const factoryAddr = networkContracts.creditVaultFactory;

    console.log("ProxyAdmin:              ", proxyAdmin);
    console.log("Copy CDO:                ", copyToken.cdoAddr);
    console.log("Copy Strategy:           ", copyToken.strategy);
    console.log("Factory:                 ", factoryAddr);
    
    // Replace owner as last param
    const params = deployToken.strategyParams.map(
      p => p === 'owner' ? addr : p
    );

    const apr = params[params.length - 1];
    console.log('APR:                     ', apr.toString());

    // replace owner address with factory address 
    params[1] = factoryAddr;

    const strategyCopy = await ethers.getContractAt("IdleCreditVault", copyToken.strategy);
    const strategyData = {
      implementation: await getImplementationAddress(hre.ethers.provider, copyToken.strategy),
      proxyAdmin,
      initializeData: strategyCopy.interface.encodeFunctionData("initialize", params)
    };

    console.log('Strategy data for IdleCDOEpochVariant:');
    console.log("Strategy implementation: ", strategyData.implementation);
    console.log("Strategy params:         ", params);
    console.log("Strategy initialize data: ", strategyData.initializeData);
    console.log()
    const hypernative = deployToken.hypernative;
    console.log("Hypernative:             ", hypernative);

    const cvParams = [
      BN(deployToken.limit).mul(ONE_TOKEN(deployToken.decimals)), // limit
      deployToken.underlying,
      networkContracts.treasuryMultisig, // recovery address
      hypernative ? networkContracts.pauserMultisig : networkContracts.treasuryMultisig, // guardian
      networkContracts.rebalancer,
      addr0, // strategy address will be set in the contract directly
      BN(deployToken.AARatio) // apr split: 10% interest to AA and 90% BB
    ];
    const cvCopy = await ethers.getContractAt("IdleCDOEpochVariant", copyToken.cdoAddr);
    const cvData = {
      implementation: await getImplementationAddress(hre.ethers.provider, copyToken.cdoAddr),
      proxyAdmin,
      initializeData: cvCopy.interface.encodeFunctionData("initialize", cvParams)
    };

    console.log('Credit Vault data for IdleCDOEpochVariant:');
    console.log("Credit Vault implementation: ", cvData.implementation);
    console.log("Credit Vault params:         ", cvParams);
    console.log("Credit vault initialize data: ", cvData.initializeData);
    console.log()

    const epochDuration = deployToken.epochDuration || 604800; // default 7 day
    const bufferPeriod = deployToken.bufferPeriod || 43200; // default 12 hour
    console.log(`Setting epoch duration to ${epochDuration}, buffer period to ${bufferPeriod}`);
    const instantWithdrawDelay = deployToken.instantWithdrawDelay || 3600; // default 1 hour
    const instantWithdrawAprDelta = deployToken.instantWithdrawAprDelta || BN(1e18); // default 0
    const disableInstantWithdraw = deployToken.disableInstantWithdraw || false; // default false
    console.log(`Setting instant withdraw params disable: ${disableInstantWithdraw}, instant delay: ${instantWithdrawDelay}, instant apr delta ${instantWithdrawAprDelta}`);
    const keyring = deployToken.keyring;
    const keyringPolicy = deployToken.keyringPolicy;
    const keyringAllowWithdraw = deployToken.keyringAllowWithdraw;
    console.log(`Setting keyring ${keyring}, policy ${keyringPolicy}, allow withdraw ${keyringAllowWithdraw}`);
    const fees = deployToken.fees;
    console.log(`Setting fees ${fees}`);
    console.log(`Has queue: ${deployToken.queue}`);
    let queueImplementation;
    if (deployToken.queue) {
      queueImplementation = await getImplementationAddress(hre.ethers.provider, copyToken.queue);
      console.log(`Queue implementation: ${queueImplementation}`);
    }
    console.log()

    // const owner = '0xE5Dab8208c1F4cce15883348B72086dBace3e64B';
    const owner = networkContracts.treasuryMultisig;
    console.log('Owner of all contracts: ', owner);

    const factory = await ethers.getContractAt("IdleCreditVaultFactory", factoryAddr, signer);
    console.log(`Deploying contracts via factory at ${factoryAddr}`);
    const creditVaultPostInitParams = {
      apr,
      epochDuration,
      bufferPeriod,
      instantWithdrawDelay,
      instantWithdrawAprDelta,
      disableInstantWithdraw,
      keyring,
      keyringPolicy,
      keyringAllowWithdraw,
      fees, 
    }
    const tx = await factory.connect(signer).deployCreditVault(
      cvData, 
      strategyData,
      creditVaultPostInitParams,
      queueImplementation ? queueImplementation : addr0, // if queue is not defined, use zero address
      owner
    );
    const receipt = await tx.wait();

    // get tx return values
    const [cv] = receipt.events.find(e => e.event === "CreditVaultDeployed").args;
    const [strategy] = receipt.events.find(e => e.event === "StrategyDeployed").args;
    console.log('Credit Vault deployed at  ', cv);
    console.log('Strategy deployed at      ', strategy);

    await hre.run("verify-contract", { address: cv });
    await hre.run("verify-contract", { address: strategy });

    let queue;
    if (deployToken.queue) {
      [queue] = receipt.events.find(e => e.event === "QueueDeployed").args;
      console.log('Queue deployed at         ', queue);
      await hre.run("verify-contract", { address: queue });
    }

    if (hypernative) {
      console.log('Adding Credit Vault to hypernative pauser module');
      const strategyContract = await ethers.getContractAt("IdleCreditVault", strategy, signer);
      const name = await strategyContract.symbol();
      await hre.run("protect-cdo", { cdo: cv });
      await hre.run("watch-cdo", { cdo: cv, id: '658', name }); // eth watch
      await hre.run("watch-cdo", { cdo: cv, id: '899', name }); // eth auto pause
      await hre.run("watch-cdo", { cdo: cv, id: '12849', name }); // cross chain auto pause
    }

    if (deployToken.queue && deployToken.keyring != addr0) {
      console.log(`Whitelisting queue in KeyringWhitelist if exists`);
      if (networkContracts.keyringWhitelist) {
        console.log(`Adding queue to keyring whitelist (${networkContracts.keyringWhitelist})`);
        const whitelist = await ethers.getContractAt("KeyringWhitelist", networkContracts.keyringWhitelist, signer);
        await whitelist.connect(signer).setWhitelistStatus(queue, true);
      }
    }

    if (deployToken.writeoff) {
      console.log('Deploying write off escrow');
      await hre.run("deploy-writeoff-escrow", { cdo: cv });
    }

    await hre.run("print-contracts-info", { cdo: cv, strategy, queue });
});

task("print-contracts-info", "Prints deployed contracts info")
  .addOptionalParam('cdo', 'Cdo address')
  .addOptionalParam('strategy', 'Strategy address')
  .addOptionalParam('queue', 'Queue address')
  .setAction(async (args) => {
    console.log('Printing contracts info');
    const cdo = args.cdo ? await ethers.getContractAt("IdleCDOEpochVariant", args.cdo) : null;
    const strategy = args.strategy ? await ethers.getContractAt("IdleCreditVault", args.strategy) : null;
    const queue = args.queue ? await ethers.getContractAt("IdleCDOEpochQueue", args.queue) : null;
    if (cdo) {
      const [
        owner,
        guardian,
        aaTrancheData,
        bbTrancheData,
        underlyingData,
        strategyAddress,
        feeReceiver,
        isAYSActive,
        epochDuration,
        bufferPeriod,
        feeValue,
        instantDisabled,
        aprDelta,
        instantDelay,
        keyringPolicy,
      ] = await Promise.all([
        cdo.owner(),
        cdo.guardian(),
        (async () => {
          const address = await cdo.AATranche();
          const tranche = await ethers.getContractAt("IERC20Detailed", address);
          const [name, symbol] = await Promise.all([tranche.name(), tranche.symbol()]);
          return { address, name, symbol };
        })(),
        (async () => {
          const address = await cdo.BBTranche();
          const tranche = await ethers.getContractAt("IERC20Detailed", address);
          const [name, symbol] = await Promise.all([tranche.name(), tranche.symbol()]);
          return { address, name, symbol };
        })(),
        (async () => {
          const address = await cdo.token();
          const tokenContract = await ethers.getContractAt("IERC20Detailed", address);
          const [name, decimals] = await Promise.all([tokenContract.name(), tokenContract.decimals()]);
          return { address, name, decimals };
        })(),
        cdo.strategy(),
        cdo.feeReceiver(),
        cdo.isAYSActive(),
        cdo.epochDuration(),
        cdo.bufferPeriod(),
        cdo.fee(),
        cdo.disableInstantWithdraw(),
        cdo.instantWithdrawAprDelta(),
        cdo.instantWithdrawDelay(),
        cdo.keyringPolicyId(),
      ]);
      console.log(`CDO at ${cdo.address}`);
      console.log(`  Owner:          ${owner}`);
      console.log(`  Guardian:       ${guardian}`);
      console.log(`  Underlying:     ${underlyingData.address} (${underlyingData.name} ${underlyingData.decimals} decimals)`);
      console.log(`  AATranche:      ${aaTrancheData.address}`);
      console.log(`       Name:      ${aaTrancheData.name}`);
      console.log(`       Symbol:    ${aaTrancheData.symbol}`);
      console.log(`  BBTranche:      ${bbTrancheData.address}`);
      console.log(`       Name:      ${bbTrancheData.name}`);
      console.log(`       Symbol:    ${bbTrancheData.symbol}`);
      console.log(`  Strategy:       ${strategyAddress}`);
      console.log(`  FeeReceiver:    ${feeReceiver}`);
      console.log(`  isAYSActive:    ${isAYSActive}`);
      console.log(`  EpochDuration:  ${epochDuration}`);
      console.log(`  BufferPeriod:   ${bufferPeriod}`);
      console.log(`  Fees:           ${feeValue}`);
      console.log(`  Instant disable:${instantDisabled}`);
      console.log(`  APR Delta:      ${aprDelta}`);
      console.log(`  Instant Delay:  ${instantDelay}`);
      console.log(`  Keyring Policy: ${keyringPolicy}`);

      console.log(``);
    }
    if (strategy) {
      const [
        owner,
        underlyingData,
        tokenDecimals,
        borrower,
        manager,
        whitelistedCdo,
        apr,
        unscaledApr,
      ] = await Promise.all([
        strategy.owner(),
        (async () => {
          const address = await strategy.token();
          const tokenContract = await ethers.getContractAt("IERC20Detailed", address);
          const [name, decimals] = await Promise.all([tokenContract.name(), tokenContract.decimals()]);
          return { address, name, decimals };
        })(),
        strategy.tokenDecimals(),
        strategy.borrower(),
        strategy.manager(),
        strategy.idleCDO(),
        strategy.getApr(),
        strategy.unscaledApr(),
      ]);
      console.log(`Strategy at ${strategy.address}`);
      console.log(`  Owner:          ${owner}`);
      console.log(`  Underlying:     ${underlyingData.address} (${underlyingData.name} ${underlyingData.decimals} decimals)`);
      console.log(`  Decimals:       ${tokenDecimals}`);
      console.log(`  Borrower:       ${borrower}`);
      console.log(`  Manager:        ${manager}`);
      console.log(`  Whitelisted CDO:${whitelistedCdo}`);
      console.log(`  APR:            ${apr}`);
      console.log(`  Unscaled APR:   ${unscaledApr}`);
      console.log(``);
    }
    if (queue) {
      const [owner, epochCdo, underlying, tranche, queueAllowed] = await Promise.all([
        queue.owner(),
        queue.idleCDOEpoch(),
        queue.underlying(),
        queue.tranche(),
        cdo.isWalletAllowed(args.queue),
      ]);
      console.log(`Queue at ${queue.address}`);
      console.log(`  Owner:          ${owner}`);
      console.log(`  CDO:            ${epochCdo}`);
      console.log(`  Underlying:     ${underlying}`);
      console.log(`  Tranche:        ${tranche}`);
      console.log(`  Queue allowed:  ${queueAllowed}`);
      console.log(``);
    }
  });

task("verify-contract", "Verify contract on Etherscan")
  .addParam('address', 'Contract address to verify')
  .setAction(async (args) => {
    console.log(`Verifying contract at ${args.address}`);
    try {
      await run("verify:verify", {
        address: args.address,
        constructorArguments: []
      });
    } catch (error) {
      console.error(error);
    }
});

/**
 * @name deploy-queue
 * task to deploy IdleCDOEpochQueue for a credit vault
 */
task("deploy-queue", "Deploy IdleCDOEpochQueue")
  .addParam('cdo')
  .addOptionalParam('owner')
  .addOptionalParam('isaa')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");
    // Check that cdo is passed
    if (!args.cdo) {
      console.log("🛑 cdo address must be defined");
      return;
    }

    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();

    console.log(`Deploying with ${addr}`);
    console.log()

    const params = [
      args.cdo, 
      args.owner || '0xE5Dab8208c1F4cce15883348B72086dBace3e64B', 
      args.isaa || true
    ];

    console.log('Params for IdleCDOEpochQueue', params);

    // Deploy queue contract
    const queue = await helpers.deployUpgradableContract(
      'IdleCDOEpochQueue',
      params,
      signer
    );

    const networkContracts = getNetworkContracts(hre);
    const multisig = await run('get-multisig-or-fake');

    if (networkContracts.keyringWhitelist) {
      console.log(`Adding queue to keyring whitelist (${networkContracts.keyringWhitelist})`);
      const whitelist = await ethers.getContractAt("KeyringWhitelist", networkContracts.keyringWhitelist, multisig);
      await whitelist.connect(multisig).setWhitelistStatus(queue.address, true);
    }
});

/**
 * @name deploy-writeoff-escrow
 * task to deploy IdleCDOEpochQueue for a credit vault
 */
task("deploy-writeoff-escrow", "Deploy IdleCreditVaultWriteOffEscrow")
  .addParam('cdo')
  .addOptionalParam('owner')
  .addOptionalParam('isaa')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");
    // Check that cdo is passed
    if (!args.cdo) {
      console.log("🛑 cdo address must be defined");
      return;
    }

    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();

    console.log(`Deploying with ${addr}`);
    console.log()

    const params = [
      args.cdo,
      args.owner || '0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814',
      args.isaa || true
    ];

    console.log('Params for IdleCreditVaultWriteOffEscrow', params);

    // Deploy write off escrow contract
    const queue = await helpers.deployUpgradableContract(
      'IdleCreditVaultWriteOffEscrow',
      params,
      signer
    );
  });

/**
 * @name deploy-proxy-admin
 * task to deploy ProxyAdmin
 */
task("deploy-proxy-admin", "Deploy ProxyAdmin")
  .addOptionalParam('owner')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");

    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();

    console.log(`Deploying ProxyAdmin with ${addr}`);
    console.log()

    const proxyAdmin = await helpers.deployContract('ProxyAdmin', [], signer);

    if (args.owner) {
      console.log(`Transferring ownership to ${args.owner}`);
      await proxyAdmin.transferOwnership(args.owner);
    }
});

/**
 * @name deploy-cv-factory
 * task to deploy ProxyAdmin
 */
task("deploy-cv-factory", "Deploy IdleCreditVaultFactory")
  .setAction(async (args) => {
    // Run compile task
    await run("compile");

    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();

    console.log(`Deploying IdleCreditVaultFactory with ${addr}`);
    console.log()

    const creditVaultFactory = await helpers.deployContract('IdleCreditVaultFactory', [], signer);
    console.log(`IdleCreditVaultFactory deployed at ${creditVaultFactory.address}`);
});

/**
 * @name deploy-keyring-whitelist
 * task to deploy KeyringIdleWhitelist
 */
task("deploy-keyring-whitelist", "Deploy KeyringIdleWhitelist")
  .addOptionalParam('owner')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");

    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();

    console.log(`Deploying KeyringIdleWhitelist with ${addr}`);
    console.log()

    const keyringAddress = "0xb0B5E2176E10B12d70e60E3a68738298A7DFe666";
    console.log(`Ownership: ${args.owner}`);
    console.log(`Keyring address: ${keyringAddress}`);
    await helpers.deployContract('KeyringIdleWhitelist', 
      [keyringAddress, args.owner], 
      signer
    );
});

/**
 * @name deploy-timelock
 * task to deploy Timelock
 */
task("deploy-timelock", "Deploy Timelock")
  .addOptionalParam('delay')
  .setAction(async (args) => {
    // Run compile task
    await run("compile");

    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();
    const networkContracts = getNetworkContracts(hre);
    const delay = args.delay;

    if (!delay) {
      console.log("🛑 delay must be specified");
      return;
    }

    console.log(`Deploying Timelock (delay ${delay}s) with ${addr}`);
    console.log()
    
    const deployer = networkContracts.deployer;
    const tlMultisig = networkContracts.treasuryMultisig;
    const biafAddr = '0xeA173648F959790baea225cE3E75dF8A53a6BDE5';
    console.log(`Treasury multisig: ${tlMultisig}`);

    const proposers = [deployer, tlMultisig];
    const executors = [deployer, tlMultisig, biafAddr];
    const owner = tlMultisig;
    console.log('Proposers: ', proposers);
    console.log('Executors: ', executors);
    console.log('Owner: ', owner);

    const params = [delay, proposers, executors, owner];
    const contract = await helpers.deployContract('Timelock', params, signer);

    await run("verify:verify", {
      constructorArguments: params,
      address: contract.address,
      contract: "contracts/Timelock.sol:Timelock"
    });
});
