pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariantPrefunded} from "../../contracts/IdleCDOEpochVariantPrefunded.sol";
import {IdleCDOEpochQueue} from "../../contracts/IdleCDOEpochQueue.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error NotAllowed();
error ContractLimitReached();

contract TestIdleCDOEpochVariantPrefunded is Test {
  using stdStorage for StdStorage;

  uint256 public constant ONE_TRANCHE = 1e18;
  uint256 public constant PREFUNDED_DEPOSIT_WINDOW = 1;
  IdleCDOEpochVariantPrefunded public constant cdoEpoch =
    IdleCDOEpochVariantPrefunded(0xf6223C567F21E33e859ED7A045773526E9E3c2D5);

  IdleCDOEpochQueue public queue;
  IERC20Detailed public underlying;
  IERC20Detailed public tranche;
  IdleCreditVault public strategy;
  address public manager;

  function setUp() public {
    vm.createSelectFork("mainnet", 20933865);

    IdleCDOEpochVariantPrefunded dummy = new IdleCDOEpochVariantPrefunded();
    IdleCreditVault dummyStrategy = new IdleCreditVault();
    vm.etch(address(cdoEpoch), address(dummy).code);
    vm.etch(cdoEpoch.strategy(), address(dummyStrategy).code);

    queue = new IdleCDOEpochQueue();
    stdstore.target(address(queue)).sig(queue.idleCDOEpoch.selector).checked_write(address(0));
    queue.initialize(address(cdoEpoch), address(this), true);

    underlying = IERC20Detailed(cdoEpoch.token());
    strategy = IdleCreditVault(cdoEpoch.strategy());
    manager = strategy.manager();
    tranche = IERC20Detailed(cdoEpoch.AATranche());
    underlying.approve(address(queue), type(uint256).max);

    vm.prank(cdoEpoch.owner());
    cdoEpoch.setKeyringParams(address(0), 1);
  }

  function testContractSize() public view {
    bytes memory runtime = vm.getDeployedCode("out/IdleCDOEpochVariantPrefunded.sol/IdleCDOEpochVariantPrefunded.json");
    console2.log('size', runtime.length);
    assertLt(runtime.length, 24_576, "IdleCDOEpochVariantPrefunded deployed bytecode too large");
  }

  function testSetEpochQueueOnlyOwnerOrManager() external {
    vm.prank(address(1));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setEpochQueue(address(queue));

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    assertEq(cdoEpoch.epochQueue(), address(queue), "epoch queue was not set by manager");
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);
    assertEq(queue.prefundedDepositWindow(), PREFUNDED_DEPOSIT_WINDOW, "deposit window was not set");

    vm.prank(cdoEpoch.owner());
    cdoEpoch.setEpochQueue(address(0));
    assertEq(cdoEpoch.epochQueue(), address(0), "owner could not reset epoch queue");
  }

  /// @notice Prefunded variants reject attempts to enable instant withdrawals.
  function testSetInstantWithdrawParamsCannotEnableInstantWithdraws() external {
    _stopCurrentEpoch();

    uint256 delay = cdoEpoch.instantWithdrawDelay() + 1;
    uint256 aprDelta = cdoEpoch.instantWithdrawAprDelta() + 1;
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setInstantWithdrawParams(delay, aprDelta, false);

    vm.prank(manager);
    cdoEpoch.setInstantWithdrawParams(delay, aprDelta, true);
    assertEq(cdoEpoch.instantWithdrawDelay(), delay, "instant delay was not updated");
    assertEq(cdoEpoch.instantWithdrawAprDelta(), aprDelta, "instant APR delta was not updated");
    assertTrue(cdoEpoch.disableInstantWithdraw(), "instant withdrawals were not disabled");
  }

  /// @notice Legacy storage cannot re-enable the prefunded instant-withdraw request path.
  function testLegacyInstantWithdrawFlagCannotEnableInstantWithdraws() external {
    _stopCurrentEpoch();

    uint256 amount = 1e6;
    deal(address(underlying), address(this), amount);
    underlying.approve(address(cdoEpoch), amount);
    cdoEpoch.depositAA(amount);

    // Simulate a legacy proxy where disableInstantWithdraw (byte 1 of slot 296) was false.
    bytes32 flagsSlot = bytes32(uint256(296));
    uint256 flags = uint256(vm.load(address(cdoEpoch), flagsSlot));
    flags = flags & ~(uint256(0xff) << 8);
    vm.store(address(cdoEpoch), flagsSlot, bytes32(flags));
    assertFalse(cdoEpoch.disableInstantWithdraw(), "legacy instant flag was not cleared");

    uint256 currentApr = strategy.unscaledApr();
    uint256 triggeringApr = currentApr + cdoEpoch.instantWithdrawAprDelta() + 1;
    stdstore.target(address(cdoEpoch)).sig(cdoEpoch.lastEpochApr.selector).checked_write(triggeringApr);

    uint256 pendingNormalPre = strategy.pendingWithdraws();
    uint256 pendingInstantPre = strategy.pendingInstantWithdraws();
    cdoEpoch.requestWithdraw(0, address(tranche));

    assertGt(strategy.pendingWithdraws(), pendingNormalPre, "request did not use normal withdrawal mode");
    assertEq(strategy.pendingInstantWithdraws(), pendingInstantPre, "legacy flag enabled instant withdrawal mode");
  }

  function testStopEpochProcessesPrefundedQueueAtomically() external {
    uint256 amount1 = 3e6;
    address user1 = makeAddr("user1");

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);

    _requestDepositWithUser(user1, amount1);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.prank(manager);
    queue.processDepositsToBorrower();

    _stopCurrentEpochPrefunded();

    assertEq(queue.epochPendingDeposits(requestEpoch), 0, "pending deposits not reset");
    assertEq(queue.epochPrefundedDeposits(requestEpoch), 0, "prefunded deposits not reset");
    uint256 epochPrice = queue.epochPrice(requestEpoch);
    assertTrue(epochPrice != 0, "epoch price not set");
    assertEq(
      tranche.balanceOf(address(queue)),
      amount1 * ONE_TRANCHE / epochPrice,
      "queue tranche balance is wrong"
    );

    uint256 user1BalPre = tranche.balanceOf(user1);
    vm.prank(user1);
    queue.claimDepositRequest(requestEpoch);
    assertEq(
      tranche.balanceOf(user1) - user1BalPre,
      amount1 * ONE_TRANCHE / epochPrice,
      "user1 claim amount is wrong"
    );
  }

  /// @notice Closing through the duration selector recalls principal already prefunded to the borrower.
  function testCloseWithDurationRecallsPrefundedPrincipal() external {
    uint256 amount = 3e6;
    address user = makeAddr("close-user");

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);

    _requestDepositWithUser(user, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;
    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.prank(manager);
    queue.processDepositsToBorrower();

    uint256 prefunded = queue.epochPrefundedDeposits(requestEpoch);
    uint256 principal = strategy.balanceOf(address(cdoEpoch));
    uint256 interest = cdoEpoch.expectedEpochInterest();
    uint256 pendingWithdraw = strategy.pendingWithdraws();
    uint256 toRepay = principal + prefunded + interest + pendingWithdraw;
    address borrower = strategy.borrower();
    deal(address(underlying), borrower, toRepay);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), toRepay);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 duration = cdoEpoch.epochDuration();
    vm.prank(manager);
    cdoEpoch.stopEpochWithDuration(0, 1, duration, 0);

    assertFalse(cdoEpoch.defaulted(), "close unexpectedly defaulted");
    assertEq(cdoEpoch.epochDuration(), 0, "pool was not closed");
    assertEq(underlying.balanceOf(borrower), 0, "prefunded principal was not recalled");
    assertEq(queue.epochPrefundedDeposits(requestEpoch), 0, "prefunded deposits were not settled");
    assertGt(queue.epochPrice(requestEpoch), 0, "prefunded epoch price was not set");
  }

  function testStopEpochRevertsWhenQueueConfigured() external {
    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));

    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.stopEpoch(0, 0);
  }

  function testDepositDuringEpochNotSupported() external {
    deal(address(underlying), address(this), 1e6);
    underlying.approve(address(cdoEpoch), 1e6);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.depositDuringEpoch(1e6, address(tranche));
  }

  function testStopEpochWithoutQueueConfigurationDoesNotProcessDeposits() external {
    uint256 amount = 1e6;
    address user1 = makeAddr("user1");

    _requestDepositWithUser(user1, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    _stopCurrentEpoch();

    assertEq(queue.epochPendingDeposits(requestEpoch), amount, "deposits should remain pending");
    assertEq(queue.epochPrice(requestEpoch), 0, "epoch price should not be set");
  }

  /// @notice Queue-held deposits remain cancellable when AA can no longer mint shares.
  function testZeroAAPriceCannotBecomeNonCancellablePrefund() external {
    uint256 amount = 1e6;
    address user = makeAddr("zero-aa-user");

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);

    _requestDepositWithUser(user, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    stdstore.target(address(cdoEpoch)).sig(cdoEpoch.lastNAVAA.selector).checked_write(uint256(0));
    stdstore.target(address(cdoEpoch)).sig(cdoEpoch.priceAA.selector).checked_write(uint256(0));
    assertEq(cdoEpoch.virtualPrice(address(tranche)), 0, "test setup did not wipe AA");

    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    queue.processDepositsToBorrower();

    uint256 balancePre = underlying.balanceOf(user);
    vm.prank(user);
    queue.deleteRequest(requestEpoch);
    assertEq(underlying.balanceOf(user) - balancePre, amount, "queue-held request was not cancellable");
    assertEq(queue.epochPrefundedDeposits(requestEpoch), 0, "zero-price request became prefunded");
  }

  /// @notice Emergency shutdown cannot send queue-held deposits to the borrower.
  function testEmergencyShutdownCannotPrefundQueuedDeposits() external {
    uint256 amount = 1e6;
    address user = makeAddr("emergency-prefund-user");

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);
    _requestDepositWithUser(user, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    vm.prank(cdoEpoch.owner());
    cdoEpoch.emergencyShutdown();
    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    queue.processDepositsToBorrower();

    uint256 balancePre = underlying.balanceOf(user);
    vm.prank(user);
    queue.deleteRequest(requestEpoch);
    assertEq(underlying.balanceOf(user) - balancePre, amount, "emergency request was not cancellable");
    assertEq(queue.epochPrefundedDeposits(requestEpoch), 0, "emergency request reached the borrower");
  }

  /// @notice Prefunded queue deposits respect the same guarded-launch TVL limit as direct deposits.
  function testPrefundedRequestRespectsContractLimit() external {
    uint256 amount = 1e6;
    address user = makeAddr("limited-prefund-user");

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);
    uint256 limitedValue = cdoEpoch.getContractValue() + amount - 1;
    vm.prank(cdoEpoch.owner());
    cdoEpoch._setLimit(limitedValue);

    deal(address(underlying), user, amount);
    vm.startPrank(user);
    underlying.approve(address(queue), amount);
    vm.expectRevert(abi.encodeWithSelector(ContractLimitReached.selector));
    queue.requestDeposit(amount);
    vm.stopPrank();

    assertEq(underlying.balanceOf(user), amount, "rejected deposit left the user");
  }

  /// @notice borrower default still settles prefunded deposits because funds already reached the borrower
  function testStopEpochWithDefaultStillProcessesPrefundedQueue() external {
    uint256 amount = 1e6;
    uint256 interest = 1000 * 1e6;
    address user1 = makeAddr("user1");

    vm.prank(manager);
    cdoEpoch.setEpochQueue(address(queue));
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);

    _requestDepositWithUser(user1, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.prank(manager);
    queue.processDepositsToBorrower();

    uint256 pendingWithdraw = strategy.pendingWithdraws();
    address borrower = strategy.borrower();
    uint256 insufficientRepayment = interest + pendingWithdraw - 1;

    // Force borrower default by repaying less than the amount required at epoch stop.
    deal(address(underlying), borrower, insufficientRepayment);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), insufficientRepayment);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 duration = cdoEpoch.epochDuration();
    vm.prank(manager);
    cdoEpoch.stopEpochWithDuration(0, interest, duration, 0);

    assertEq(cdoEpoch.defaulted(), true, "pool should default");
    assertEq(queue.epochPendingDeposits(requestEpoch), 0, "pending deposits should stay moved out of the queue");
    assertEq(queue.epochPrefundedDeposits(requestEpoch), 0, "prefunded deposits should be settled");

    uint256 epochPrice = queue.epochPrice(requestEpoch);
    assertTrue(epochPrice != 0, "epoch price should be set on default");
    assertEq(
      tranche.balanceOf(address(queue)),
      amount * ONE_TRANCHE / epochPrice,
      "queue should receive tranche tokens on default"
    );

    uint256 user1BalPre = tranche.balanceOf(user1);
    vm.prank(user1);
    queue.claimDepositRequest(requestEpoch);
    assertEq(
      tranche.balanceOf(user1) - user1BalPre,
      amount * ONE_TRANCHE / epochPrice,
      "user1 claim amount is wrong on default"
    );
  }

  /// @notice A successful explicit loss is realized before next-epoch prefunded AA enters.
  function testPrefundedDepositEntersAfterSuccessfulPartialLoss() external {
    uint256 amount = 3e6;
    uint256 interest = 1000 * 1e6;
    address user = makeAddr("partial-loss-prefund-user");

    vm.startPrank(cdoEpoch.owner());
    cdoEpoch.setEpochQueue(address(queue));
    cdoEpoch.setFeeParams(cdoEpoch.feeReceiver(), 0, 100_000, 0);
    vm.stopPrank();
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);
    _requestDepositWithUser(user, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.prank(manager);
    queue.processDepositsToBorrower();

    assertEq(strategy.pendingWithdraws(), 0, "test requires no pending receipts");
    assertEq(cdoEpoch.pendingWithdrawFees(), 0, "test requires no pending withdrawal fees");
    uint256 strategyBalancePre = strategy.balanceOf(address(cdoEpoch));
    uint256 activeBasis = cdoEpoch.getContractValue() + interest;
    uint256 lossAmount = activeBasis / 10;
    assertGt(lossAmount, interest, "test loss must exceed interest");

    address borrower = strategy.borrower();
    deal(address(underlying), borrower, interest);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), interest);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 duration = cdoEpoch.epochDuration();
    vm.prank(manager);
    cdoEpoch.stopEpochWithDuration(0, interest, duration, lossAmount);

    assertFalse(cdoEpoch.defaulted(), "partial loss unexpectedly defaulted");
    assertEq(
      strategy.balanceOf(address(cdoEpoch)),
      strategyBalancePre + interest - lossAmount + amount,
      "prefunded principal was included in the preceding loss"
    );

    uint256 queueShares = tranche.balanceOf(address(queue));
    uint256 prefundedValue = queueShares * cdoEpoch.virtualPrice(address(tranche)) / ONE_TRANCHE;
    assertApproxEqAbs(prefundedValue, amount, 2, "prefunded deposit did not enter at full post-loss value");

    vm.prank(user);
    queue.claimDepositRequest(requestEpoch);
    assertEq(tranche.balanceOf(user), queueShares, "user did not receive the post-loss prefunded shares");
  }

  /// @notice Prefunded principal and aggregate active interest share the hard-default recovery ratio.
  function testPrefundedDepositJoinsHardDefaultRecoveryAndActiveInterest() external {
    uint256 amount = 3e6;
    uint256 interest = 1000 * 1e6;
    address user = makeAddr("default-recovery-prefund-user");

    vm.startPrank(cdoEpoch.owner());
    cdoEpoch.setEpochQueue(address(queue));
    cdoEpoch.setFeeParams(cdoEpoch.feeReceiver(), 0, 100_000, 0);
    vm.stopPrank();
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);
    _requestDepositWithUser(user, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.prank(manager);
    queue.processDepositsToBorrower();

    assertEq(strategy.pendingWithdraws(), 0, "test requires no pending receipts");
    assertEq(cdoEpoch.pendingWithdrawFees(), 0, "test requires no pending withdrawal fees");
    uint256 strategyBalancePre = strategy.balanceOf(address(cdoEpoch));
    address borrower = strategy.borrower();
    deal(address(underlying), borrower, interest - 1);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), interest - 1);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 duration = cdoEpoch.epochDuration();
    vm.prank(manager);
    cdoEpoch.stopEpochWithDuration(0, interest, duration, 0);

    assertTrue(cdoEpoch.defaulted(), "pool should hard default");
    uint256 strategyBalanceAfterDefault = strategy.balanceOf(address(cdoEpoch));
    assertEq(
      strategyBalanceAfterDefault,
      strategyBalancePre + amount,
      "prefunded principal did not join active strategy-token basis"
    );

    uint256 activeBasis = strategyBalanceAfterDefault + interest;
    uint256 recovered = activeBasis / 2;
    deal(address(underlying), manager, recovered);
    vm.startPrank(manager);
    underlying.approve(address(strategy), recovered);
    cdoEpoch.finalizeDefault(recovered, manager);
    vm.stopPrank();

    uint256 recoveryPrice = strategy.defaultRecoveryPrice();
    assertEq(recoveryPrice, recovered * ONE_TRANCHE / activeBasis, "prefunded principal missing from recovery ratio");

    uint256 queueShares = tranche.balanceOf(address(queue));
    uint256 recoveredPrefundedValue = queueShares * cdoEpoch.virtualPrice(address(tranche)) / ONE_TRANCHE;
    uint256 principalOnlyRecovery = amount * recoveryPrice / ONE_TRANCHE;
    assertGt(
      recoveredPrefundedValue,
      principalOnlyRecovery,
      "prefunded shares did not receive their pro-rata active-interest allocation"
    );

    _claimPrefundedRecovery(user, requestEpoch, recoveredPrefundedValue);
  }

  /// @notice A prefunded stop rejects an exact active wipe explicitly instead of dividing by zero.
  function testPrefundedExactActiveWipeRevertsAtomically() external {
    uint256 amount = 1e6;
    address user = makeAddr("wipe-user");

    vm.startPrank(cdoEpoch.owner());
    cdoEpoch.setEpochQueue(address(queue));
    cdoEpoch.setFeeParams(cdoEpoch.feeReceiver(), 0, 100_000, 0);
    vm.stopPrank();
    vm.prank(manager);
    queue.setPrefundedDepositWindow(PREFUNDED_DEPOSIT_WINDOW);

    _requestDepositWithUser(user, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;
    _enterPrefundedWindow(PREFUNDED_DEPOSIT_WINDOW);
    vm.prank(manager);
    queue.processDepositsToBorrower();

    uint256 interest = 1000 * 1e6;
    uint256 pendingWithdraw = strategy.pendingWithdraws();
    address borrower = strategy.borrower();
    uint256 toRepay = interest + pendingWithdraw;
    deal(address(underlying), borrower, toRepay);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), toRepay);

    uint256 activeLoss = cdoEpoch.getContractValue() + interest;
    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 duration = cdoEpoch.epochDuration();
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.stopEpochWithDuration(0, interest, duration, activeLoss);

    assertTrue(cdoEpoch.isEpochRunning(), "rejected wipe should leave the epoch running");
    assertEq(
      queue.epochPrefundedDeposits(requestEpoch),
      amount,
      "rejected wipe should leave prefunded accounting unchanged"
    );
  }

  function _requestDepositWithUser(address _user, uint256 _amount) internal {
    deal(address(underlying), _user, _amount);
    vm.startPrank(_user);
    underlying.approve(address(queue), _amount);
    queue.requestDeposit(_amount);
    vm.stopPrank();
  }

  /// @notice Claim prefunded shares and redeem their finalized default-recovery value.
  /// @param _user prefunded depositor
  /// @param _requestEpoch queue request epoch
  /// @param _expectedValue expected recovered underlying value
  function _claimPrefundedRecovery(address _user, uint256 _requestEpoch, uint256 _expectedValue) internal {
    vm.prank(_user);
    queue.claimDepositRequest(_requestEpoch);
    uint256 balancePre = underlying.balanceOf(_user);
    vm.startPrank(_user);
    uint256 requested = cdoEpoch.requestWithdraw(0, address(tranche));
    cdoEpoch.claimWithdrawRequest();
    vm.stopPrank();
    assertApproxEqAbs(requested, _expectedValue, 2, "post-default request value is wrong");
    assertApproxEqAbs(
      underlying.balanceOf(_user) - balancePre,
      _expectedValue,
      2,
      "prefunded recovery claim is wrong"
    );
  }

  function _stopCurrentEpoch() internal {
    uint256 interest = 1000 * 1e6;
    uint256 pendingWithdraw = strategy.pendingWithdraws();
    address borrower = strategy.borrower();
    uint256 toRepay = interest + pendingWithdraw;

    deal(address(underlying), borrower, toRepay);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), toRepay);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.prank(cdoEpoch.owner());
    cdoEpoch.stopEpoch(0, interest);
  }

  function _stopCurrentEpochPrefunded() internal {
    uint256 interest = 1000 * 1e6;
    uint256 pendingWithdraw = strategy.pendingWithdraws();
    address borrower = strategy.borrower();
    uint256 toRepay = interest + pendingWithdraw;

    deal(address(underlying), borrower, toRepay);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), toRepay);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    uint256 duration = cdoEpoch.epochDuration();
    vm.prank(manager);
    cdoEpoch.stopEpochWithDuration(0, interest, duration, 0);
  }

  function _enterPrefundedWindow(uint256 _window) internal {
    uint256 target = cdoEpoch.epochEndDate() - _window + 1;
    if (block.timestamp < target) {
      vm.warp(target);
    }
  }
}
