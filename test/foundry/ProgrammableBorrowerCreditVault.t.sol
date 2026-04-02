// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {IdleCDO} from "../../contracts/IdleCDO.sol";
import {IdleCDOTranche} from "../../contracts/IdleCDOTranche.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {ProgrammableBorrower} from "../../contracts/strategies/idle/ProgrammableBorrower.sol";
import {IMMVault} from "../../contracts/interfaces/morpho/IMMVault.sol";
import {IMorpho} from "../../contracts/interfaces/morpho/IMorpho.sol";

error NotAllowed();
error InvalidAmount();
error InvalidAddress();
error InsufficientBorrowable();

contract TestProgrammableBorrowerCreditVault is Test {
  using stdStorage for StdStorage;

  address internal constant TL_MULTISIG = address(0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814);
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
  address internal constant STEAKHOUSE_USDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
  uint256 internal constant FORK_BLOCK = 19225935;
  string internal constant BORROWER_NAME = "testBorrower";

  address internal owner = address(0xdeadbad);
  address internal rebalancer = address(0xbaddead);
  address internal manager = makeAddr("manager");
  address internal placeholderBorrower = makeAddr("placeholderBorrower");
  address internal revolvingBorrower = makeAddr("revolvingBorrower");

  uint256 internal initialProvidedApr = 10e18;
  uint256 internal oneScale;

  IdleCDO internal idleCDO;
  IdleCDOEpochVariant internal cdoEpoch;
  IdleCDOTranche internal aaTranche;
  IdleCDOTranche internal bbTranche;
  IERC20Detailed internal underlying;
  IdleCreditVault internal strategy;
  ProgrammableBorrower internal programmableBorrower;
  IMMVault internal morphoVault = IMMVault(STEAKHOUSE_USDC);

  function setUp() public {
    vm.createSelectFork("mainnet", FORK_BLOCK);

    strategy = new IdleCreditVault();
    stdstore.target(address(strategy)).sig(strategy.token.selector).checked_write(address(0));
    strategy.initialize(USDC, owner, manager, placeholderBorrower, BORROWER_NAME, initialProvidedApr);

    cdoEpoch = new IdleCDOEpochVariant();
    stdstore.target(address(cdoEpoch)).sig(cdoEpoch.token.selector).checked_write(address(0));
    cdoEpoch.initialize(0, USDC, address(this), owner, rebalancer, address(strategy), 100000);
    idleCDO = IdleCDO(address(cdoEpoch));

    underlying = IERC20Detailed(USDC);
    aaTranche = IdleCDOTranche(idleCDO.AATranche());
    bbTranche = IdleCDOTranche(idleCDO.BBTranche());
    oneScale = 10 ** underlying.decimals();

    vm.prank(owner);
    strategy.setWhitelistedCDO(address(cdoEpoch));
    vm.prank(owner);
    strategy.setMaxApr(0);

    vm.startPrank(owner);
    cdoEpoch.setIsAYSActive(false);
    cdoEpoch.setFeeParams(TL_MULTISIG, 0);
    cdoEpoch.setInstantWithdrawParams(3 days, 1.5e18, false);
    cdoEpoch.setLossToleranceBps(5000);
    cdoEpoch.setEpochParams(36.5 days, 5 days);
    cdoEpoch.setKeyringParams(address(0), 0, false);
    vm.stopPrank();

    deal(USDC, address(this), 1_000_000 * oneScale, true);
    underlying.approve(address(cdoEpoch), type(uint256).max);

    programmableBorrower = new ProgrammableBorrower();
    stdstore
      .target(address(programmableBorrower))
      .sig(programmableBorrower.underlyingToken.selector)
      .checked_write(address(0));
    programmableBorrower.initialize(USDC, STEAKHOUSE_USDC, address(cdoEpoch), address(this));
    programmableBorrower.setBorrower(revolvingBorrower);
    programmableBorrower.setBorrowerApr(365e18);

    vm.prank(owner);
    strategy.setBorrower(address(programmableBorrower));

    vm.prank(owner);
    cdoEpoch.setIsProgrammableBorrower(true);

    vm.prank(manager);
    strategy.setAprs(0, 0);

    vm.prank(revolvingBorrower);
    underlying.approve(address(programmableBorrower), type(uint256).max);
  }

  function testProgrammableBorrowerStopEpochAutoRealizesInterestWithRealVault() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 5_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    assertApproxEqAbs(_programmableMorphoAssets(), amount, 2, "epoch funds not parked in morpho");

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(block.timestamp + 30 days);
    _accrueMorphoVaultInterest();

    uint256 expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    uint256 expectedMorphoInterest = programmableBorrower.morphoInterestAccrued();
    uint256 expectedTotalInterest = programmableBorrower.totalInterestDueNow();
    uint256 pricePre = cdoEpoch.virtualPrice(address(aaTranche));

    assertGt(expectedBorrowerInterest, 0, "borrower interest should accrue");
    assertGt(expectedMorphoInterest, 0, "morpho interest should accrue");

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();
    expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    expectedMorphoInterest = programmableBorrower.morphoInterestAccrued();
    expectedTotalInterest = programmableBorrower.totalInterestDueNow();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertGt(cdoEpoch.virtualPrice(address(aaTranche)), pricePre, "AA price did not increase");
    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedTotalInterest, 10, "epoch interest mismatch");
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestDebt(),
      expectedBorrowerInterest,
      5,
      "fronted borrower interest debt mismatch"
    );
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "current borrower interest not cleared");
    assertEq(strategy.unscaledApr(), 0, "strategy apr should stay zero");
  }

  function testProgrammableBorrowerMorphoLossDoesNotReduceSettledBorrowerDebt() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 5_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    // Simulate a real loss on the MetaMorpho position by moving actual vault shares away from the
    // programmable borrower. This keeps the test on a real fork with the live deployed vault while
    // exercising the accounting branch where the vault sleeve is down.
    uint256 sharesToRescue = morphoVault.balanceOf(address(programmableBorrower)) / 5;
    assertGt(sharesToRescue, 0, "expected programmable borrower shares");
    programmableBorrower.rescueTokens(address(morphoVault), makeAddr("shareSink"), sharesToRescue);

    uint256 expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    uint256 expectedMorphoLoss = programmableBorrower.morphoLoss();
    uint256 expectedTotalInterest = programmableBorrower.totalInterestDueNow();

    assertGt(expectedBorrowerInterest, 0, "borrower interest should accrue");
    assertGt(expectedMorphoLoss, 0, "morpho loss should be recognized");
    assertLt(expectedTotalInterest, expectedBorrowerInterest, "pool interest should be net of morpho loss");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedTotalInterest, 10, "epoch interest mismatch");
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestDebt(),
      expectedBorrowerInterest,
      5,
      "contractual borrower debt should not be reduced by morpho loss"
    );
  }

  function testProgrammableBorrowerClosePoolRealizesInterestWithRealVault() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    uint256 expectedInterest = programmableBorrower.totalInterestDueNow();
    assertGt(expectedInterest, 0, "expected morpho interest before close");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 1);

    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedInterest, 10, "close pool interest mismatch");
    assertEq(cdoEpoch.defaulted(), false, "pool should not default");
    assertEq(cdoEpoch.epochEndDate(), 0, "epoch should be closed");
    assertEq(cdoEpoch.disableInstantWithdraw(), true, "instant withdraw should be disabled after close");
    assertEq(cdoEpoch.allowInstantWithdraw(), true, "withdraw claims should be allowed after close");
  }

  function testProgrammableBorrowerRepayClearsFrontedDebtAndRedeploysCashWithRealVault() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 4_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    uint256 frontedDebt = programmableBorrower.borrowerInterestDebt();
    assertGt(frontedDebt, 0, "expected fronted interest debt");

    _startEpochAndCheckPrices(1);

    uint256 morphoAssetsPre = _programmableMorphoAssets();
    uint256 principalPre = programmableBorrower.borrowerPrincipal();

    deal(USDC, revolvingBorrower, frontedDebt, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(frontedDebt);

    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "fronted debt not cleared");
    assertEq(programmableBorrower.borrowerPrincipal(), principalPre, "principal should not change");
    assertApproxEqAbs(_programmableMorphoAssets() - morphoAssetsPre, frontedDebt, 5, "repayment not redeployed");
  }

  function testProgrammableBorrowerRepayWhenEpochInactiveKeepsCashOnHand() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 4_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    uint256 frontedDebt = programmableBorrower.borrowerInterestDebt();
    uint256 morphoAssetsPre = _programmableMorphoAssets();
    uint256 onHandPre = underlying.balanceOf(address(programmableBorrower));

    deal(USDC, revolvingBorrower, frontedDebt, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(frontedDebt);

    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "fronted debt not cleared");
    assertApproxEqAbs(
      underlying.balanceOf(address(programmableBorrower)) - onHandPre,
      frontedDebt,
      2,
      "repayment should stay on-hand while epoch is inactive"
    );
    assertApproxEqAbs(_programmableMorphoAssets(), morphoAssetsPre, 2, "inactive repayment should not redeploy");
  }

  function testProgrammableBorrowerStopEpochSettlesFullBorrowerInterestWithApr0PendingWithdraws() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 2_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    cdoEpoch.requestWithdraw(aaTranche.balanceOf(address(this)) / 2, address(aaTranche));
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    uint256 expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    assertGt(expectedBorrowerInterest, 0, "borrower interest should accrue");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertApproxEqAbs(
      programmableBorrower.borrowerInterestDebt(),
      expectedBorrowerInterest,
      5,
      "apr0 pending withdraws should not reduce settled borrower debt"
    );
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "current borrower interest not cleared");
  }

  function testProgrammableBorrowerStopEpochDefaultsWhenMorphoCannotReturnEnoughLiquidity() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 1_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    // Make the programmable borrower insolvent from IdleCDO's perspective by removing most of the
    // remaining MetaMorpho position before the close-pool recall.
    uint256 sharesToRescue = morphoVault.balanceOf(address(programmableBorrower)) * 9 / 10;
    programmableBorrower.rescueTokens(address(morphoVault), makeAddr("shareSinkDefault"), sharesToRescue);

    uint256 accruedBefore = programmableBorrower.borrowerInterestAccruedNow();
    assertGt(accruedBefore, 0, "expected accrued borrower interest before default");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 1);

    assertEq(cdoEpoch.defaulted(), true, "pool should default");
    assertEq(cdoEpoch.allowInstantWithdraw(), true, "instant withdraw should be allowed after default");
    assertEq(cdoEpoch.isEpochRunning(), false, "epoch should stop on default");
    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "default path should not settle borrower debt");
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestAccruedNow(),
      accruedBefore,
      5,
      "borrower accrued interest should remain un-settled on default"
    );
  }

  function testProgrammableBorrowerRequiresMintedInterest() external {
    idleCDO.depositAA(10_000 * oneScale);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.startEpoch();
  }

  function testProgrammableBorrowerRejectsManualInterestOverride() external {
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(10_000 * oneScale);
    _startEpochAndCheckPrices(0);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 1_000 * oneScale);
  }

  function testSetBorrowerAprCheckpointsAccruedInterest() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 5_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    // Borrower draws funds (APR is 365e18 = ~1% per day)
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    // Advance 15 days and let interest accrue at the initial APR
    vm.warp(block.timestamp + 15 days);

    uint256 interestBefore = programmableBorrower.borrowerInterestAccruedNow();
    assertGt(interestBefore, 0, "should have accrued interest at initial APR");

    // Change APR to double — this should checkpoint first at the old rate
    programmableBorrower.setBorrowerApr(730e18);

    // Verify the checkpoint stored interest at the old rate
    uint256 checkpointed = programmableBorrower.borrowerInterestAccrued();
    assertEq(checkpointed, interestBefore, "interest should be checkpointed at old rate");

    // Advance another 15 days
    vm.warp(block.timestamp + 15 days);

    // Interest for the second period should accrue at the new (doubled) rate
    uint256 interestFinal = programmableBorrower.borrowerInterestAccruedNow();
    uint256 newPeriodInterest = interestFinal - checkpointed;

    // Both periods are 15 days; new APR is 2x old, so new-period interest ≈ 2x first-period
    assertApproxEqRel(newPeriodInterest, interestBefore * 2, 0.01e18, "second period should accrue at double rate");
  }

  function testSetMorphoVaultRejectsWrongAssetVault() external {
    address wethVault = 0x38989BBA00BDF8181F4082995b3DEAe96163aC5D;

    vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
    programmableBorrower.setMorphoVault(wethVault);
  }

  function testTotalInterestDueNowFloorsAtZeroWhenMorphoLossExceedsGains() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    uint256 sharesToRescue = morphoVault.balanceOf(address(programmableBorrower)) * 9 / 10;
    programmableBorrower.rescueTokens(address(morphoVault), makeAddr("shareSinkZeroFloor"), sharesToRescue);

    assertGt(programmableBorrower.morphoLoss(), 0, "expected morpho loss");
    assertEq(programmableBorrower.totalInterestDueNow(), 0, "net interest should floor at zero");
  }

  // ─── Access Control ────────────────────────────────────────────────────

  function testBorrowRevertsForNonBorrower() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    // Non-borrower should revert
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    programmableBorrower.borrow(1_000 * oneScale);
  }

  function testBorrowRevertsWhenEpochInactive() external {
    // No epoch started — borrowing should revert
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(100 * oneScale);
  }

  function testBorrowRevertsOnZeroAmount() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(0);
  }

  function testBorrowRevertsWhenExceedingAvailable() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    // Request half, leaving ~5k available after reservation
    cdoEpoch.requestWithdraw(aaTranche.balanceOf(address(this)) / 2, address(aaTranche));
    _startEpochAndCheckPrices(0);

    uint256 available = programmableBorrower.availableToBorrow();
    // Try to borrow more than available
    vm.expectRevert(abi.encodeWithSelector(InsufficientBorrowable.selector));
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(available + 1);
  }

  function testRepayRevertsForNonBorrower() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    programmableBorrower.repay(100 * oneScale);
  }

  function testRepayRevertsOnZeroAmount() external {
    vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(0);
  }

  function testOnStartEpochRevertsForNonCDO() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    programmableBorrower.onStartEpoch(0);
  }

  function testOnStopEpochRevertsForNonCDO() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    programmableBorrower.onStopEpoch(0);
  }

  function testEmergencyExitMorphoRevertsForNonOwner() external {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(revolvingBorrower);
    programmableBorrower.emergencyExitMorpho(0);
  }

  // ─── emergencyExitMorpho ──────────────────────────────────────────────

  function testEmergencyExitMorphoFullRedeem() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    uint256 morphoSharesBefore = morphoVault.balanceOf(address(programmableBorrower));
    assertGt(morphoSharesBefore, 0, "should have morpho shares");

    // Full redeem (shares=0 means all)
    programmableBorrower.emergencyExitMorpho(0);

    assertEq(morphoVault.balanceOf(address(programmableBorrower)), 0, "all shares should be redeemed");
    assertApproxEqAbs(
      underlying.balanceOf(address(programmableBorrower)),
      amount,
      2,
      "underlying should be on contract"
    );
  }

  function testEmergencyExitMorphoPartialRedeem() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    uint256 totalShares = morphoVault.balanceOf(address(programmableBorrower));
    uint256 halfShares = totalShares / 2;

    // Partial redeem
    programmableBorrower.emergencyExitMorpho(halfShares);

    assertApproxEqAbs(
      morphoVault.balanceOf(address(programmableBorrower)),
      totalShares - halfShares,
      1,
      "half shares should remain"
    );
  }

  // ─── Repay Waterfall ──────────────────────────────────────────────────

  function testRepayWaterfallClearsInterestThenPrincipal() external {
    // Setup: deposit, borrow, accrue interest, stop epoch (fronts borrower interest)
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 5_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    uint256 frontedDebt = programmableBorrower.borrowerInterestDebt();
    assertGt(frontedDebt, 0, "should have fronted debt");

    // Start new epoch so repaid funds go to Morpho
    _startEpochAndCheckPrices(1);

    // Borrow again to accrue more interest
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(3_000 * oneScale);
    vm.warp(block.timestamp + 10 days);

    uint256 accruedInterest = programmableBorrower.borrowerInterestAccruedNow();
    uint256 principal = programmableBorrower.borrowerPrincipal();
    assertGt(accruedInterest, 0, "should have accrued interest");

    // Repay everything: should clear fronted debt, then accrued, then principal
    uint256 totalOwed = frontedDebt + accruedInterest + principal;
    deal(USDC, revolvingBorrower, totalOwed, true);

    vm.prank(revolvingBorrower);
    (uint256 interestPaid, uint256 principalPaid) = programmableBorrower.repay(totalOwed);

    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "fronted debt not cleared");
    assertEq(programmableBorrower.borrowerInterestAccrued(), 0, "accrued interest not cleared");
    assertEq(programmableBorrower.borrowerPrincipal(), 0, "principal not cleared");
    assertApproxEqAbs(
      interestPaid,
      frontedDebt + accruedInterest,
      5,
      "interest paid should be total interest"
    );
    assertApproxEqAbs(principalPaid, principal, 5, "principal paid should match drawn");
  }

  function testRepayPartialCoversOnlyFrontedDebt() external {
    // Setup: create fronted debt via stop epoch
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(5_000 * oneScale);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    uint256 frontedDebt = programmableBorrower.borrowerInterestDebt();
    uint256 principal = programmableBorrower.borrowerPrincipal();

    // Repay only half the fronted debt
    uint256 partialRepay = frontedDebt / 2;
    deal(USDC, revolvingBorrower, partialRepay, true);

    _startEpochAndCheckPrices(1);

    vm.prank(revolvingBorrower);
    (uint256 interestPaid, uint256 principalPaid) = programmableBorrower.repay(partialRepay);

    assertEq(interestPaid, partialRepay, "all repayment should go to interest");
    assertEq(principalPaid, 0, "no principal should be repaid");
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestDebt(),
      frontedDebt - partialRepay,
      1,
      "remaining fronted debt incorrect"
    );
    assertEq(programmableBorrower.borrowerPrincipal(), principal, "principal should be unchanged");
  }

  // ─── depositDuringEpoch blocked ───────────────────────────────────────

  function testDepositDuringEpochBlockedForProgrammableBorrower() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    // Attempt mid-epoch deposit — should revert because PB is active
    deal(USDC, address(this), 1_000 * oneScale, true);
    underlying.approve(address(cdoEpoch), 1_000 * oneScale);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.depositDuringEpoch(1_000 * oneScale, address(aaTranche));
  }

  // ─── Multi-epoch cycle ────────────────────────────────────────────────

  function testMultiEpochBorrowRepayCarryForward() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 4_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    // Epoch 0: borrow
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    uint256 priceAfterEpoch0 = cdoEpoch.virtualPrice(address(aaTranche));
    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);
    uint256 priceAfterStop0 = cdoEpoch.virtualPrice(address(aaTranche));
    assertGt(priceAfterStop0, priceAfterEpoch0, "price should increase after epoch 0 stop");

    uint256 debt0 = programmableBorrower.borrowerInterestDebt();
    assertGt(debt0, 0, "should have debt from epoch 0");

    // Epoch 1: repay previous debt, borrow again
    _startEpochAndCheckPrices(1);

    deal(USDC, revolvingBorrower, debt0 + drawAmount, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(debt0);
    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "debt should be cleared after repay");

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);
    uint256 priceAfterStop1 = cdoEpoch.virtualPrice(address(aaTranche));
    assertGt(priceAfterStop1, priceAfterStop0, "price should increase after epoch 1 stop");

    uint256 debt1 = programmableBorrower.borrowerInterestDebt();
    assertGt(debt1, 0, "should have new debt from epoch 1");
  }

  function _startEpochAndCheckPrices(uint256 _epochNum) internal {
    if (cdoEpoch.epochEndDate() != 0) {
      vm.warp(block.timestamp + cdoEpoch.bufferPeriod() + 1);
    }

    uint256 aaPricePre = cdoEpoch.virtualPrice(address(aaTranche));
    uint256 bbPricePre = cdoEpoch.virtualPrice(address(bbTranche));

    vm.prank(manager);
    cdoEpoch.startEpoch();

    assertApproxEqAbs(
      cdoEpoch.virtualPrice(address(aaTranche)),
      aaPricePre,
      1,
      string(abi.encodePacked("AA price changed on start: ", _epochNum))
    );
    assertApproxEqAbs(
      cdoEpoch.virtualPrice(address(bbTranche)),
      bbPricePre,
      1,
      string(abi.encodePacked("BB price changed on start: ", _epochNum))
    );
  }

  function _accrueMorphoVaultInterest() internal {
    IMorpho blue = IMorpho(MORPHO_BLUE);
    for (uint256 i = 0; i < morphoVault.withdrawQueueLength(); i++) {
      blue.accrueInterest(blue.idToMarketParams(morphoVault.withdrawQueue(i)));
    }
  }

  function _programmableMorphoAssets() internal view returns (uint256) {
    return morphoVault.convertToAssets(morphoVault.balanceOf(address(programmableBorrower)));
  }
}
