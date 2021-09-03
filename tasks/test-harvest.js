require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const { time } = require("@openzeppelin/test-helpers");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const {
  rebalanceFull,
} = require("./tests");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

const testToken = addresses.deployTokens.idledai;

const waitBlocks = async (n) => {
  for (var i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine");
  };
}

task("test-harvest", "")
  .addOptionalParam('cdoname')
  .setAction(async (args) => {
    let res;
    if (args.cdoname) {
      res = await run("print-info", {cdo: addresses.deployTokens[args.cdoname].cdo.cdoAddr});
    } else {
      res = await run("print-info");
    }
    let {idleCDO, AAaddr, BBaddr, idleToken, strategy} = res;

    console.log('######## Setup');
    // Get signers
    let [creator, AAbuyer, BBbuyer, AAbuyer2, feeCollector] = await ethers.getSigners();
    // Get contracts
    const underlying = await idleCDO.token();
    let compERC20 = await ethers.getContractAt("IERC20Detailed", mainnetContracts.COMP);
    let idleERC20 = await ethers.getContractAt("IERC20Detailed", mainnetContracts.IDLE);
    let cTokenContract = await ethers.getContractAt("IERC20Detailed", testToken.cToken);
    let underlyingContract = await ethers.getContractAt("IERC20Detailed", underlying);
    let AAContract = await ethers.getContractAt("IdleCDOTranche", AAaddr);
    let BBContract = await ethers.getContractAt("IdleCDOTranche", BBaddr);
    let stakingRewardsAA = await ethers.getContractAt("IdleCDOTrancheRewards", await idleCDO.AAStaking());
    let stakingRewardsBB = await ethers.getContractAt("IdleCDOTrancheRewards", await idleCDO.BBStaking());
    const stkAave = await ethers.getContractAt("IERC20Detailed", addresses.IdleTokens.mainnet.stkAAVE);
    // Get utils
    const oneToken = await helpers.oneToken(underlying);
    const creatorAddr = args.cdoname ? addresses.idleDeployer : await creator.getAddress();
    const AABuyerAddr = await AAbuyer.getAddress();
    const AABuyer2Addr = await AAbuyer2.getAddress();
    const BBBuyerAddr = await BBbuyer.getAddress();
    const feeCollectorAddr = await feeCollector.getAddress();
    // set fee receiver
    await helpers.sudoCall(creatorAddr, idleCDO, 'setFeeReceiver', [feeCollectorAddr]);
    // enrich idleCDO contract (do NOT reassign the object like below)
    // idleCDO = {...idleCDO, AAContract, BBContract, underlyingContract};
    idleCDO.idleToken = idleToken;

    // move funds to AAVE V2
    await hre.ethers.provider.send("hardhat_setBalance", [addresses.timelock, "0xffffffffffffffff"]);
    await hre.ethers.provider.send("hardhat_setBalance", [addresses.whale, "0xffffffffffffffff"]);
    await helpers.sudoCall(addresses.timelock, idleToken, 'setAllocations', [[BN("0"), BN("0"), BN("100000")]]);
    await helpers.sudoCall(creatorAddr, idleToken, 'rebalance', []);

    idleCDO.AAContract = AAContract;
    idleCDO.BBContract = BBContract;
    idleCDO.AAStaking = stakingRewardsAA;
    idleCDO.BBStaking = stakingRewardsBB;
    idleCDO.underlyingContract = underlyingContract;
    // Params
    const amount = BN('10000').mul(oneToken);
    // Fund wallets
    await helpers.fundWallets(underlying, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, creatorAddr], addresses.whale, amount);

    console.log("************************ stkAAVE balance", (await stkAave.balanceOf(idleCDO.address)).toString());
    console.log("************************ underlying balance", (await underlyingContract.balanceOf(idleCDO.address)).toString());

    console.log('######## Deposits');
    // Buy AA tranche with `amount` underlying
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, amount);
    // Buy BB tranche with `amount` underlying
    await helpers.deposit('BB', idleCDO, BBBuyerAddr, amount.div(BN('2')));
    // Do an harvest to do a real deposit in Idle
    // no gov tokens collected now because it's the first deposit
    await rebalanceFull(idleCDO, creatorAddr, true, false);

    console.log("************************ stkAAVE balance", (await stkAave.balanceOf(idleCDO.address)).toString());
    console.log("************************ underlying balance", (await underlyingContract.balanceOf(idleCDO.address)).toString());

    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa2TrancheBal = await helpers.deposit('AA', idleCDO, AABuyer2Addr, amount);
    // amount bought should be less than the one of AABuyerAddr because price increased
    await helpers.checkIncreased(aa2TrancheBal, aaTrancheBal, 'AA1 bal is greater than the newly minted bal after harvest');

    const blocksPerDay = 6000;
    const daysBlocks = (days) => (blocksPerDay * days).toString();

    // harvest 2
    console.log('######## harvest 2 with interest and rewards accrued');
    await rebalanceFull(idleCDO, creatorAddr, true, true);
    console.log("************************ stkAAVE balance", (await stkAave.balanceOf(idleCDO.address)).toString());
    console.log("************************ underlying balance", (await underlyingContract.balanceOf(idleCDO.address)).toString());

    // harvest 3
    console.log('######## harvest 3 should do nothing with stkAAVE because cooldown is active');
    await run("mine-multiple", {blocks: daysBlocks(6)});
    await rebalanceFull(idleCDO, creatorAddr, true, true);
    console.log("************************ stkAAVE balance", (await stkAave.balanceOf(idleCDO.address)).toString());
    console.log("************************ underlying balance", (await underlyingContract.balanceOf(idleCDO.address)).toString());

    // harvest 4
    console.log('######## harvest 4 should redeem AAVE and convert them in underlying + pull new stkAAVE and start a new cooldown');
    await hre.run("increase-time-mine", { time: time.duration.days(11).toString() });
    await rebalanceFull(idleCDO, creatorAddr, true, true);
    console.log("************************ stkAAVE balance", (await stkAave.balanceOf(idleCDO.address)).toString());
    console.log("************************ underlying balance", (await underlyingContract.balanceOf(idleCDO.address)).toString());
  });
