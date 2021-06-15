require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { expect } = require("chai");

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');

describe("IdleCDO", function () {
  beforeEach(async () => {
    // deploy contracts
    signers = await ethers.getSigners();
    owner = signers[0];
    AABuyer = signers[1];
    AABuyerAddr = AABuyer.address;
    BBBuyer = signers[2];
    BBBuyerAddr = BBBuyer.address;
    AABuyer2 = signers[3];
    AABuyer2Addr = AABuyer2.address;
    BBBuyer2 = signers[4];
    BBBuyer2Addr = BBBuyer2.address;

    const IdleCDOTranche = await ethers.getContractFactory("IdleCDOTranche");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const MockIdleToken = await ethers.getContractFactory("MockIdleToken");

    // 10M to creator
    weth = await MockERC20.deploy("WETH", "WETH");
    await weth.deployed();
    // 10M to creator
    underlying = await MockERC20.deploy("DAI", "DAI");
    await underlying.deployed();
    // 10M to creator
    incentiveToken = await MockERC20.deploy("IDLE", "IDLE");
    await incentiveToken.deployed();
    incentiveTokens = [incentiveToken.address];

    idleToken = await MockIdleToken.deploy(underlying.address);
    await idleToken.deployed();

    strategy = await helpers.deployUpgradableContract('IdleStrategy', [idleToken.address, owner.address], owner);
    idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens
      ],
      owner
    );

    AA = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
    BB = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());

    const stakingRewardsParams = [
      incentiveTokens,
      owner.address, // owner / guardian
      idleCDO.address,
      owner.address // recovery address
    ];
    stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AA.address, ...stakingRewardsParams], owner
    );
    stakingRewardsBB = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [BB.address, ...stakingRewardsParams], owner
    );
    await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);

    // Params
    initialAmount = BN('100000').mul(ONE_TOKEN(18));
    // Fund wallets
    await helpers.fundWallets(underlying.address, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, BBBuyer2Addr, idleToken.address], owner.address, initialAmount);

    // set IdleToken mocked params
    await idleToken.setTokenPriceWithFee(BN(10**18));
  });

  it("should not reinitialize the contract", async () => {
    await expect(
      idleCDO.connect(owner).initialize(
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'),
        incentiveTokens
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize params", async () => {
    expect(await idleCDO.AATranche()).to.equal(AA.address);
    expect(await idleCDO.BBTranche()).to.equal(BB.address);
    expect(await idleCDO.token()).to.equal(underlying.address);
    expect(await idleCDO.strategy()).to.equal(strategy.address);
    expect(await idleCDO.strategyToken()).to.equal(idleToken.address);
    expect(await idleCDO.rebalancer()).to.equal(owner.address);
    expect(await idleCDO.trancheAPRSplitRatio()).to.be.equal(BN('20000'));
    expect(await idleCDO.trancheIdealWeightRatio()).to.be.equal(BN('50000'));
    expect(await idleCDO.idealRange()).to.be.equal(BN('10000'));
    expect(await idleCDO.oneToken()).to.be.equal(BN(10**18));
    expect(await idleCDO.priceAA()).to.be.equal(BN(10**18));
    expect(await idleCDO.priceBB()).to.be.equal(BN(10**18));
    expect(await idleCDO.lastAAPrice()).to.be.equal(BN(10**18));
    expect(await idleCDO.lastBBPrice()).to.be.equal(BN(10**18));
    expect(await idleCDO.allowAAWithdraw()).to.equal(true);
    expect(await idleCDO.allowBBWithdraw()).to.equal(true);
    expect(await idleCDO.revertIfTooLow()).to.equal(true);
    expect(await idleToken.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await underlying.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await idleCDO.lastStrategyPrice()).to.be.equal(BN(10**18));
    expect(await idleCDO.fee()).to.be.equal(BN('10000'));
    expect(await idleCDO.feeReceiver()).to.equal('0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4');
    expect(await idleCDO.guardian()).to.equal(owner.address);
    expect(await idleCDO.weth()).to.equal('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2');
    expect(await idleCDO.incentiveTokens(0)).to.equal(incentiveTokens[0]);
    // OwnableUpgradeable
    expect(await idleCDO.owner()).to.equal(owner.address);
    // GuardedLaunchUpgradable
    expect(await idleCDO.limit()).to.be.equal(BN('1000000').mul(ONE_TOKEN(18)));
    expect(await idleCDO.governanceRecoveryFund()).to.equal(owner.address);
  });

  // ###############
  // AA deposit
  // ###############
  it("should depositAA when supply is 0", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    expect(aaTrancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.sub(_amount));
  });

  it("should get _amount of underlyings from msg.sender when depositAA", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.sub(_amount));
  });

  it("should update lastNAVAA when calling depositAA", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('1000').mul(ONE_TOKEN(18)));
  });

  it("should revert when calling depositAA and contract is paused", async () => {
    await idleCDO.pause();

    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(AABuyer).depositAA(_amount)
    ).to.be.revertedWith("Pausable: paused");
  });
  it("should revert when calling depositAA and we go above the deposit limit", async () => {
    await idleCDO._setLimit(BN('1'));
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(AABuyer).depositAA(_amount)
    ).to.be.revertedWith("Contract limit");
  });

  it("should revert when calling depositAA and strategyPrice decreased", async () => {
    await idleToken.setTokenPriceWithFee(BN(9**18));
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(AABuyer).depositAA(_amount)
    ).to.be.revertedWith("IDLE:DEFAULT_WAIT_SHUTDOWN");
  });

  it("should call mint the correct amount whe totalSupply > 0", async () => {
    // First deposit to initialize pool
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    // Do another deposit with another user
    const aaTrancheBal2 = await helpers.deposit('AA', idleCDO, AABuyer2Addr, _amount);
    // tranche price will be (new price - old price) - fee => (2 - 1) - 10% = 1.9 underlyings
    expect(aaTrancheBal2.div(ONE_TOKEN(18))).to.be.closeTo(BN('526'), 1); // 1000 / 1.9 => 526.31
  });

  it("should call _updatePrices when calling depositAA", async () => {
    // First deposit to initialize pool
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    // Do another deposit with another user
    const aaTrancheBal2 = await helpers.deposit('AA', idleCDO, AABuyer2Addr, _amount);
    // tranche price will be (new price - old price) - fee => (2 - 1) - 10% = 1.9 underlyings
    expect(await idleCDO.priceAA()).to.be.equal(BN('1900000000000000000'));
    expect(await idleCDO.priceBB()).to.be.equal(ONE_TOKEN(18));
    expect(aaTrancheBal2.div(ONE_TOKEN(18))).to.be.closeTo(BN('526'), 1); // 1000 / 1.9 => 526.31 // 1000 / 1.9 => 526.31
    // NAV before deposit is now 2000 => gain 1000 => perf fee 100
    expect(await idleCDO.unclaimedFees()).to.be.equal(BN('100').mul(ONE_TOKEN(18)));
    // 1000 + 900 = 1900 + 1000 just deposited = 2900
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('2900').mul(ONE_TOKEN(18)));
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('0').mul(ONE_TOKEN(18)));
  });

  // ###############
  // BB deposit
  // ###############
  it("should depositBB when supply is 0", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const trancheBal = await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount);
    expect(trancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(initialAmount.sub(_amount));
  });

  it("should get _amount of underlyings from msg.sender when depositBB", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const trancheBal = await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount);
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(initialAmount.sub(_amount));
  });

  it("should update lastNAVBB when calling depositBB", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const aaTrancheBal = await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount);
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('1000').mul(ONE_TOKEN(18)));
  });

  it("should revert when calling depositBB and contract is paused", async () => {
    await idleCDO.pause();

    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(BBBuyer).depositBB(_amount)
    ).to.be.revertedWith("Pausable: paused");
  });
  it("should revert when calling depositBB and we go above the deposit limit", async () => {
    await idleCDO._setLimit(BN('1'));
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(BBBuyer).depositBB(_amount)
    ).to.be.revertedWith("Contract limit");
  });

  it("should revert when calling depositBB and strategyPrice decreased", async () => {
    await idleToken.setTokenPriceWithFee(BN(9**18));
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(BBBuyer).depositBB(_amount)
    ).to.be.revertedWith("IDLE:DEFAULT_WAIT_SHUTDOWN");
  });

  it("should call mint the correct amount whe totalSupply > 0", async () => {
    // First deposit to initialize pool
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    // Do another deposit with another user
    const trancheBal2 = await helpers.deposit('BB', idleCDO, BBBuyer2Addr, _amount);
    // tranche price will be (new price - old price) - fee => (2 - 1) - 10% = 1.9 underlyings
    expect(trancheBal2.div(ONE_TOKEN(18))).to.be.closeTo(BN('526'), 1); // 1000 / 1.9 => 526.31
  });

  it("should call _updatePrices when calling depositBB", async () => {
    // First deposit to initialize pool
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    // Do another deposit with another user
    const aaTrancheBal2 = await helpers.deposit('BB', idleCDO, BBBuyer2Addr, _amount);
    // tranche price will be (new price - old price) - fee => (2 - 1) - 10% = 1.9 underlyings
    expect(await idleCDO.priceBB()).to.be.equal(BN('1900000000000000000'));
    expect(await idleCDO.priceAA()).to.be.equal(ONE_TOKEN(18));
    expect(aaTrancheBal2.div(ONE_TOKEN(18))).to.be.closeTo(BN('526'), 1); // 1000 / 1.9 => 526.31 // 1000 / 1.9 => 526.31
    // NAV before deposit is now 2000 => gain 1000 => perf fee 100
    expect(await idleCDO.unclaimedFees()).to.be.equal(BN('100').mul(ONE_TOKEN(18)));
    // 1000 + 900 = 1900 + 1000 just deposited = 2900
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('2900').mul(ONE_TOKEN(18)));
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('0').mul(ONE_TOKEN(18)));
  });

  // ###############
  // AA withdraw
  // ###############
  it("should revert when calling withdrawAA and contract is has been shutdown", async () => {
    await idleCDO.emergencyShutdown();

    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(AABuyer).withdrawAA(_amount)
    ).to.be.revertedWith("IDLE:AA_!ALLOWED");
  });

  it("should revert when calling withdrawAA and strategyPrice decreased", async () => {
    await idleToken.setTokenPriceWithFee(BN(9**18));
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(AABuyer).withdrawAA(_amount)
    ).to.be.revertedWith("IDLE:DEFAULT_WAIT_SHUTDOWN");
  });

  it("should withdrawAA all AA balance if _amount supplied is 0", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    const _amountW = BN('0').mul(ONE_TOKEN(18));
    await helpers.withdraw('AA', idleCDO, AABuyerAddr, _amountW);
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('900').mul(ONE_TOKEN(18)));
    expect(BN(await AA.balanceOf(AABuyerAddr))).to.be.equal(BN('0'));
    // redeem price is still 1, no harvests since the price increase
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount);
  });

  it("should withdrawAA all AA balance if _amount supplied is 0 and price lastTranchePrice just updated", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // to update lastTranchePriceAA which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    const _amountW = BN('0').mul(ONE_TOKEN(18));
    await helpers.withdraw('AA', idleCDO, AABuyerAddr, _amountW);
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('0').mul(ONE_TOKEN(18)));
    expect(BN(await AA.balanceOf(AABuyerAddr))).to.be.equal(BN('0'));
    // 2000 - 10% of fees on 1000 of gain -> initialAmount - 1000 + 1900
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(BN('900').mul(ONE_TOKEN(18)).add(initialAmount));
  });

  it("withdrawAA should redeem the _amount of AA tranche tokens requested", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // to update lastTranchePriceAA which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    const _amountW = BN('500').mul(ONE_TOKEN(18));
    await helpers.withdraw('AA', idleCDO, AABuyerAddr, _amountW);
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('950').mul(ONE_TOKEN(18)));
    expect(BN(await AA.balanceOf(AABuyerAddr))).to.be.equal(BN('500').mul(ONE_TOKEN(18)));
    // 2000 - 10% of fees on 1000 of gain -> initialAmount - 1000 + 1900 -> requested half => tot 950
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.sub(BN('50').mul(ONE_TOKEN(18))));
  });

  it("withdrawAA should _updatePrices", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    const _amountW = BN('500').mul(ONE_TOKEN(18));
    await helpers.withdraw('AA', idleCDO, AABuyerAddr, _amountW);
    // lastTranchePrice is still 1 so he will redeem only 500 underlyings
    expect(await idleCDO.lastTranchePrice(AA.address)).to.be.equal(BN('1').mul(ONE_TOKEN(18)));
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('1400').mul(ONE_TOKEN(18)));
    expect(await idleCDO.priceAA()).to.be.equal(BN('1900000000000000000'));
    expect(await idleCDO.unclaimedFees()).to.be.equal(BN('100').mul(ONE_TOKEN(18)));
  });
  it("should withdrawAA when in emergencyShutdown but allowAAWithdraw is true", async () => {

    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositAA(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // to update lastTranchePriceAA which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    await idleCDO.emergencyShutdown();
    await idleCDO.setAllowAAWithdraw(true);

    const _amountW = BN('0').mul(ONE_TOKEN(18));
    await helpers.withdraw('AA', idleCDO, AABuyerAddr, _amountW);
    expect(await idleCDO.lastNAVAA()).to.be.equal(BN('0').mul(ONE_TOKEN(18)));
    expect(BN(await AA.balanceOf(AABuyerAddr))).to.be.equal(BN('0'));
    // 2000 - 10% of fees on 1000 of gain -> initialAmount - 1000 + 1900
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(BN('900').mul(ONE_TOKEN(18)).add(initialAmount));
  });

  // ###############
  // BB withdraw
  // ###############
  it("should revert when calling withdrawBB and contract is has been shutdown", async () => {
    await idleCDO.emergencyShutdown();

    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(BBBuyer).withdrawBB(_amount)
    ).to.be.revertedWith("IDLE:BB_!ALLOWED");
  });

  it("should revert when calling withdrawBB and strategyPrice decreased", async () => {
    await idleToken.setTokenPriceWithFee(BN(9**18));
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await expect(
      idleCDO.connect(BBBuyer).withdrawBB(_amount)
    ).to.be.revertedWith("IDLE:DEFAULT_WAIT_SHUTDOWN");
  });
  it("should withdrawBB all BB balance if _amount supplied is 0", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    const _amountW = BN('0').mul(ONE_TOKEN(18));
    await helpers.withdraw('BB', idleCDO, BBBuyerAddr, _amountW);
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('900').mul(ONE_TOKEN(18)));
    expect(BN(await BB.balanceOf(BBBuyerAddr))).to.be.equal(BN('0'));
    // redeem price is still 1, no harvests since the price increase
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(initialAmount);
  });

  it("should withdrawBB all BB balance if _amount supplied is 0 and price lastTranchePrice just updated", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // to update lastTranchePriceBB which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    const _amountW = BN('0').mul(ONE_TOKEN(18));
    await helpers.withdraw('BB', idleCDO, BBBuyerAddr, _amountW);
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('0').mul(ONE_TOKEN(18)));
    expect(BN(await BB.balanceOf(BBBuyerAddr))).to.be.equal(BN('0'));
    // 2000 - 10% of fees on 1000 of gain -> initialAmount - 1000 + 1900
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(BN('900').mul(ONE_TOKEN(18)).add(initialAmount));
  });

  it("withdrawBB should redeem the _amount of BB tranche tokens requested", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // to update lastTranchePriceBB which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    const _amountW = BN('500').mul(ONE_TOKEN(18));
    await helpers.withdraw('BB', idleCDO, BBBuyerAddr, _amountW);
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('950').mul(ONE_TOKEN(18)));
    expect(BN(await BB.balanceOf(BBBuyerAddr))).to.be.equal(BN('500').mul(ONE_TOKEN(18)));
    // 2000 - 10% of fees on 1000 of gain -> initialAmount - 1000 + 1900 -> requested half => tot 950
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(initialAmount.sub(BN('50').mul(ONE_TOKEN(18))));
  });

  it("withdrawBB should _updatePrices", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));

    const _amountW = BN('500').mul(ONE_TOKEN(18));
    await helpers.withdraw('BB', idleCDO, BBBuyerAddr, _amountW);
    // lastTranchePrice is still 1 so he will redeem only 500 underlyings
    expect(await idleCDO.lastTranchePrice(BB.address)).to.be.equal(BN('1').mul(ONE_TOKEN(18)));
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('1400').mul(ONE_TOKEN(18)));
    expect(await idleCDO.priceBB()).to.be.equal(BN('1900000000000000000'));
    expect(await idleCDO.unclaimedFees()).to.be.equal(BN('100').mul(ONE_TOKEN(18)));
  });

  it("should withdrawBB when in emergencyShutdown but allowBBWithdraw is true", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // to update lastTranchePriceBB which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    await idleCDO.emergencyShutdown();
    await idleCDO.setAllowBBWithdraw(true);

    const _amountW = BN('0').mul(ONE_TOKEN(18));
    await helpers.withdraw('BB', idleCDO, BBBuyerAddr, _amountW);
    expect(await idleCDO.lastNAVBB()).to.be.equal(BN('0').mul(ONE_TOKEN(18)));
    expect(BN(await BB.balanceOf(BBBuyerAddr))).to.be.equal(BN('0'));
    // 2000 - 10% of fees on 1000 of gain -> initialAmount - 1000 + 1900
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(BN('900').mul(ONE_TOKEN(18)).add(initialAmount));
  });
  // ###############
  // AA and BB general
  // ###############
  it("should revert when redeemed amount is too low", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    await firstDepositBB(_amount);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    await idleToken.setLossOnRedeem(BN('101'));

    // to update lastTranchePriceBB which will be 1.9
    await idleCDO.harvest(false, true, [true], [BN('0')]);

    await expect(
      idleCDO.connect(BBBuyer).withdrawAA(_amount)
    ).to.be.revertedWith("IDLE:TOO_LOW");
  });

  const firstDepositAA = async (_amount) => {
    await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    // deposit in the lending protocol
    await idleCDO.harvest(true, true, [true], [BN('0')]);
  };
  const firstDepositBB = async (_amount) => {
    await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount);
    // deposit in the lending protocol
    await idleCDO.harvest(true, true, [true], [BN('0')]);
  };
});
