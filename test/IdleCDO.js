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
    Random = signers[5];
    RandomAddr = Random.address;
    Random2 = signers[6];
    Random2Addr = Random2.address;

    one = ONE_TOKEN(18);
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
    idleToken2 = await MockIdleToken.deploy(underlying.address);
    await idleToken2.deployed();

    strategy = await helpers.deployUpgradableContract('IdleStrategy', [idleToken.address, owner.address], owner);
    strategy2 = await helpers.deployUpgradableContract('IdleStrategy', [idleToken2.address, owner.address], owner);
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
      owner.address, // recovery address
      10, // cooling period
    ];
    stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AA.address, ...stakingRewardsParams], owner
    );
    stakingRewardsBB = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [BB.address, ...stakingRewardsParams], owner
    );
    await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);

    await idleCDO.setUnlentPerc(BN('0'));
    // Params
    initialAmount = BN('100000').mul(ONE_TOKEN(18));
    // Fund wallets
    await helpers.fundWallets(underlying.address, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, BBBuyer2Addr, idleToken.address], owner.address, initialAmount);

    // set IdleToken mocked params
    await idleToken.setTokenPriceWithFee(BN(10**18));
    // set IdleToken2 mocked params
    await idleToken2.setTokenPriceWithFee(BN(2 * 10**18));
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
    // Reset it here (it's set to 0 after initialization in beforeEach)
    await idleCDO.setUnlentPerc(BN('2000'));

    expect(await idleCDO.AATranche()).to.equal(AA.address);
    expect(await idleCDO.BBTranche()).to.equal(BB.address);
    expect(await idleCDO.token()).to.equal(underlying.address);
    expect(await idleCDO.strategy()).to.equal(strategy.address);
    expect(await idleCDO.strategyToken()).to.equal(idleToken.address);
    expect(await idleCDO.rebalancer()).to.equal(owner.address);
    expect(await idleCDO.trancheAPRSplitRatio()).to.be.equal(BN('20000'));
    expect(await idleCDO.trancheIdealWeightRatio()).to.be.equal(BN('50000'));
    expect(await idleCDO.idealRange()).to.be.equal(BN('10000'));
    expect(await idleCDO.unlentPerc()).to.be.equal(BN('2000'));
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
  it("should not revert when calling depositAA and limit is 0", async () => {
    await idleCDO._setLimit(BN('0')); // no limit
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const trancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    expect(trancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.sub(_amount));
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

  it("should not revert when calling depositAA and limit is 0", async () => {
    await idleCDO._setLimit(BN('0')); // no limit
    const _amount = BN('1000').mul(ONE_TOKEN(18));
    const trancheBal = await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount);
    expect(trancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.equal(initialAmount.sub(_amount));
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

  it("should withdrawAA all AA balance if _amount supplied is 0 and lastTranchePrice just updated", async () => {
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

  it("should withdrawBB all BB balance if _amount supplied is 0 and lastTranchePrice just updated", async () => {
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

  // ###############
  // Views
  // ###############
  it("tranchePrice should return the requested tranche price", async () => {
    // Initial price is 1 for both
    let tranchePriceAA = await idleCDO.tranchePrice(AA.address);
    let tranchePriceBB = await idleCDO.tranchePrice(BB.address);
    expect(tranchePriceAA.div(ONE_TOKEN(18))).to.be.equal(1);
    expect(tranchePriceBB.div(ONE_TOKEN(18))).to.be.equal(1);

    // First deposit to initialize pool
    const _amountAA = BN('1000').mul(ONE_TOKEN(18));
    const _amountBB = BN('1000').mul(ONE_TOKEN(18));
    await setupBasicDeposits(_amountAA, _amountBB);
    // nav is 4000

    tranchePriceAA = await idleCDO.tranchePrice(AA.address);
    tranchePriceBB = await idleCDO.tranchePrice(BB.address);
    // gain is 2000 -> fee is 200
    // 2000 + (20% of 1800) = 1360 / 1000 = 1.36
    expect(tranchePriceAA).to.be.equal(BN('1360000000000000000'));
    // 2000 + (80% of 1800) = 2440 / 1000 = 2.44
    expect(tranchePriceBB).to.be.equal(BN('2440000000000000000'));
  });
  it("lastTranchePrice should return the requested tranche price after an harvest", async () => {
    // Initial price is 1 for both
    let tranchePriceAA = await idleCDO.lastTranchePrice(AA.address);
    let tranchePriceBB = await idleCDO.lastTranchePrice(BB.address);
    expect(tranchePriceAA.div(ONE_TOKEN(18))).to.be.equal(1);
    expect(tranchePriceBB.div(ONE_TOKEN(18))).to.be.equal(1);

    // First deposit to initialize pool
    const _amountAA = BN('1000').mul(ONE_TOKEN(18));
    const _amountBB = BN('1000').mul(ONE_TOKEN(18));
    await setupBasicDeposits(_amountAA, _amountBB);
    // harvest just made so price is equal to tranchePrice
    tranchePriceAA = await idleCDO.lastTranchePrice(AA.address);
    tranchePriceBB = await idleCDO.lastTranchePrice(BB.address);
    // gain is 2000 -> fee is 200
    // 2000 + (20% of 1800) = 1360 / 1000 = 1.36
    expect(tranchePriceAA).to.be.equal(BN('1360000000000000000'));
    // 2000 + (80% of 1800) = 2440 / 1000 = 2.44
    expect(tranchePriceBB).to.be.equal(BN('2440000000000000000'));
  });

  it("lastTranchePrice should return the last saved price before an harvest", async () => {
    // Initial price is 1 for both
    let tranchePriceAA = await idleCDO.lastTranchePrice(AA.address);
    let tranchePriceBB = await idleCDO.lastTranchePrice(BB.address);
    expect(tranchePriceAA.div(ONE_TOKEN(18))).to.be.equal(1);
    expect(tranchePriceBB.div(ONE_TOKEN(18))).to.be.equal(1);

    // First deposit to initialize pool
    const _amountAA = BN('1000').mul(ONE_TOKEN(18));
    const _amountBB = BN('1000').mul(ONE_TOKEN(18));
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // harvest just made so price is equal to tranchePrice
    tranchePriceAA = await idleCDO.lastTranchePrice(AA.address);
    tranchePriceBB = await idleCDO.lastTranchePrice(BB.address);
    expect(tranchePriceAA.div(ONE_TOKEN(18))).to.be.equal(1);
    expect(tranchePriceBB.div(ONE_TOKEN(18))).to.be.equal(1);
  });

  it("getContractValue should return the current NAV", async () => {
    // Initial value is 0
    let value = await idleCDO.getContractValue();
    expect(value).to.be.equal(0);

    // First deposit to initialize pool
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB);
    // gain is 2000 -> fee is 200 but it's reinvested so NAV is still 4000
    value = await idleCDO.getContractValue();
    expect(value).to.be.equal(BN('4000').mul(one));
  });

  it("getContractValue should return the current NAV", async () => {
    // Initial value is 0
    let value = await idleCDO.getContractValue();
    expect(value).to.be.equal(0);

    // First deposit to initialize pool
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    // skip last price update so fees are not counted yet
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // NAV is 4000
    value = await idleCDO.getContractValue();
    expect(value).to.be.equal(BN('4000').mul(one));
  });

  it("getIdealApr should return the ideal apr with ideal tranche ratio", async () => {
    await idleToken.setFee(BN('0'));
    // Initial apr 10%
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));

    let aprAA = await idleCDO.getIdealApr(AA.address);
    let aprBB = await idleCDO.getIdealApr(BB.address);
    expect(aprAA.div(one)).to.be.equal(4);
    expect(aprBB.div(one)).to.be.equal(16);
  });

  it("getApr should return the current apr with the current tranche ratio", async () => {
    await idleToken.setFee(BN('0'));
    // Initial apr 10%
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));

    let aprAA = await idleCDO.getApr(AA.address);
    let aprBB = await idleCDO.getApr(BB.address);
    expect(aprAA.div(one)).to.be.equal(0);
    expect(aprBB.div(one)).to.be.equal(10);

    // First deposit to initialize pool
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    // skip last price update so fees are not counted yet
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // NAV is 4000 because virtualPrice is used in getCurrentAARatio in getApr
    // 3800 (without fees) -> 1800 is the gain -> 1800 * 20% = 360 to AA
    // 1440 to BB -> NAVAA = 1360 -> NAVBB = 2440
    aprAA = await idleCDO.getApr(AA.address);
    aprBB = await idleCDO.getApr(BB.address);
    // tranche
    // 5.58%
    expect(aprAA).to.be.equal(BN('5588309257034284277'));
    // 12.4%
    expect(aprBB).to.be.equal(BN('12458924483343975331')); // +- 0.1%
  });

  it("strategyAPR should return the current strategy apr", async () => {
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));
    let apr = await idleCDO.strategyAPR();
    expect(apr).to.be.equal(BN('10').mul(ONE_TOKEN(18)));
  });

  it("strategyPrice should return the current strategy price", async () => {
    await idleToken.setTokenPriceWithFee(BN('10').mul(ONE_TOKEN(18)));
    let apr = await idleCDO.strategyPrice();
    expect(apr).to.be.equal(BN('10').mul(ONE_TOKEN(18)));
  });

  it("strategyPrice should return the current strategy rewards", async () => {
    await idleToken.setGovTokens([incentiveToken.address]);
    let rewards = await idleCDO.getRewards();
    expect(rewards.length).to.be.equal(1);
    expect(rewards[0]).to.be.equal(incentiveToken.address);
  });

  it("getCurrentAARatio should return the current AA ratio", async () => {
    await idleToken.setFee(BN('0'));
    // Initial apr 10%
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));

    let ratio = await idleCDO.getCurrentAARatio();
    expect(ratio).to.be.equal(0);

    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await helpers.deposit('AA', idleCDO, AABuyerAddr, _amountAA);
    await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amountBB);
    await idleCDO.harvest(true, true, [true], [BN('0')]);

    ratio = await idleCDO.getCurrentAARatio();
    expect(ratio).to.be.equal(50000); // 50%

    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // NAVAA = 1360 -> NAVBB = 2440 -> tot 3800
    // 1360 / 3800 = 35.7%

    ratio = await idleCDO.getCurrentAARatio();
    expect(ratio).to.be.equal(35789); // +- 35.7%
  });

  it("virtualPrice should return the current price for a tranche considering the full nav when no _updatePrice is called after price increase", async () => {
    await idleToken.setFee(BN('0'));
    // Initial apr 10%
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));

    let priceAA = await idleCDO.virtualPrice(AA.address);
    let priceBB = await idleCDO.virtualPrice(BB.address);
    expect(priceAA).to.be.equal(one);
    expect(priceBB).to.be.equal(one);

    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);

    priceAA = await idleCDO.virtualPrice(AA.address);
    priceBB = await idleCDO.virtualPrice(BB.address);
    expect(priceAA).to.be.equal(BN('1360000000000000000'));
    expect(priceBB).to.be.equal(BN('2440000000000000000'));
  });

  it("virtualPrice should return the current price for a tranche considering the full nav", async () => {
    // NOTE: it's the same test as above but with a flag changed in setupBasicDeposits

    await idleToken.setFee(BN('0'));
    // Initial apr 10%
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));

    let priceAA = await idleCDO.virtualPrice(AA.address);
    let priceBB = await idleCDO.virtualPrice(BB.address);
    expect(priceAA).to.be.equal(one);
    expect(priceBB).to.be.equal(one);

    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, false);

    priceAA = await idleCDO.virtualPrice(AA.address);
    priceBB = await idleCDO.virtualPrice(BB.address);
    expect(priceAA).to.be.equal(BN('1360000000000000000'));
    expect(priceBB).to.be.equal(BN('2440000000000000000'));
  });

  it("virtualBalance should return the current balance for a tranche considering the full nav", async () => {
    await idleToken.setFee(BN('0'));
    // Initial apr 10%
    await idleToken.setApr(BN('10').mul(ONE_TOKEN(18)));

    let balAA = await idleCDO.virtualBalance(AA.address);
    let balBB = await idleCDO.virtualBalance(BB.address);
    expect(balAA).to.be.equal(0);
    expect(balBB).to.be.equal(0);

    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);

    balAA = await idleCDO.virtualBalance(AA.address);
    balBB = await idleCDO.virtualBalance(BB.address);
    expect(balAA).to.be.equal(BN('1360').mul(one));
    expect(balBB).to.be.equal(BN('2440').mul(one));
  });

  it("getIncentiveTokens should return the current incentiveTokens array", async () => {
    let rewards = await idleCDO.getIncentiveTokens();
    expect(rewards.length).to.be.equal(1);
    expect(rewards[0]).to.be.equal(incentiveToken.address);
  });

  // ###############
  // Protected
  // ###############

  it("liquidate should liquidate the requested amount", async () => {
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);

    expect(await underlying.balanceOf(idleCDO.address)).to.be.equal(BN('0').mul(one));
    balAA = await idleCDO.liquidate(BN('1000').mul(one), true);
    expect(await underlying.balanceOf(idleCDO.address)).to.be.equal(BN('1000').mul(one));
  });

  it("liquidate should be called only by rebalancer or owner", async () => {
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);

    await expect(
      idleCDO.connect(BBBuyer).liquidate(BN('1000'), true)
    ).to.be.revertedWith("IDLE:!AUTH");

    await idleCDO.setRebalancer(BBBuyer.address);

    await idleCDO.connect(BBBuyer).liquidate(BN('1000'), true);
    expect(await underlying.balanceOf(idleCDO.address)).to.be.equal(BN('1000'));
  });
  it("setAllowAAWithdraw should set the relative flag and be called only by the owner", async () => {
    await idleCDO.setAllowAAWithdraw(true);
    expect(await idleCDO.allowAAWithdraw()).to.be.equal(true);

    await expect(
      idleCDO.connect(BBBuyer).setAllowAAWithdraw(false)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setAllowBBWithdraw should set the relative flag and be called only by the owner", async () => {
    await idleCDO.setAllowBBWithdraw(true);
    expect(await idleCDO.allowBBWithdraw()).to.be.equal(true);

    await expect(
      idleCDO.connect(BBBuyer).setAllowBBWithdraw(false)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setSkipDefaultCheck should set the relative flag and be called only by the owner", async () => {
    await idleCDO.setSkipDefaultCheck(true);
    expect(await idleCDO.skipDefaultCheck()).to.be.equal(true);

    await expect(
      idleCDO.connect(BBBuyer).setSkipDefaultCheck(false)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setRevertIfTooLow should set the relative flag and be called only by the owner", async () => {
    await idleCDO.setRevertIfTooLow(true);
    expect(await idleCDO.revertIfTooLow()).to.be.equal(true);

    await expect(
      idleCDO.connect(BBBuyer).setRevertIfTooLow(false)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setRebalancer should set the relative address and be called only by the owner", async () => {
    const val = RandomAddr;
    await idleCDO.setRebalancer(val);
    expect(await idleCDO.rebalancer()).to.be.equal(val);

    await expect(
      idleCDO.setRebalancer(addresses.addr0)
    ).to.be.revertedWith("IDLE:IS_0");

    await expect(
      idleCDO.connect(BBBuyer).setRebalancer(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setFeeReceiver should set the relative address and be called only by the owner", async () => {
    const val = RandomAddr;
    await idleCDO.setFeeReceiver(val);
    expect(await idleCDO.feeReceiver()).to.be.equal(val);

    await expect(
      idleCDO.setFeeReceiver(addresses.addr0)
    ).to.be.revertedWith("IDLE:IS_0");

    await expect(
      idleCDO.connect(BBBuyer).setFeeReceiver(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setGuardian should set the relative address and be called only by the owner", async () => {
    const val = RandomAddr;
    await idleCDO.setGuardian(val);
    expect(await idleCDO.guardian()).to.be.equal(val);

    await expect(
      idleCDO.setGuardian(addresses.addr0)
    ).to.be.revertedWith("IDLE:IS_0");

    await expect(
      idleCDO.connect(BBBuyer).setGuardian(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setFee should set the relative address and be called only by the owner", async () => {
    const val = BN('15000');
    await idleCDO.setFee(val);
    expect(await idleCDO.fee()).to.be.equal(val);

    await expect(
      idleCDO.setFee(BN('20001'))
    ).to.be.revertedWith("IDLE:TOO_HIGH");

    await expect(
      idleCDO.connect(BBBuyer).setFee(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setIdealRange should set the relative address and be called only by the owner", async () => {
    const val = BN('15000');
    await idleCDO.setIdealRange(val);
    expect(await idleCDO.idealRange()).to.be.equal(val);

    await expect(
      idleCDO.setIdealRange(BN('100001'))
    ).to.be.revertedWith("IDLE:TOO_HIGH");

    await expect(
      idleCDO.connect(BBBuyer).setIdealRange(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setUnlentPerc should set the unlent percentage and be called only by the owner", async () => {
    const val = BN('15000');
    await idleCDO.setUnlentPerc(val);
    expect(await idleCDO.unlentPerc()).to.be.equal(val);

    await expect(
      idleCDO.setUnlentPerc(BN('100001'))
    ).to.be.revertedWith("IDLE:TOO_HIGH");

    await expect(
      idleCDO.connect(BBBuyer).setUnlentPerc(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("setStakingRewards should set the relative addresses for incentiveTokens", async () => {
    await idleCDO.setStakingRewards(RandomAddr, Random2Addr);
    expect(await idleCDO.AAStaking()).to.be.equal(RandomAddr);
    expect(await idleCDO.BBStaking()).to.be.equal(Random2Addr);

    expect(await incentiveToken.allowance(idleCDO.address, RandomAddr)).to.be.equal(MAX_UINT);
    expect(await incentiveToken.allowance(idleCDO.address, Random2Addr)).to.be.equal(MAX_UINT);

    await idleCDO.setStakingRewards(AABuyerAddr, AABuyer2Addr);

    expect(await incentiveToken.allowance(idleCDO.address, RandomAddr)).to.be.equal(0);
    expect(await incentiveToken.allowance(idleCDO.address, Random2Addr)).to.be.equal(0);

    await expect(
      idleCDO.connect(BBBuyer).setStakingRewards(RandomAddr, Random2Addr)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
  it("emergencyShutdown should pause everything", async () => {
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);

    await idleCDO.emergencyShutdown();
    expect(await idleCDO.allowAAWithdraw()).to.be.equal(false);
    expect(await idleCDO.allowBBWithdraw()).to.be.equal(false);
    expect(await idleCDO.paused()).to.be.equal(true);
    expect(await idleCDO.skipDefaultCheck()).to.be.equal(true);
    expect(await idleCDO.revertIfTooLow()).to.be.equal(true);
  });
  it("emergencyShutdown should be called only by guardian or owner", async () => {
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);

    await expect(
      idleCDO.connect(BBBuyer).emergencyShutdown()
    ).to.be.revertedWith("IDLE:!AUTH");

    await idleCDO.setGuardian(BBBuyer.address);

    await idleCDO.connect(BBBuyer).emergencyShutdown();
    expect(await idleCDO.allowAAWithdraw()).to.be.equal(false);
    expect(await idleCDO.allowBBWithdraw()).to.be.equal(false);
    expect(await idleCDO.paused()).to.be.equal(true);
    expect(await idleCDO.skipDefaultCheck()).to.be.equal(true);
    expect(await idleCDO.revertIfTooLow()).to.be.equal(true);
  });

  it("pause/unpause should be called only by guardian or owner", async () => {
    // owner
    await idleCDO.pause();
    expect(await idleCDO.paused()).to.be.equal(true);
    await idleCDO.unpause();
    expect(await idleCDO.paused()).to.be.equal(false);

    // only allowed people
    await expect(
      idleCDO.connect(BBBuyer).emergencyShutdown()
    ).to.be.revertedWith("IDLE:!AUTH");

    await idleCDO.setGuardian(BBBuyer.address);

    // guardian allowed
    await idleCDO.connect(BBBuyer).pause();
    expect(await idleCDO.paused()).to.be.equal(true);
    await idleCDO.connect(BBBuyer).unpause();
    expect(await idleCDO.paused()).to.be.equal(false);
  });

  it("setStrategy should set the relative addresses for incentiveTokens", async () => {
    await expect(
      idleCDO.setStrategy(addresses.addr0, [Random2Addr])
    ).to.be.revertedWith("IDLE:IS_0");

    await expect(
      idleCDO.connect(BBBuyer).setStrategy(RandomAddr, [Random2Addr])
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await idleCDO.setStrategy(strategy2.address, [Random2Addr]);
    expect(await idleCDO.strategy()).to.be.equal(strategy2.address);
    expect(await idleCDO.getIncentiveTokens()).to.have.all.members([Random2Addr]);
    expect(await idleCDO.strategyToken()).to.be.equal(idleToken2.address);
    expect(await idleCDO.lastStrategyPrice()).to.be.equal(one.mul(BN('2')));

    expect(await idleToken.allowance(idleCDO.address, strategy.address)).to.be.equal(0);
    expect(await underlying.allowance(idleCDO.address, strategy.address)).to.be.equal(0);

    expect(await underlying.allowance(idleCDO.address, strategy2.address)).to.be.equal(MAX_UINT);
    expect(await idleToken2.allowance(idleCDO.address, strategy2.address)).to.be.equal(MAX_UINT);
  });
  it("transferToken should be callable only from owner", async () => {
    const _amountAA = BN('1000').mul(one);
    await helpers.deposit('AA', idleCDO, AABuyerAddr, _amountAA);

    const initialBal = await underlying.balanceOf(owner.address);

    await expect(
      idleCDO.connect(BBBuyer).transferToken(underlying.address, BN('1000').mul(one))
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await idleCDO.setGuardian(BBBuyer.address);

    await idleCDO.transferToken(underlying.address, BN('1000').mul(one));
    const finalBal = await underlying.balanceOf(owner.address);
    expect(finalBal.sub(initialBal)).to.be.equal(BN('1000').mul(one));
  });
  it("harvest should be callable only from owner or rebalancer", async () => {
    const _amountAA = BN('1000').mul(one);
    await helpers.deposit('AA', idleCDO, AABuyerAddr, _amountAA);

    await expect(
      idleCDO.connect(BBBuyer).harvest(true, true, [true], [BN('0')])
    ).to.be.revertedWith("IDLE:!AUTH");

    await idleCDO.setRebalancer(BBBuyer.address);

    await idleCDO.connect(BBBuyer).harvest(true, true, [true], [BN('0')]);
    // underlying should have been deposited in Idle
    const finalBal = await idleToken.balanceOf(idleCDO.address);
    expect(finalBal).to.be.equal(_amountAA);
  });

  it("harvest should skipRedeem if flag is passed", async () => {
    const _amountAA = BN('1000').mul(one);
    await helpers.deposit('AA', idleCDO, AABuyerAddr, _amountAA);
    await idleToken.setTokenPriceWithFee(BN(2 * 10**18));
    await idleCDO.harvest(true, true, [true], [BN('0')]);
    // underlying should have been deposited in Idle
    const finalBal = await idleToken.balanceOf(idleCDO.address);
    expect(finalBal).to.be.equal(_amountAA.div(2));
    // prices have not been updated
    expect(await idleCDO.priceAA()).to.be.equal(one);
    expect(await idleCDO.lastTranchePrice(AA.address)).to.be.equal(one);
  });

  it("harvest should redeem rewards", async () => {
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB);

    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amountAA);

    const initialBal = await incentiveToken.balanceOf(idleCDO.address);
    await idleCDO.harvest(false, true, [true], [BN('0')]);
    const finalBal = await incentiveToken.balanceOf(idleCDO.address);
    expect(finalBal.sub(initialBal)).to.be.equal(_amountAA);
  });

  it("harvest should keep an unlent reserve", async () => {
    await idleCDO.setUnlentPerc(BN('2000'));

    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB);

    const initialBal = await underlying.balanceOf(idleCDO.address);
    await idleCDO.harvest(true, true, [true], [BN('0')]);
    const finalBal = await underlying.balanceOf(idleCDO.address);
    expect(finalBal).to.be.equal(initialBal.mul(await idleCDO.unlentPerc()).div(BN('100000')));
  });

  it("harvest should call _updatePrices and _updateLastTranchePrices if we are not skipping redeem of rewards", async () => {
    // Initialize deposits
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amountAA);

    expect(await idleCDO.priceAA()).to.be.equal(one);
    expect(await idleCDO.priceBB()).to.be.equal(one);
    expect(await idleCDO.lastTranchePrice(AA.address)).to.be.equal(one);
    expect(await idleCDO.lastTranchePrice(BB.address)).to.be.equal(one);

    await idleCDO.harvest(false, true, [true], [BN('0')]);

    // gain is 2000 -> fee is 200
    // 2000 + (20% of 1800) = 1360 / 1000 = 1.36
    expect(await idleCDO.priceAA()).to.be.equal(BN('1360000000000000000'));
    // 2000 + (80% of 1800) = 2440 / 1000 = 2.44
    expect(await idleCDO.priceBB()).to.be.equal(BN('2440000000000000000'));
    expect(await idleCDO.lastTranchePrice(AA.address)).to.be.equal(BN('1360000000000000000'));
    expect(await idleCDO.lastTranchePrice(BB.address)).to.be.equal(BN('2440000000000000000'));
  });
  it("harvest should deposit fees (as AA tranche tokens) if curr AA ratio is low", async () => {
    // set fee receiver
    await idleCDO.setFeeReceiver(RandomAddr);
    // Initialize deposits
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amountAA);
    // gain is 2000 -> fee is 200
    const gain = BN('200').mul(one);
    // NAVAA = 1360 -> NAVBB = 2440 -> tot 3800
    // AARatio = 1360 / 3800 = 35.789%
    // ideal ratio = 50% +- 10%
    // so it will mint AA tokens
    const vPriceAA = await idleCDO.virtualPrice(AA.address);
    const expected = gain.mul(one).div(vPriceAA);

    expect(await AA.balanceOf(RandomAddr)).to.be.equal(BN('0'));
    await idleCDO.harvest(false, true, [true], [BN('0')]);
    expect(await AA.balanceOf(RandomAddr)).to.be.equal(expected);
    expect(await idleCDO.unclaimedFees()).to.be.equal(0);
    const navAAafter = await idleCDO.lastNAVAA();
    // 1360 + 200 gain in AA from fees = 1560
    expect(navAAafter).to.be.equal(BN('1560').mul(one));
  });

  it("harvest should deposit fees (as BB tranche tokens) if curr AA ratio is high", async () => {
    // set fee receiver
    await idleCDO.setFeeReceiver(RandomAddr);
    // Initialize deposits
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('0').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amountAA);
    // gain is 1000 -> fee is 100
    const gain = BN('100').mul(one);
    // NAVAA = 1900 -> NAVBB = 0 -> tot 1900
    // AARatio = 100%
    // ideal ratio = 50% +- 10%
    // so it will mint BB tokens
    const vPriceBB = await idleCDO.virtualPrice(BB.address);
    const expected = gain.mul(one).div(vPriceBB);

    expect(await BB.balanceOf(RandomAddr)).to.be.equal(BN('0'));
    await idleCDO.harvest(false, true, [true], [BN('0')]);
    expect(await BB.balanceOf(RandomAddr)).to.be.equal(expected);
    expect(await idleCDO.unclaimedFees()).to.be.equal(0);
    const navBBafter = await idleCDO.lastNAVBB();
    expect(navBBafter).to.be.equal(BN('100').mul(one));
  });

  it("harvest should give incentive to AA staking rewards if AA ratio is low", async () => {
    const feeReceiver = RandomAddr;
    // set fee receiver
    await idleCDO.setFeeReceiver(feeReceiver);
    // Initialize deposits
    const _amount = BN('1000').mul(one);
    const _amountBB = BN('1000').mul(one);
    await setupBasicDeposits(_amount, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amount);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amount);

    await idleCDO.harvest(false, false, [true], [BN('0')]);
    expect(await incentiveToken.balanceOf(stakingRewardsAA.address)).to.be.equal(_amount);
    expect(await incentiveToken.balanceOf(stakingRewardsBB.address)).to.be.equal(0);
  });

  it("harvest should give incentive to BB staking rewards if AA ratio is high", async () => {
    const feeReceiver = RandomAddr;
    // set fee receiver
    await idleCDO.setFeeReceiver(feeReceiver);
    // Initialize deposits
    const _amount = BN('1000').mul(one);
    const _amountBB = BN('0').mul(one);
    await setupBasicDeposits(_amount, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amount);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amount);

    await idleCDO.harvest(false, false, [true], [BN('0')]);
    expect(await incentiveToken.balanceOf(stakingRewardsAA.address)).to.be.equal(0);
    expect(await incentiveToken.balanceOf(stakingRewardsBB.address)).to.be.equal(_amount);
  });

  it("harvest should split incentives to both AA and BB staking rewards contracts if currAA ratio is in the ideal range", async () => {
    const feeReceiver = RandomAddr;
    // set fee receiver
    await idleCDO.setFeeReceiver(feeReceiver);
    // Initialize deposits
    const _amount = BN('1000').mul(one);
    const _amountBB = BN('500').mul(one);
    await setupBasicDeposits(_amount, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amount);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amount);

    expect(await incentiveToken.balanceOf(idleCDO.address)).to.be.equal(0);
    await idleCDO.harvest(false, false, [true], [BN('0')]);
    expect(await incentiveToken.balanceOf(idleCDO.address)).to.be.equal(0);
    // 20% of 1000
    expect(await incentiveToken.balanceOf(stakingRewardsAA.address)).to.be.equal(BN('200').mul(one));
    // 80% of 1000
    expect(await incentiveToken.balanceOf(stakingRewardsBB.address)).to.be.equal(BN('800').mul(one));
  });

  it("harvest should not sell incentiveTokens", async () => {
    const feeReceiver = RandomAddr;
    // set fee receiver
    await idleCDO.setFeeReceiver(feeReceiver);
    // Initialize deposits
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('0').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amountAA);

    await idleCDO.harvest(false, true, [false], [BN('0')]);
    expect(await incentiveToken.balanceOf(feeReceiver)).to.be.equal(0);
    expect(await incentiveToken.balanceOf(idleCDO.address)).to.be.equal(_amountAA);
  });

  it("harvest should sell non incentiveTokens", async () => {
    const feeReceiver = RandomAddr;
    // set fee receiver
    await idleCDO.setFeeReceiver(feeReceiver);
    await idleCDO.setIncentiveTokens([]);
    // Initialize deposits
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('0').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(_amountAA);

    //  NOTE: It will revert because no uniswap contract is deployed in teh network
    // ie is trying to sell the incentiveToken on uniswap
    await expect(
      idleCDO.harvest(false, true, [false], [BN('0')])
    ).to.be.revertedWith("Transaction reverted: function call to a non-contract account");
  });

  it("harvest should sell non incentiveTokens if bal > 0", async () => {
    const feeReceiver = RandomAddr;
    // set fee receiver
    await idleCDO.setFeeReceiver(feeReceiver);
    await idleCDO.setIncentiveTokens([]);
    // Initialize deposits
    const _amountAA = BN('1000').mul(one);
    const _amountBB = BN('0').mul(one);
    await setupBasicDeposits(_amountAA, _amountBB, true);
    // Mock the return of gov tokens
    await incentiveToken.transfer(idleToken.address, _amountAA);
    await idleToken.setGovTokens([incentiveToken.address]);
    await idleToken.setGovAmount(0);

    // NOTE: it works which means is not trying to sell on uniswap
    await idleCDO.harvest(false, true, [false], [BN('0')]);
  });

  // ###############
  // Helpers
  // ###############
  const setupBasicDeposits = async (_amountAA, _amountBB, skipLastHarvest = false) => {
    await helpers.deposit('AA', idleCDO, AABuyerAddr, _amountAA);
    await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amountBB);
    // nav is 2000
    await idleCDO.harvest(true, true, [true], [BN('0')]);
    // update lending protocol price which is now 2
    await idleToken.setTokenPriceWithFee(BN('2').mul(ONE_TOKEN(18)));
    // nav is 4000
    // updatePrices of mint and redeem
    if (!skipLastHarvest) {
      await idleCDO.harvest(false, true, [true], [BN('0')]);
    }
  };
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
