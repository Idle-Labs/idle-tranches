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
task("deploy-cdo-with-factory", "Deploy IdleCDO using IdleCDOFactory")
  .addParam('cdoname', "The underlying asset (idledai/idleusdc/idleusdt)")
  .addParam('cdoImplementation', "The CDO implementation address", "", types.string, true)
  .addParam('cloneFromProxy', "The CDO proxy to clone the implementation from", "", types.string, true)
  .addParam('proxyAdmin', "The ProxyAdmin address", "", types.string, true)
  .addParam('factory', "The CDOFactory address")
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
    const factoryAddress = args.factory;
    const limit = args.limit;
    const governanceFund = args.governanceFund;
    const strategyAddress = args.strategy;
    const trancheAPRSplitRatio = args.trancheAPRSplitRatio;
    const trancheIdealWeightRatio = args.trancheIdealWeightRatio;
    const incentiveTokens = args.incentiveTokens.split(",").map(s => s.trim());

    console.log("creator:                 ", creator);
    console.log("network:                 ", hre.network.name);
    console.log("proxyAdmin:              ", proxyAdminAddress);
    console.log("factory:                 ", factoryAddress);
    console.log("cdoname:                 ", cdoname);
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

    const cdoFactory = await ethers.getContractAt("IdleCDOFactory", factoryAddress);
    const idleCDO = await ethers.getContractAt("IdleCDO", cdoImplementationAddress);
    const deployToken = addresses.deployTokens[cdoname];

    const initMethodCall = idleCDO.interface.encodeFunctionData("initialize", [
      limit,
      deployToken.underlying,
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
