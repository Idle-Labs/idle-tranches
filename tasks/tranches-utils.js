require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const one = ONE_TOKEN(18);

/**
 * @name change-rewards
 */
task("change-rewards", "Update rewards IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    // await run('upgrade-cdo-multisig', {cdoname: args.cdoname});

    const multisig = await run('get-multisig-or-fake');

    const deployToken = addresses.deployTokens[args.cdoname];
    console.log('deployToken', deployToken)

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
