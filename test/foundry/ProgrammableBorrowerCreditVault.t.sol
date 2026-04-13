// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {IdleCDO} from "../../contracts/IdleCDO.sol";
import {IdleCDOTranche} from "../../contracts/IdleCDOTranche.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626} from "../../contracts/interfaces/IERC4626.sol";
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
  address internal constant GAUNTLET_USDC_PRIME = 0x8c106EEDAd96553e64287A5A6839c3Cc78afA3D0;
  address internal constant MORPHO_AAVE_USDC = 0xA5269A8e31B93Ff27B887B56720A25F844db0529;
  uint256 internal constant FORK_BLOCK = 19225935;
  uint256 internal constant GAUNTLET_FORK_BLOCK = 24850150;
  string internal constant BORROWER_NAME = "testBorrower";

  address internal owner = address(0xdeadbad);
  address internal rebalancer = address(0xbaddead);
  address internal manager = makeAddr("manager");
  address internal borrowerManager = makeAddr("borrowerManager");
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
  IMMVault internal morphoVault;

  function setUp() public {
    _setUpProgrammableBorrowerCreditVault(FORK_BLOCK, STEAKHOUSE_USDC);
  }

  function _setUpProgrammableBorrowerCreditVault(uint256 forkBlock, address vaultAddress) internal {
    vm.createSelectFork("mainnet", forkBlock);

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
    programmableBorrower.initialize(USDC, vaultAddress, address(cdoEpoch), address(this), manager, revolvingBorrower, 365e18);
    morphoVault = IMMVault(vaultAddress);

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

    assertApproxEqAbs(_programmableVaultAssets(), amount, 2, "epoch funds not parked in vault");

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(block.timestamp + 30 days);
    _accrueMorphoVaultInterest();

    uint256 expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    uint256 expectedVaultInterest = programmableBorrower.vaultInterestAccrued();
    uint256 expectedTotalInterest = programmableBorrower.totalInterestDueNow();
    uint256 pricePre = cdoEpoch.virtualPrice(address(aaTranche));

    assertGt(expectedBorrowerInterest, 0, "borrower interest should accrue");
    assertGt(expectedVaultInterest, 0, "vault interest should accrue");

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();
    expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    expectedVaultInterest = programmableBorrower.vaultInterestAccrued();
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

  function testProgrammableBorrowerVaultLossDoesNotReduceSettledBorrowerDebt() external {
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
    uint256 expectedVaultLoss = programmableBorrower.vaultLoss();
    uint256 expectedTotalInterest = programmableBorrower.totalInterestDueNow();

    assertGt(expectedBorrowerInterest, 0, "borrower interest should accrue");
    assertGt(expectedVaultLoss, 0, "vault loss should be recognized");
    assertLt(expectedTotalInterest, expectedBorrowerInterest, "pool interest should be net of vault loss");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedTotalInterest, 10, "epoch interest mismatch");
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestDebt(),
      expectedBorrowerInterest,
      5,
      "contractual borrower debt should not be reduced by vault loss"
    );
  }

  function testProgrammableBorrowerRequestWithdrawNeverCreatesInstantWithdraws() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);

    // Force the generic APR-drop predicate so this test proves programmable mode bypasses the
    // instant-withdraw path explicitly, rather than relying only on the current APR=0 operating mode.
    stdstore.target(address(cdoEpoch)).sig(cdoEpoch.lastEpochApr.selector).checked_write(5e18);

    uint256 requested = cdoEpoch.requestWithdraw(0, address(aaTranche));

    assertEq(strategy.pendingInstantWithdraws(), 0, "programmable mode should not create instant withdraws");
    assertEq(strategy.instantWithdrawsRequests(address(this)), 0, "instant withdraw receipt should stay empty");
    assertEq(strategy.pendingWithdraws(), requested, "request should use the normal withdraw path");
  }

  function testProgrammableBorrowerGetInstantWithdrawFundsIsUnsupported() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();
  }

  function testProgrammableBorrowerStopEpochDoesNotTrustBrokenMaxWithdraw() external {
    _setUpProgrammableBorrowerCreditVault(GAUNTLET_FORK_BLOCK, GAUNTLET_USDC_PRIME);

    IERC4626 gauntletVault = IERC4626(GAUNTLET_USDC_PRIME);
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);

    uint256 withdrawReceipt = cdoEpoch.requestWithdraw(aaTranche.balanceOf(address(this)) / 2, address(aaTranche));
    assertGt(withdrawReceipt, 0, "expected a pending withdraw receipt");

    _startEpochAndCheckPrices(0);

    assertGt(gauntletVault.balanceOf(address(programmableBorrower)), 0, "idle funds not parked in gauntlet vault");
    assertEq(gauntletVault.maxWithdraw(address(programmableBorrower)), 0, "regression prerequisite changed");
    assertGt(strategy.pendingWithdraws(), 0, "stop epoch should need liquidity recall");

    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertFalse(cdoEpoch.defaulted(), "stop epoch should not default just because maxWithdraw is zero");
    assertEq(strategy.pendingWithdraws(), 0, "pending withdraws should be funded");
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

  function testProgrammableBorrowerClosePoolDefaultsWhenPrincipalStillOutstanding() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 4_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(cdoEpoch.epochEndDate() + 1);

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 1);

    assertEq(cdoEpoch.defaulted(), true, "close pool should default with outstanding principal");
    assertEq(cdoEpoch.isEpochRunning(), false, "epoch should stop on default");
    assertFalse(programmableBorrower.epochAccountingActive(), "borrower accounting should stop on default");
    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "default path should not settle borrower debt");
  }

  function testProgrammableBorrowerClosePoolAfterFullRepayRecognizesBorrowerInterest() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 4_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(block.timestamp + 15 days);

    uint256 expectedBorrowerInterest = programmableBorrower.borrowerInterestAccruedNow();
    assertGt(expectedBorrowerInterest, 0, "borrower interest should accrue before repay");

    deal(USDC, revolvingBorrower, underlying.balanceOf(revolvingBorrower) + expectedBorrowerInterest, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(drawAmount + expectedBorrowerInterest);

    assertEq(programmableBorrower.borrowerPrincipal(), 0, "principal should be cleared before close");
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "accrued interest should be cleared before close");

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 expectedTotalInterest = programmableBorrower.totalInterestDueNow();
    assertGe(expectedTotalInterest, expectedBorrowerInterest, "repaid borrower interest should still contribute to close interest");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 1);

    assertEq(cdoEpoch.defaulted(), false, "close pool should succeed after full repay");
    assertEq(cdoEpoch.epochEndDate(), 0, "pool should be closed");
    assertApproxEqAbs(
      cdoEpoch.lastEpochInterest(),
      expectedTotalInterest,
      10,
      "close-pool interest should match programmable borrower accounting after full repay"
    );
  }

  function testProgrammableBorrowerMultipleBorrowRepayCyclesWithinSingleEpoch() external {
    uint256 amount = 10_000 * oneScale;
    uint256 firstDraw = 4_000 * oneScale;
    uint256 secondDraw = 1_000 * oneScale;
    uint256 principalRepaidInEpoch = 1_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(firstDraw);

    vm.warp(block.timestamp + 10 days);
    uint256 firstPeriodInterest = _onePercentPerDayInterest(firstDraw, 10);
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestAccruedNow(),
      firstPeriodInterest,
      2,
      "first borrow leg should accrue 1% per day"
    );

    deal(USDC, revolvingBorrower, firstPeriodInterest + principalRepaidInEpoch, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(firstPeriodInterest + principalRepaidInEpoch);

    assertEq(
      programmableBorrower.borrowerPrincipal(),
      firstDraw - principalRepaidInEpoch,
      "principal should be reduced by the same-epoch repayment"
    );
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "first interest leg should be fully repaid");

    vm.warp(block.timestamp + 5 days);
    uint256 secondPeriodInterest = _onePercentPerDayInterest(firstDraw - principalRepaidInEpoch, 5);
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestAccruedNow(),
      secondPeriodInterest,
      2,
      "interest should continue on the reduced principal"
    );

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(secondDraw);

    vm.warp(block.timestamp + 22 days);
    _accrueMorphoVaultInterest();

    uint256 thirdPeriodInterest = _onePercentPerDayInterest(firstDraw, 22);
    uint256 outstandingBorrowerInterest = secondPeriodInterest + thirdPeriodInterest;
    uint256 totalBorrowerInterestForEpoch = firstPeriodInterest + outstandingBorrowerInterest;
    uint256 manualMorphoGain =
      _programmableVaultAssets() +
      firstDraw +
      secondDraw -
      (amount + principalRepaidInEpoch);
    uint256 expectedTotalInterest = manualMorphoGain + outstandingBorrowerInterest;

    assertApproxEqAbs(
      programmableBorrower.borrowerInterestAccruedNow(),
      outstandingBorrowerInterest,
      2,
      "outstanding borrower interest should match the unrepaid legs"
    );
    assertGe(expectedTotalInterest, totalBorrowerInterestForEpoch, "repaid same-epoch interest should remain visible as epoch profit");
    assertApproxEqAbs(
      programmableBorrower.totalInterestDueNow(),
      expectedTotalInterest,
      20,
      "manual epoch interest should match borrower accounting across same-epoch cycles"
    );

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedTotalInterest, 20, "epoch interest mismatch after same-epoch cycles");
    assertApproxEqAbs(
      programmableBorrower.borrowerInterestDebt(),
      outstandingBorrowerInterest,
      5,
      "only the unpaid borrower interest should be settled into debt"
    );
  }

  function testProgrammableBorrowerBorrowInOneEpochAndRepayInNextEpoch() external {
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

    uint256 debtFromEpoch0 = programmableBorrower.borrowerInterestDebt();
    assertGt(debtFromEpoch0, 0, "first epoch should front borrower interest");
    assertEq(programmableBorrower.borrowerPrincipal(), drawAmount, "principal should carry into the next epoch");

    _startEpochAndCheckPrices(1);
    uint256 bufferedVaultInterestAtStart = programmableBorrower.vaultInterestAccrued();
    uint256 epoch1StartAssets = programmableBorrower.epochStartVaultAssets();

    vm.warp(block.timestamp + 5 days);
    uint256 unfrontedInterestAtRepay = programmableBorrower.borrowerInterestAccruedNow();
    assertGt(unfrontedInterestAtRepay, 0, "carried principal should accrue fresh interest before next-epoch repay");
    uint256 repayAmount = debtFromEpoch0 + unfrontedInterestAtRepay + drawAmount;

    deal(USDC, revolvingBorrower, repayAmount, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(repayAmount);

    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "previous epoch debt should be cleared");
    assertEq(programmableBorrower.borrowerPrincipal(), 0, "principal should be fully repaid");
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "current epoch accrued interest should be cleared");

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    uint256 expectedEpoch1Interest =
      bufferedVaultInterestAtStart +
      _programmableVaultAssets() -
      (epoch1StartAssets + debtFromEpoch0 + drawAmount);
    assertGe(expectedEpoch1Interest, unfrontedInterestAtRepay, "only the newly accrued unfronted interest should remain as new epoch profit");
    assertApproxEqAbs(
      programmableBorrower.totalInterestDueNow(),
      expectedEpoch1Interest,
      20,
      "manual epoch-1 interest should exclude repaid prior-epoch debt"
    );

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedEpoch1Interest, 20, "epoch-1 interest mismatch");
    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "no new borrower debt should be fronted after a full next-epoch repay");
  }

  function testProgrammableBorrowerBufferVaultYieldIsRealizedAtNextStop() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.warp(cdoEpoch.epochEndDate() + 1);

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    uint256 priceAfterEpoch0Stop = cdoEpoch.virtualPrice(address(aaTranche));
    uint256 vaultAssetsAfterEpoch0Stop = _programmableVaultAssets();

    vm.warp(cdoEpoch.epochEndDate() + cdoEpoch.bufferPeriod() + 1);
    _accrueMorphoVaultInterest();

    uint256 bufferVaultYield = _programmableVaultAssets() - vaultAssetsAfterEpoch0Stop;
    assertGt(bufferVaultYield, 0, "expected vault yield during the buffer");

    uint256 aaPricePre = cdoEpoch.virtualPrice(address(aaTranche));
    uint256 bbPricePre = cdoEpoch.virtualPrice(address(bbTranche));

    vm.prank(manager);
    cdoEpoch.startEpoch();

    assertApproxEqAbs(cdoEpoch.virtualPrice(address(aaTranche)), aaPricePre, 1, "AA price changed on start: 1");
    assertApproxEqAbs(cdoEpoch.virtualPrice(address(bbTranche)), bbPricePre, 1, "BB price changed on start: 1");

    assertApproxEqAbs(
      programmableBorrower.vaultInterestAccrued(),
      bufferVaultYield,
      20,
      "buffer vault yield should remain pending after the next epoch starts"
    );

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 expectedEpoch1Interest = programmableBorrower.totalInterestDueNow();
    assertGe(expectedEpoch1Interest, bufferVaultYield, "buffer vault yield should still contribute before the next stop");

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertGe(cdoEpoch.lastEpochInterest(), bufferVaultYield, "buffer vault yield should be realized at next stop");
    assertGt(
      cdoEpoch.virtualPrice(address(aaTranche)),
      priceAfterEpoch0Stop,
      "AA tranche price should increase once the buffered vault yield is realized"
    );
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

    uint256 vaultAssetsPre = _programmableVaultAssets();
    uint256 principalPre = programmableBorrower.borrowerPrincipal();

    deal(USDC, revolvingBorrower, frontedDebt, true);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(frontedDebt);

    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "fronted debt not cleared");
    assertEq(programmableBorrower.borrowerPrincipal(), principalPre, "principal should not change");
    assertApproxEqAbs(_programmableVaultAssets() - vaultAssetsPre, frontedDebt, 5, "repayment not redeployed");
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
    uint256 vaultAssetsPre = _programmableVaultAssets();
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
    assertApproxEqAbs(_programmableVaultAssets(), vaultAssetsPre, 2, "inactive repayment should not redeploy");
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

  function testProgrammableBorrowerStopEpochDefaultsWhenVaultCannotReturnEnoughLiquidity() external {
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
    assertFalse(programmableBorrower.epochAccountingActive(), "borrower accounting should stop on default");
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

  function testSetVaultRejectsWrongAssetVault() external {
    address wethVault = 0x38989BBA00BDF8181F4082995b3DEAe96163aC5D;

    vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
    programmableBorrower.setVault(wethVault);
  }

  function testSetBorrowerRevertsDuringActiveEpoch() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    programmableBorrower.setBorrower(makeAddr("borrowerWhileActive"));
  }

  function testSetBorrowerRevertsWithOutstandingExposureAfterStop() external {
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

    assertGt(programmableBorrower.borrowerPrincipal(), 0, "expected principal to remain outstanding");

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    programmableBorrower.setBorrower(makeAddr("borrowerWithExposure"));
  }

  function testSetVaultRevertsDuringActiveEpoch() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    programmableBorrower.setVault(MORPHO_AAVE_USDC);
  }

  function testSetVaultRevertsWhenCurrentVaultSharesStillExist() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, 0);

    assertGt(morphoVault.balanceOf(address(programmableBorrower)), 0, "expected old vault shares to remain");

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    programmableBorrower.setVault(MORPHO_AAVE_USDC);
  }

  function testSetManagerOnlyOwner() external {
    assertEq(programmableBorrower.manager(), manager, "manager should be initialized");

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(revolvingBorrower);
    programmableBorrower.setManager(borrowerManager);

    programmableBorrower.setManager(borrowerManager);
    assertEq(programmableBorrower.manager(), borrowerManager, "owner should update manager");

    programmableBorrower.setManager(address(0));
    assertEq(programmableBorrower.manager(), address(0), "owner should be able to clear manager");
  }

  function testManagerCanOperateRoutineAdminFunctions() external {
    uint256 amount = 10_000 * oneScale;
    address newBorrower = makeAddr("newBorrower");

    programmableBorrower.setManager(borrowerManager);

    vm.prank(borrowerManager);
    programmableBorrower.setBorrower(newBorrower);
    assertEq(programmableBorrower.borrower(), newBorrower, "manager should update borrower");

    vm.prank(borrowerManager);
    programmableBorrower.setBorrowerApr(730e18);
    assertEq(programmableBorrower.borrowerApr(), 730e18, "manager should update borrower apr");

    vm.prank(borrowerManager);
    programmableBorrower.setVault(STEAKHOUSE_USDC);
    assertEq(address(programmableBorrower.vault()), STEAKHOUSE_USDC, "manager should update vault");

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    uint256 sharesBefore = morphoVault.balanceOf(address(programmableBorrower));
    assertGt(sharesBefore, 0, "expected vault shares before emergency exit");

    vm.prank(borrowerManager);
    programmableBorrower.emergencyExitVault(0);

    assertEq(morphoVault.balanceOf(address(programmableBorrower)), 0, "manager should redeem all shares");
    assertApproxEqAbs(
      underlying.balanceOf(address(programmableBorrower)),
      amount,
      2,
      "redeemed underlying should return to programmable borrower"
    );
  }

  function testTotalInterestDueNowFloorsAtZeroWhenVaultLossExceedsGains() external {
    uint256 amount = 10_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    _accrueMorphoVaultInterest();

    uint256 sharesToRescue = morphoVault.balanceOf(address(programmableBorrower)) * 9 / 10;
    programmableBorrower.rescueTokens(address(morphoVault), makeAddr("shareSinkZeroFloor"), sharesToRescue);

    assertGt(programmableBorrower.vaultLoss(), 0, "expected vault loss");
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

  function testRepayZeroRevertsWhenNothingIsOwed() external {
    vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(0);
  }

  function testRepayZeroRepaysEverythingOwed() external {
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

    uint256 totalOwed = programmableBorrower.borrowerInterestDebt()
      + programmableBorrower.borrowerInterestAccruedNow()
      + programmableBorrower.borrowerPrincipal();
    assertGt(totalOwed, 0, "expected outstanding debt");

    deal(USDC, revolvingBorrower, totalOwed, true);
    vm.prank(revolvingBorrower);
    (uint256 interestPaid, uint256 principalPaid) = programmableBorrower.repay(0);

    assertEq(interestPaid + principalPaid, totalOwed, "repay(0) should clear the full tracked obligation");
    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "fronted debt should be cleared");
    assertEq(programmableBorrower.borrowerPrincipal(), 0, "principal should be cleared");
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "accrued interest should be cleared");
  }

  function testRepayZeroUsesBorrowerInterestOwedNowIncludingUncheckpointedInterest() external {
    uint256 amount = 10_000 * oneScale;
    uint256 drawAmount = 4_000 * oneScale;

    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(drawAmount);

    vm.warp(block.timestamp + 5 days);

    uint256 principalBefore = programmableBorrower.borrowerPrincipal();
    uint256 interestOwedNow = programmableBorrower.borrowerInterestOwedNow();
    uint256 totalOwed = principalBefore + interestOwedNow;
    assertEq(principalBefore, drawAmount, "unexpected outstanding principal");
    assertGt(interestOwedNow, 0, "expected live accrued interest before repay");

    deal(USDC, revolvingBorrower, totalOwed, true);
    vm.prank(revolvingBorrower);
    (uint256 interestPaid, uint256 principalPaid) = programmableBorrower.repay(0);

    assertEq(interestPaid, interestOwedNow, "repay(0) should clear the live borrowerInterestOwedNow amount");
    assertEq(principalPaid, principalBefore, "repay(0) should clear the full outstanding principal");
    assertEq(underlying.balanceOf(revolvingBorrower), 0, "repay(0) should transfer the full currently owed amount");
    assertEq(programmableBorrower.borrowerInterestDebt(), 0, "fronted debt should remain cleared");
    assertEq(programmableBorrower.borrowerPrincipal(), 0, "principal should be fully cleared");
    assertApproxEqAbs(programmableBorrower.borrowerInterestAccruedNow(), 0, 2, "live accrued interest should be cleared");
  }

  function testOnStartEpochRevertsForNonCDO() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    programmableBorrower.onStartEpoch(0);
  }

  function testOnStopEpochRevertsForNonCDO() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    programmableBorrower.onStopEpoch(0);
  }

  function testEmergencyExitVaultRevertsForNonOwnerOrManager() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(revolvingBorrower);
    programmableBorrower.emergencyExitVault(0);
  }

  // ─── emergencyExitVault ───────────────────────────────────────────────

  function testEmergencyExitVaultFullRedeem() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    uint256 morphoSharesBefore = morphoVault.balanceOf(address(programmableBorrower));
    assertGt(morphoSharesBefore, 0, "should have morpho shares");

    // Full redeem (shares=0 means all)
    programmableBorrower.emergencyExitVault(0);

    assertEq(morphoVault.balanceOf(address(programmableBorrower)), 0, "all shares should be redeemed");
    assertApproxEqAbs(
      underlying.balanceOf(address(programmableBorrower)),
      amount,
      2,
      "underlying should be on contract"
    );
  }

  function testEmergencyExitVaultPartialRedeem() external {
    uint256 amount = 10_000 * oneScale;
    vm.prank(owner);
    cdoEpoch.setIsInterestMinted(true);

    idleCDO.depositAA(amount);
    _startEpochAndCheckPrices(0);

    uint256 totalShares = morphoVault.balanceOf(address(programmableBorrower));
    uint256 halfShares = totalShares / 2;

    // Partial redeem
    programmableBorrower.emergencyExitVault(halfShares);

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

  function _programmableVaultAssets() internal view returns (uint256) {
    return morphoVault.convertToAssets(morphoVault.balanceOf(address(programmableBorrower)));
  }

  function _onePercentPerDayInterest(uint256 principal, uint256 elapsedDays) internal pure returns (uint256) {
    return principal * elapsedDays / 100;
  }
}
