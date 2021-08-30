require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

const testToken = addresses.deployTokens.idledai;

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
      const res = await run("deploy", {cdoname: 'idledai'});
      idleCDO = res.idleCDO;
      AAaddr = res.AAaddr;
      BBaddr = res.BBaddr;
      strategy = res.strategy;
    }

    let idleToken = await ethers.getContractAt("IIdleToken", await strategy.strategyToken());
    const strategyAddr = await idleCDO.strategy();
    let idleStrategy = await ethers.getContractAt("IdleStrategy", strategyAddr);
    const rewardTokens = await idleStrategy.getRewardTokens();

    const [
      lastStrategyPrice,
      tranchePriceAA,
      tranchePriceBB,
      virtualPriceAA,
      virtualPriceBB,
      getAprAA,
      getAprBB,
      getIdealAprAA,
      getIdealAprBB,
      contractVal,
      getCurrentAARatio,
    ] = await Promise.all([
      // Check prices
      idleCDO.lastStrategyPrice(),
      idleCDO.tranchePrice(AAaddr),
      idleCDO.tranchePrice(BBaddr),
      idleCDO.virtualPrice(AAaddr),
      idleCDO.virtualPrice(BBaddr),
      // Aprs
      idleCDO.getApr(AAaddr),
      idleCDO.getApr(BBaddr),
      idleCDO.getIdealApr(AAaddr),
      idleCDO.getIdealApr(BBaddr),
      // Values
      idleCDO.getContractValue(),
      idleCDO.getCurrentAARatio()
    ]);

    console.log('📄 Info 📄');
    console.log(`#### Prices (Last strategy price: ${BN(lastStrategyPrice)})) ####`);
    console.log(`tranchePriceAA ${BN(tranchePriceAA)}, virtualPriceAA ${BN(virtualPriceAA)}`);
    console.log(`tranchePriceBB ${BN(tranchePriceBB)}, virtualPriceBB ${BN(virtualPriceBB)}`);
    console.log(`#### Aprs ####`);
    console.log(`getAprAA ${BN(getAprAA)}, (Ideal: ${BN(getIdealAprAA)})`);
    console.log(`getAprBB ${BN(getAprBB)}, (Ideal: ${BN(getIdealAprBB)})`);
    console.log('#### Other values ####');
    console.log(`NAV ${contractVal.toString()} (ratio: ${getCurrentAARatio.toString()})`);
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
 * @name harvest-cdo
 * @notice this can be called in mainnet only if the owner is still the deployer address
 */
task("harvest-cdo")
  .addParam('cdo')
  .setAction(async ({ cdo }) => {
    let signer = await helpers.getSigner(true);
    if (hre.network.name != 'mainnet') {
      await signer.sendTransaction({to: addresses.idleDeployer, value: ethers.utils.parseEther("1.0")});
      [,signer] = await helpers.sudo(addresses.idleDeployer);
    }
    const addr = await signer.getAddress();
    console.log('Address used', addr);

    let idleCDO = await ethers.getContractAt("IdleCDO", cdo);
    idleCDO = await idleCDO.connect(signer);

    const skipRedeem = false;
    const skipIncentives = false;
    const skipFeeDeposit = true;

    const strategyAddr = await idleCDO.strategy();
    let idleStrategy = await ethers.getContractAt("IdleStrategy", strategyAddr);
    const rewardTokens = await idleStrategy.getRewardTokens();
    let res = await idleCDO.callStatic.harvest(skipRedeem, skipIncentives, skipFeeDeposit, rewardTokens.map(r => false), rewardTokens.map(r => BN('0')), rewardTokens.map(r => BN('0')));
    let sellAmounts = res._soldAmounts;
    let minAmounts = res._swappedAmounts;
    console.log(`sellAmounts ${sellAmounts}, minAmounts ${minAmounts}`);
    // Add some slippage tolerance
    minAmounts = minAmounts.map(m => BN(m).div(BN('100')).mul(BN('97'))); // 3 % slippage
    let tx = await idleCDO.harvest(skipRedeem, skipIncentives, skipFeeDeposit, rewardTokens.map(r => false), minAmounts, sellAmounts);
    tx = await tx.wait();
    console.log(`Tx ${tx.transactionHash}, ⛽ ${tx.cumulativeGasUsed}`);
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
    await rebalanceFull(idleCDO, creatorAddr, true, false);
    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa2TrancheBal = await helpers.deposit('AA', idleCDO, AABuyer2Addr, amount);
    // amount bought should be less than the one of AABuyerAddr because price increased
    await helpers.checkIncreased(aa2TrancheBal, aaTrancheBal, 'AA1 bal is greater than the newly minted bal after harvest');

    console.log('######## First real rebalance (with interest and rewards accrued)');
    let feeReceiverBBBal = await stakingRewardsBB.usersStakes(feeCollectorAddr);
    let stakingBBIdleBal = await helpers.getBalance(idleERC20, stakingRewardsBB.address);
    await helpers.checkBalance(compERC20, stakingRewardsBB.address, BN('0'));
    // tranchePriceAA and tranchePriceBB have been updated just before the deposit
    // some gov token (IDLE but not COMP because it has been sold) should be present in the contract after the rebalance
    await rebalanceFull(idleCDO, creatorAddr, false, false);
    // so no IDLE in IdleCDO
    await helpers.checkBalance(idleERC20, idleCDO.address, BN('0'));
    // some COMP may still be there given that we are not selling exactly the entire balance
    // await helpers.checkBalance(compERC20, idleCDO.address, BN('0'));

    // feeReceiver should have received some BB tranches as fees and those should be staked
    let feeReceiverBBBalAfter = await stakingRewardsBB.usersStakes(feeCollectorAddr);
    await helpers.checkIncreased(feeReceiverBBBal, feeReceiverBBBalAfter, 'Fee receiver got some BB tranches (staked)');
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
    feeReceiverBBBal = await stakingRewardsBB.usersStakes(feeCollectorAddr);
    await rebalanceFull(idleCDO, creatorAddr, false, false);
    // Check that fee receiver got fees (in BB tranche tokens)
    feeReceiverBBBalAfter = await stakingRewardsBB.usersStakes(feeCollectorAddr);
    await helpers.checkIncreased(feeReceiverBBBal, feeReceiverBBBalAfter, 'Fee receiver got some BB tranches (staked)');

    await helpers.withdrawWithGain('BB', idleCDO, BBBuyerAddr, amount.div(BN('2')));
    await rebalanceFull(idleCDO, creatorAddr, false, false);

    await helpers.withdrawWithGain('AA', idleCDO, AABuyer2Addr, amount);

    console.log('######## Check fees');
    let feeReceiverAABal = await stakingRewardsAA.usersStakes(feeCollectorAddr);
    let stakingAAIdleBal = await helpers.getBalance(idleERC20, stakingRewardsAA.address);
    helpers.check(stakingAAIdleBal, BN('0'), `AA staking contract has no IDLE`);
    await rebalanceFull(idleCDO, creatorAddr, false, false);
    let stakingAAIdleBalAfter = await helpers.getBalance(idleERC20, stakingRewardsAA.address);
    await helpers.checkIncreased(stakingAAIdleBal, stakingAAIdleBalAfter, 'AA Staking contract got some IDLE tokens');
    // Check that fee receiver got fees (in AA tranche tokens)
    let feeReceiverAABalAfter = await stakingRewardsAA.usersStakes(feeCollectorAddr);;
    await helpers.checkIncreased(feeReceiverAABal, feeReceiverAABalAfter, 'Fee receiver got some AA tranches (staked)');
    await helpers.checkBalance(compERC20, stakingRewardsAA.address, BN('0'));
    await helpers.checkBalance(compERC20, stakingRewardsBB.address, BN('0'));

    await run("print-balance", {address: idleCDO.address});
    idleTokenBal = await idleToken.balanceOf(idleCDO.address);
    console.log('idleTokenBal', idleTokenBal.toString());

    feeReceiverBBBalAfter = await stakingRewardsBB.usersStakes(feeCollectorAddr);
    console.log('feeReceiverBBBalAfter', feeReceiverBBBalAfter.toString());
    feeReceiverAABalAfter = await stakingRewardsAA.usersStakes(feeCollectorAddr);
    console.log('feeReceiverAABalAfter', feeReceiverAABalAfter.toString());

    console.log('AA staking IDLE balance');
    await run("print-balance", {address: stakingRewardsAA.address});
    console.log('BB staking IDLE balance');
    await run("print-balance", {address: stakingRewardsBB.address});

    console.log('######## Stake/Unstake AA tranche for incentive rewards');
    // stake AA tranche in AA rewards contract
    // Give some ETH to fee receiver
    await creator.sendTransaction({to: feeCollectorAddr, value: ethers.utils.parseEther("1.0")});

    const stakedAA = await stakingRewardsAA.usersStakes(feeCollectorAddr);
    const stakedBB = await stakingRewardsBB.usersStakes(feeCollectorAddr);
    const IDLEbal = await helpers.getBalance(idleERC20, feeCollectorAddr);

    await helpers.checkBalance(AAContract, feeCollectorAddr, BN('0'));
    await helpers.checkBalance(AAContract, stakingRewardsAA.address, stakedAA);
    await helpers.checkBalance(BBContract, feeCollectorAddr, BN('0'));
    await helpers.checkBalance(BBContract, stakingRewardsBB.address, stakedBB);

    const expAA = await stakingRewardsAA.expectedUserReward(feeCollectorAddr, mainnetContracts.IDLE);
    const expBB = await stakingRewardsBB.expectedUserReward(feeCollectorAddr, mainnetContracts.IDLE);

    // unstake and check to get rewards
    await helpers.sudoCall(feeCollectorAddr, stakingRewardsAA, 'unstake', [stakedAA]);
    const IDLEbalAfterUnstake = await helpers.getBalance(idleERC20, feeCollectorAddr);
    await helpers.checkIncreased(IDLEbal, IDLEbalAfterUnstake, 'Fee receiver got some IDLE tokens after unstaking AA');
    await helpers.check(IDLEbalAfterUnstake.sub(IDLEbal), expAA, 'Fee receiver got correct number of IDLE after unstaking AA');

    await helpers.sudoCall(feeCollectorAddr, stakingRewardsBB, 'unstake', [stakedBB]);
    const IDLEbalFinal = await helpers.getBalance(idleERC20, feeCollectorAddr);
    await helpers.checkIncreased(IDLEbalAfterUnstake, IDLEbalFinal, 'Fee receiver got some IDLE tokens after unstaking BB');
    await helpers.check(IDLEbalFinal.sub(IDLEbalAfterUnstake), expBB, 'Fee receiver got correct number of IDLE after unstaking BB');

    await helpers.checkBalance(AAContract, stakingRewardsAA.address, BN('0'));
    await helpers.checkBalance(AAContract, feeCollectorAddr, feeReceiverAABalAfter);
    await helpers.checkBalance(BBContract, stakingRewardsBB.address, BN('0'));
    await helpers.checkBalance(BBContract, feeCollectorAddr, feeReceiverBBBalAfter);

    return {idleCDO};
  });

const rebalanceIdleToken = async (signerAddress, idleToken, allocations) => {
  console.log('🚧 Rebalancing idleToken ', idleToken.address);
  await helpers.sudoCall(mainnetContracts.rebalancer, idleToken, 'setAllocations', [allocations.map(a => BN(a))]);
  await helpers.sudoCall(signerAddress, idleToken, 'rebalance', []);
  let res = await helpers.sudoStaticCall(signerAddress, idleToken, 'getAllAvailableTokens', []);
  const aTokenAddr = res[3];
  let aToken = await ethers.getContractAt("IERC20Detailed", aTokenAddr);
  let aTokenBal = await helpers.sudoStaticCall(signerAddress, aToken, 'balanceOf', [idleToken.address]);
  console.log('AToken balance ', aTokenBal.toString());
}

const rebalanceFull = async (idleCDO, address, skipIncentivesUpdate, skipFeeDeposit) => {
  await run("print-info", {cdo: idleCDO.address});
  console.log('🚧 Waiting some time + 🚜 Harvesting');
  await run("mine-multiple", {blocks: '500'});

  const strategyAddr = await idleCDO.strategy();
  let idleStrategy = await ethers.getContractAt("IdleStrategy", strategyAddr);
  const rewardTokens = await idleStrategy.getRewardTokens();

  let res = await helpers.sudoStaticCall(address, idleCDO, 'harvest', [false, skipIncentivesUpdate, skipFeeDeposit, rewardTokens.map(r => false), rewardTokens.map(r => BN('0')), rewardTokens.map(r => BN('0'))]);
  let sellAmounts = res._soldAmounts;
  let minAmounts = res._swappedAmounts;
  // Add some slippage tolerance
  minAmounts = minAmounts.map(m => BN(m).div(BN('100')).mul(BN('97'))); // 3 % slippage
  await helpers.sudoCall(address, idleCDO, 'harvest', [false, skipIncentivesUpdate, skipFeeDeposit, rewardTokens.map(r => false), minAmounts, sellAmounts]);
  await helpers.sudoCall(address, idleCDO.idleToken, 'rebalance', []);

  await run("mine-multiple", {blocks: '500'});
  // Poking cToken contract to accrue interest and let strategyPrice increase.
  // (be sure to have a pinned block with allocation in compound)
  let cToken = await ethers.getContractAt("ICToken", testToken.cToken);
  await cToken.accrueInterest();
  await run("print-info", {cdo: idleCDO.address});
}

module.exports = {
  rebalanceFull,
  rebalanceIdleToken
}
