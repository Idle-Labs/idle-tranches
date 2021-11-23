require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

task("deploy-convex-strategy")
  .addParam("strategy")
  .setAction(async (args) => {
    await run("compile");
    const convexArgs = addresses.deployConvex[args.strategy];
    console.log("Deploying Idle Convex Strategy: ", args.strategy);

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    const deployArgs = convexArgs.strategyArgs;
    deployArgs[1] = creator // setting the owner for the strategy

    const strategy = await helpers.deployUpgradableContract(convexArgs.contractName, deployArgs, signer);

    console.log("Strategy deployed at ", strategy.address);
    console.log("To deploy a CDO using this strategy use the task deploy-with-factory-generic");
    console.log("Add '--strategy " + strategy.address + " to use this deployed strategy")
    console.log("Remember to set the whitelisted CDO for this strategy!");
  });