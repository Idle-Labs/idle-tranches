require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");
const { task } = require("hardhat/config");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const deployTokensBY = addresses.deployTokensBY;
const CDOs = addresses.CDOs;
    
/**
 * @name deploy-by
 * task to deploy IdleTokenFungible with it's strategies
 */
task("deploy-by", "Deploy IdleTokenFungible via CDOFactory")
  .addParam('byname')
  .setAction(async (args) => {
    // First we should deploy the uninitialized IdleToken
    // Then deploy the strategies, using the new IdleToken address
    // Then rerun this task to call _init on IdleToken

    await run("compile");
    // Check that byname is passed
    if (!args.byname) {
      console.log("🛑 byname and it's params must be defined");
      return;
    }
    
    // Get config params
    const deployToken = addresses.deployTokensBY[args.byname];
    if (!deployToken.underlying || !deployToken.strategies) {
      console.log("🛑 underlying and strategies must be specified");
      return;
    }
    
    // Get signer
    const signer = await helpers.getSigner();
    const addr = await signer.getAddress();
    
    console.log(`Deploying with ${addr}`);
    console.log()
    
    let idleToken;
    if (!deployToken.address) {
      idleToken = await helpers.deployUpgradableContract(
        'IdleTokenFungible',
        [], // no params, initialize is called after strategies deploy
        signer
      );
    } else {
      idleToken = await ethers.getContractAt('IdleTokenFungible', deployToken.address);
    }

    const underlying = await ethers.getContractAt('IERC20Detailed', deployToken.underlying);
    const underlyingName = await underlying.name();
    const strategies = deployToken.strategies;

    if (strategies.length == 0) {
      return;
    }

    const deployedStrat = [];
    const protocolTokens = [];
    for (let i = 0; i < strategies.length; i++) {
      let strategy = await ethers.getContractAt('ILendingProtocol', strategies[i]);
      protocolTokens.push(await strategy.token());
      deployedStrat.push(strategy);
    }

    const initParams = [
      deployToken.name,
      deployToken.symbol,
      deployToken.underlying,
      protocolTokens,
      deployedStrat.map(s => s.address),
      [BN('100000'), BN('0')]
    ];

    console.log('initParams', initParams);
    console.log()
    console.log("🟩🟩🟩 IdleToken params 🟩🟩🟩");
    console.log("name:               ", `${initParams[0]}`);
    console.log("symbol:             ", `${initParams[1]}`);
    console.log("underlying:         ", `${initParams[2]} ${underlyingName}`);
    console.log("protocolTokens:     ", `${initParams[3]}`);
    console.log("strategies:         ", `${initParams[4]}`);
    console.log("allocations:        ", `${initParams[5]}`);
    console.log()

    await idleToken.connect(signer)._init(...initParams);
    // If protocols need to be updated call the following method
    //
    // await idleToken.connect(signer).setAllAvailableTokensAndWrappers(
    //   protocolTokens,
    //   deployedStrat.map(s => s.address)
    // );
});
