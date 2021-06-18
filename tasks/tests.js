require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

const testToken = addresses.deployTokens.DAI;

/**
 * @name print-info
 */
task("print-info")
  .addOptionalParam('cdo')
  .setAction(async ({cdo}) => {
    let idleCDO;
    let AAaddr;
    let BBaddr;
    let strategy;
    if (cdo) {
      idleCDO = await ethers.getContractAt("IdleCDO", cdo);
      AAaddr = await idleCDO.AATranche();
      BBaddr = await idleCDO.BBTranche();
      strategy = await ethers.getContractAt("IIdleCDOStrategy", await idleCDO.strategy());
    } else {
      // Run 'deploy' task
      const res = await run("deploy");
      idleCDO = res.idleCDO;
      AAaddr = res.AAaddr;
      BBaddr = res.BBaddr;
      strategy = res.strategy;
    }

    let idleToken = await ethers.getContractAt("IIdleToken", await strategy.strategyToken());
    const rewardTokens = await idleCDO.getRewards();

    const [
      lastStrategyPrice,
      strategyPrice,
      tranchePriceAA,
      tranchePriceBB,
      virtualPriceAA,
      virtualPriceBB,
      lastTranchePriceAA,
      lastTranchePriceBB,
      strategyAPR,
      getAprAA,
      getAprBB,
      getIdealAprAA,
      getIdealAprBB,
      contractVal,
      virtualBalanceAA,
      virtualBalanceBB,
      getCurrentAARatio,
    ] = await Promise.all([
      // Check prices
      idleCDO.lastStrategyPrice(),
      idleCDO.strategyPrice(),
      idleCDO.tranchePrice(AAaddr),
      idleCDO.tranchePrice(BBaddr),
      idleCDO.virtualPrice(AAaddr),
      idleCDO.virtualPrice(BBaddr),
      idleCDO.lastTranchePrice(AAaddr),
      idleCDO.lastTranchePrice(BBaddr),
      // Aprs
      idleCDO.strategyAPR(),
      idleCDO.getApr(AAaddr),
      idleCDO.getApr(BBaddr),
      idleCDO.getIdealApr(AAaddr),
      idleCDO.getIdealApr(BBaddr),
      // Values
      idleCDO.getContractValue(),
      idleCDO.virtualBalance(AAaddr),
      idleCDO.virtualBalance(BBaddr),
      idleCDO.getCurrentAARatio()
    ]);

    console.log('📄 Info 📄');
    console.log(`#### Prices (strategyPrice ${BN(strategyPrice)}, (Last: ${BN(lastStrategyPrice)})) ####`);
    console.log(`tranchePriceAA ${BN(tranchePriceAA)}, virtualPriceAA ${BN(virtualPriceAA)} (Last: ${BN(lastTranchePriceAA)})`);
    console.log(`tranchePriceBB ${BN(tranchePriceBB)}, virtualPriceBB ${BN(virtualPriceBB)} (Last: ${BN(lastTranchePriceBB)})`);
    console.log(`#### Aprs (strategyAPR ${BN(strategyAPR)}) ####`);
    console.log(`getAprAA ${BN(getAprAA)}, (Ideal: ${BN(getIdealAprAA)})`);
    console.log(`getAprBB ${BN(getAprBB)}, (Ideal: ${BN(getIdealAprBB)})`);
    console.log('#### Other values ####');
    console.log('Underlying val', BN(contractVal).toString());
    console.log('Virtual balance AA', BN(virtualBalanceAA).toString());
    console.log('Virtual balance BB', BN(virtualBalanceBB).toString());
    console.log('getCurrentAARatio', BN(getCurrentAARatio).toString());
    console.log();

    return {idleCDO, AAaddr, BBaddr, strategy, idleToken};
  });

task("print-balance")
  .addOptionalParam('address')
  .setAction(async (args) => {
    let compERC20 = await ethers.getContractAt("IERC20Detailed", mainnetContracts.COMP);
    let idleERC20 = await ethers.getContractAt("IERC20Detailed", mainnetContracts.IDLE);
    let underlyingContract = await ethers.getContractAt("IERC20Detailed", testToken.underlying);

    let COMPBal = await compERC20.balanceOf(args.address);
    let IDLEBal = await idleERC20.balanceOf(args.address);
    let underlyingBalance = await underlyingContract.balanceOf(args.address);
    console.log('COMPBal', COMPBal.toString());
    console.log('IDLEBal', IDLEBal.toString());
    console.log('underlyingBalance', underlyingBalance.toString());
});

/**
 * @name integration
 */
task("integration")
  .setAction(async (args) => {
    let {idleCDO, AAaddr, BBaddr, idleToken, strategy} = await run("print-info");

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
    // Get utils
    const oneToken = await helpers.oneToken(underlying);
    const creatorAddr = await creator.getAddress();
    const AABuyerAddr = await AAbuyer.getAddress();
    const AABuyer2Addr = await AAbuyer2.getAddress();
    const BBBuyerAddr = await BBbuyer.getAddress();
    const feeCollectorAddr = await feeCollector.getAddress();

    // set fee receiver
    await idleCDO.setFeeReceiver(feeCollectorAddr);

    // enrich idleCDO contract (do NOT reassign the object like below)
    // idleCDO = {...idleCDO, AAContract, BBContract, underlyingContract};
    idleCDO.idleToken = idleToken;
    idleCDO.AAContract = AAContract;
    idleCDO.BBContract = BBContract;
    idleCDO.AAStaking = stakingRewardsAA;
    idleCDO.BBStaking = stakingRewardsBB;
    idleCDO.underlyingContract = underlyingContract;
    // Params
    const amount = BN('100000').mul(oneToken);
    // Fund wallets
    await helpers.fundWallets(underlying, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, creatorAddr], addresses.whale, amount);

    console.log('######## Deposits');
    // Buy AA tranche with `amount` underlying
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, amount);
    // Buy BB tranche with `amount` underlying
    await helpers.deposit('BB', idleCDO, BBBuyerAddr, amount.div(BN('2')));
    // Do an harvest to do a real deposit in Idle
    // no gov tokens collected now because it's the first deposit
    await rebalanceFull(idleCDO, creatorAddr, true);
    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa2TrancheBal = await helpers.deposit('AA', idleCDO, AABuyer2Addr, amount);
    // amount bought should be less than the one of AABuyerAddr because price increased
    await helpers.checkIncreased(aa2TrancheBal, aaTrancheBal, 'AA1 bal is greater than the newly minted bal after harvest');

    console.log('######## First real rebalance (with interest and rewards accrued)');
    let feeReceiverBBBal = await helpers.getBalance(BBContract, feeCollectorAddr);
    let stakingBBIdleBal = await helpers.getBalance(idleERC20, stakingRewardsBB.address);
    await helpers.checkBalance(compERC20, stakingRewardsBB.address, BN('0'));
    // tranchePriceAA and tranchePriceBB have been updated just before the deposit
    // some gov token (IDLE but not COMP because it has been sold) should be present in the contract after the rebalance
    await rebalanceFull(idleCDO, creatorAddr);
    // so no IDLE and no COMP in IdleCDO
    await helpers.checkBalance(idleERC20, idleCDO.address, BN('0'));
    await helpers.checkBalance(compERC20, idleCDO.address, BN('0'));
    // feeReceiver should have received some BB tranches as fees
    let feeReceiverBBBalAfter = await helpers.getBalance(BBContract, feeCollectorAddr);
    await helpers.checkIncreased(feeReceiverBBBal, feeReceiverBBBalAfter, 'Fee receiver got some BB tranches');
    // BB Staking contract should have received only IDLE
    let stakingBBIdleBalAfter = await helpers.getBalance(idleERC20, stakingRewardsBB.address);
    await helpers.checkIncreased(stakingBBIdleBal, stakingBBIdleBalAfter, 'BB Staking contract got some IDLE tokens');
    await helpers.checkBalance(compERC20, stakingRewardsBB.address, BN('0'));
    // No rewards for AA staking contract
    await helpers.checkBalance(compERC20, stakingRewardsAA.address, BN('0'));
    await helpers.checkBalance(idleERC20, stakingRewardsAA.address, BN('0'));

    console.log('######## Withdraws');
    // First user withdraw
    await helpers.withdrawWithGain('AA', idleCDO, AABuyerAddr, amount);
    feeReceiverBBBal = await idleCDO.BBContract.balanceOf(feeCollectorAddr);
    await rebalanceFull(idleCDO, creatorAddr);
    // Check that fee receiver got fees (in BB tranche tokens)
    feeReceiverBBBalAfter = await idleCDO.BBContract.balanceOf(feeCollectorAddr);
    await helpers.checkIncreased(feeReceiverBBBal, feeReceiverBBBalAfter, 'Fee receiver got some BB tranches');

    await helpers.withdrawWithGain('BB', idleCDO, BBBuyerAddr, amount.div(BN('2')));
    await rebalanceFull(idleCDO, creatorAddr);

    await helpers.withdrawWithGain('AA', idleCDO, AABuyer2Addr, amount);

    console.log('######## Check fees');
    let feeReceiverAABal = await idleCDO.AAContract.balanceOf(feeCollectorAddr);
    let stakingAAIdleBal = await helpers.getBalance(idleERC20, stakingRewardsAA.address);
    helpers.check(stakingAAIdleBal, BN('0'), `AA staking contract has no IDLE`);
    await rebalanceFull(idleCDO, creatorAddr);
    let stakingAAIdleBalAfter = await helpers.getBalance(idleERC20, stakingRewardsAA.address);
    await helpers.checkIncreased(stakingAAIdleBal, stakingAAIdleBalAfter, 'AA Staking contract got some IDLE tokens');
    // Check that fee receiver got fees (in AA tranche tokens)
    let feeReceiverAABalAfter = await idleCDO.AAContract.balanceOf(feeCollectorAddr);
    await helpers.checkIncreased(feeReceiverAABal, feeReceiverAABalAfter, 'Fee receiver got some AA tranches');
    await helpers.checkBalance(compERC20, stakingRewardsAA.address, BN('0'));
    await helpers.checkBalance(compERC20, stakingRewardsBB.address, BN('0'));

    await run("print-balance", {address: idleCDO.address});
    idleTokenBal = await idleToken.balanceOf(idleCDO.address);
    console.log('idleTokenBal', idleTokenBal.toString());

    feeReceiverBBBalAfter = await idleCDO.BBContract.balanceOf(feeCollectorAddr);
    console.log('feeReceiverBBBalAfter', feeReceiverBBBalAfter.toString());
    feeReceiverAABalAfter = await idleCDO.AAContract.balanceOf(feeCollectorAddr);
    console.log('feeReceiverAABalAfter', feeReceiverAABalAfter.toString());

    console.log('AA staking IDLE balance');
    await run("print-balance", {address: stakingRewardsAA.address});
    console.log('BB staking IDLE balance');
    await run("print-balance", {address: stakingRewardsBB.address});

    console.log('######## Stake/Unstake AA tranche for incentive rewards');
    // stake AA tranche in AA rewards contract
    // Give some ETH to fee receiver
    await creator.sendTransaction({to: feeCollectorAddr, value: ethers.utils.parseEther("1.0")});
    let _amount = feeReceiverAABalAfter;
    await helpers.sudoCall(feeCollectorAddr, AAContract, 'approve', [stakingRewardsAA.address, _amount]);
    await helpers.sudoCall(feeCollectorAddr, stakingRewardsAA, 'stake', [_amount]);
    await helpers.checkBalance(AAContract, feeCollectorAddr, BN('0'));
    await helpers.checkBalance(AAContract, stakingRewardsAA.address, _amount);
    helpers.check(await stakingRewardsAA.expectedUserReward(feeCollectorAddr, mainnetContracts.IDLE), BN('0'));

    // accrue some IDLE in the AA staking reward contract with a rebalance
    stakingAAIdleBal = await helpers.getBalance(idleERC20, stakingRewardsAA.address);
    await rebalanceFull(idleCDO, creatorAddr);
    stakingAAIdleBalAfter = await helpers.getBalance(idleERC20, stakingRewardsAA.address);
    await helpers.checkIncreased(stakingAAIdleBal, stakingAAIdleBalAfter, 'AA Staking contract got some IDLE tokens');

    // unstake and check to get rewards
    await helpers.sudoCall(feeCollectorAddr, stakingRewardsAA, 'unstake', [_amount]);
    await helpers.checkBalance(AAContract, stakingRewardsAA.address, BN('0'));
    await helpers.checkBalance(AAContract, feeCollectorAddr, _amount);
    // sub 1 for rounding
    await helpers.checkBalance(idleERC20, feeCollectorAddr, stakingAAIdleBalAfter.sub(stakingAAIdleBal).sub(BN('1')));

    return {idleCDO};
  });

const rebalanceFull = async (idleCDO, address, skipRedeem = false) => {
  await run("print-info", {cdo: idleCDO.address});
  console.log('🚧 Waiting some time + 🚜 Harvesting');
  await run("mine-multiple", {blocks: '500'});
  const rewardTokens = await idleCDO.getRewards();
  await helpers.sudoCall(address, idleCDO, 'harvest', [false, skipRedeem, rewardTokens.map(r => false), rewardTokens.map(r => BN('0'))]);
  await helpers.sudoCall(address, idleCDO.idleToken, 'rebalance', []);

  await run("mine-multiple", {blocks: '500'});
  // Poking cToken contract to accrue interest and let strategyPrice increase.
  // (be sure to have a pinned block with allocation in compound)
  let cToken = await ethers.getContractAt("ICToken", testToken.cToken);
  await cToken.accrueInterest();
  console.log('🚧 After some time...');
  await run("print-info", {cdo: idleCDO.address});
}
