require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { task } = require("hardhat/config");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const polygonContracts = addresses.IdleTokens.polygon;

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
    const networkContracts = isMatic ? polygonContracts : mainnetContracts;

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
    const strategy = await ethers.getContractAt("IIdleCDOStrategy", strategyAddress);
    const underlyingAddress = await strategy.token();
    const underlyingAddressCDO = args.cdoUnderlying;
    const underlyingToken = await ethers.getContractAt("IERC20Detailed", underlyingAddress);
    const underlyingName = await underlyingToken.name();
    const underlyingTokenCDO = await ethers.getContractAt("IERC20Detailed", underlyingAddressCDO);
    const underlyingNameCDO = await underlyingTokenCDO.name();

    if (hre.network.name === 'hardhat' && cdoFactoryAddress === undefined) {
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
    
    let cdoFactory = await ethers.getContractAt("IdleCDOFactory", cdoFactoryAddress);
    cdoFactory = cdoFactory.connect(signer);
    const idleCDO = await ethers.getContractAt(isMatic ? "IdleCDOPolygon" : "IdleCDO", cdoImplementationAddress);
    
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
    const deployToken = (
      isMatic ?
        addresses.deployTokensPolygon :
        addresses.deployTokens
    )[args.cdoname];
    const networkContracts = isMatic ? polygonContracts : mainnetContracts;

    if (deployToken === undefined) {
      console.log(`🛑 deployToken not found with specified cdoname (${cdoname})`)
      return;
    } 

    let strategy = await ethers.getContractAt(args.strategyName, strategyAddress);
    const incentiveTokens = deployToken.incentiveTokens || [];
    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    let idleCDOAddress;
    const contractName = deployToken.cdoVariant || (isMatic ? 'IdleCDOPolygon' : 'IdleCDO');

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

    const idleCDO = await ethers.getContractAt(contractName, idleCDOAddress);
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

    console.log(`Transfer ownership of strategy to DL multisig ${mainnetContracts.devLeagueMultisig}`);
    await strategy.connect(signer).transferOwnership(mainnetContracts.devLeagueMultisig);
    
    console.log(`Set guardian of CDO to DL multisig ${mainnetContracts.devLeagueMultisig}`);
    await idleCDO.connect(signer).setGuardian(mainnetContracts.devLeagueMultisig);
    
    console.log(`Transfer ownership of CDO to TL multisig ${mainnetContracts.treasuryMultisig}`);
    await idleCDO.connect(signer).transferOwnership(mainnetContracts.treasuryMultisig);

    const feeReceiver = await idleCDO.feeReceiver();
    if (
        (!isMatic && feeReceiver == mainnetContracts.oldFeeReceiver) || 
        (isMatic && feeReceiver != polygonContracts.feeReceiver)
      ) {
      console.log('Setting fee receiver to Treasury Multisig')
      await idleCDO.connect(signer).setFeeReceiver(networkContracts.feeReceiver);
    }

    if (deployToken.unlent == 0) {
      console.log('Setting unlent to 0')
      await idleCDO.connect(signer).setUnlentPerc(0);
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
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const networkContracts = isMatic ? polygonContracts : mainnetContracts;

    // Check that cdoname is passed
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    
    // Get config params
    const deployToken = (
      isMatic ? 
      addresses.deployTokensPolygon : 
      addresses.deployTokens
    )[args.cdoname];
    
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
