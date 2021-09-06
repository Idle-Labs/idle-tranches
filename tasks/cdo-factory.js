require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

const defaultProxyAdminAddress = "0x9438904ABC7d8944A6E2A89671fEf51C629af351";

/**
 * @name deploy
 * eg `npx hardhat deploy-cdo-factory`
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
 * @name deploy
 * eg `npx hardhat deploy-with-cdo-factory`
 */
task("deploy-with-factory-generic", "Deploy IdleCDO using IdleCDOFactory")
  .addParam('cdoImplementation', "The CDO implementation address", "", types.string, true)
  .addParam('cloneFromProxy', "The CDO proxy to clone the implementation from", "", types.string, true)
  .addParam('proxyAdmin', "The ProxyAdmin address", "", types.string, true)
  .addParam('limit', "CDO param _limit")
  .addParam('governanceFund', "CDO param _governanceFund")
  .addParam('strategy', "CDO param _strategy")
  .addParam('trancheAPRSplitRatio', "CDO param _trancheAPRSplitRatio")
  .addParam('trancheIdealWeightRatio', "CDO param _trancheIdealWeightRatio")
  .addParam('incentiveTokens', "A comma separated list of incentive tokens", undefined, types.string, true)
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    let proxyAdminAddress = args.proxyAdmin;
    if (proxyAdminAddress === "") {
      console.log("\n⚠️  proxyAdmin not specified. Using the default one: ", defaultProxyAdminAddress, "\n");
      proxyAdminAddress = defaultProxyAdminAddress;
    }

    if (helpers.isEmptyString(args.cdoImplementation) && helpers.isEmptyString(args.cloneFromProxy)) {
      throw("cdoImplementationAddress or cloneFromProxy must be specified");
    }

    let cdoImplementationAddress = args.cdoImplementation;
    if (helpers.isEmptyString(cdoImplementationAddress)) {
      console.log("\n🔎 Retrieving implementation from proxy (", args.cloneFromProxy, ")");
      cdoImplementationAddress = await getImplementationAddress(hre.ethers.provider, args.cloneFromProxy);
      console.log("🔎 using implementation address", cdoImplementationAddress, "\n");
    }

    const cdoname = args.cdoname;
    let   cdoFactoryAddress = mainnetContracts.cdoFactory;
    const limit = args.limit;
    const governanceFund = args.governanceFund;
    const strategyAddress = args.strategy;
    const trancheAPRSplitRatio = args.trancheAPRSplitRatio;
    const trancheIdealWeightRatio = args.trancheIdealWeightRatio;
    const incentiveTokens = args.incentiveTokens.split(",").map(s => s.trim());

    console.log("\n🔎 Retrieving underlying token from strategy (", args.strategyAddress, ")");
    const strategy = await ethers.getContractAt("IIdleCDOStrategy", strategyAddress);
    const underlyingAddress = await strategy.token();
    const underlyingToken = await ethers.getContractAt("IERC20Detailed", underlyingAddress);
    const underlyingName = await underlyingToken.name();

    if (hre.network.name === 'hardhat' && cdoFactoryAddress === undefined) {
      console.log("\n⚠️  Local network - cdoFactoryAddress is undefined, deploying CDOFactory\n");
      const cdoFactory = await hre.run("deploy-cdo-factory");
      cdoFactoryAddress = cdoFactory.address;
    }

    if (helpers.isEmptyString(cdoFactoryAddress)) {
      console.log("🛑 cdoFactoryAddress must be specified")
      return;
    }

    console.log("creator:                 ", creator);
    console.log("network:                 ", hre.network.name);
    console.log("proxyAdmin:              ", proxyAdminAddress);
    console.log("factory:                 ", cdoFactoryAddress);
    console.log("underlying:              ", `(${underlyingAddress, underlyingName}`);
    console.log("cdoImplementation:       ", cdoImplementationAddress);
    console.log("limit:                   ", limit.toString());
    console.log("governanceFund:          ", governanceFund);
    console.log("strategy:                ", strategyAddress);
    console.log("trancheAPRSplitRatio:    ", trancheAPRSplitRatio.toString());
    console.log("trancheIdealWeightRatio: ", trancheIdealWeightRatio.toString());
    console.log("incentiveTokens:");
    for (var i = 0; i < incentiveTokens.length; i++) {
      console.log(`* ${incentiveTokens[i]}`);
    };

    await helpers.prompt("continue? [y/n]", true);

    const cdoFactory = await ethers.getContractAt("IdleCDOFactory", cdoFactoryAddress);
    const idleCDO = await ethers.getContractAt("IdleCDO", cdoImplementationAddress);

    const initMethodCall = idleCDO.interface.encodeFunctionData("initialize", [
      limit,
      underlyingAddress,
      governanceFund, // recovery address
      creator, // guardian
      mainnetContracts.rebalancer,
      strategyAddress,
      trancheAPRSplitRatio,
      trancheIdealWeightRatio,
      incentiveTokens
    ]);

    console.log("deploying with factory...");
    const res = await cdoFactory.deployCDO(cdoImplementationAddress, proxyAdminAddress, initMethodCall);
    const cdoDeployFilter = cdoFactory.filters.CDODeployed;
    const events = await cdoFactory.queryFilter(cdoDeployFilter, "latest");
    const proxyAddress = events[0].args.proxy;
    const receipt = await res.wait();
    helpers.log(`📤 IdleCDO created (proxy via CDOFactory): ${proxyAddress} @tx: ${res.hash}, (gas ${receipt.cumulativeGasUsed.toString()})`);
    return proxyAddress;
  });

task("deploy-with-factory", "Deploy IdleCDO with CDOFactory, IdleStrategy and Staking contract for rewards with default parameters")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const cdoname = args.cdoname;
    let cdoProxyAddressToClone = undefined;
    const deployToken = addresses.deployTokens[cdoname];

    if (deployToken === undefined) {
      console.log(`🛑 deployToken not found with specified cdoname (${cdoname})`)
      return;
    }

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    if (hre.network.name === 'hardhat') {
      console.log("\n⚠️  Local network - deploying test CDO\n");
      let { idleCDO, strategy, AAaddr, BBaddr } = await hre.run("deploy", { cdoname: cdoname });
      cdoProxyAddressToClone = idleCDO.address;
    }

    if (helpers.isEmptyString(cdoProxyAddressToClone)) {
      console.log("🛑 cdoProxyAddressToClone must be specified")
      return;
    }

    await helpers.prompt("continue? [y/n]", true);

    const incentiveTokens = [mainnetContracts.IDLE];
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [deployToken.idleToken, creator], signer);

    const deployParams = {
      cdoname: cdoname,
      // cdoImplementation: implAddress,
      cloneFromProxy: cdoProxyAddressToClone,
      limit: BN('500000').mul(ONE_TOKEN(deployToken.decimals)).toString(), // limit
      governanceFund: mainnetContracts.treasuryMultisig, // recovery address
      strategy: strategy.address,
      trancheAPRSplitRatio: BN('20000').toString(), // apr split: 20% interest to AA and 80% BB
      trancheIdealWeightRatio: BN('50000').toString(), // ideal value: 50% AA and 50% BB tranches
      incentiveTokens: [mainnetContracts.IDLE].join(","),
    }
    const idleCDOAddress = await hre.run("deploy-with-factory-generic", deployParams);
    const idleCDO = await ethers.getContractAt("IdleCDO", idleCDOAddress);

    await strategy.connect(signer).setWhitelistedCDO(idleCDO.address);
    const AAaddr = await idleCDO.AATranche();
    const BBaddr = await idleCDO.BBTranche();
    console.log(`AATranche: ${AAaddr}, BBTranche: ${BBaddr}`);

    const stakingCoolingPeriod = BN(1500);
    const stakingRewardsParams = [
      incentiveTokens,
      creator, // owner / guardian
      idleCDO.address,
      mainnetContracts.devLeagueMultisig, // recovery address
      stakingCoolingPeriod
    ];
    const stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AAaddr, ...stakingRewardsParams], signer
    );
    const stakingRewardsBB = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [BBaddr, ...stakingRewardsParams], signer
    );
    await idleCDO.connect(signer).setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);
    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`staking reward contract set`);
    console.log();
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

