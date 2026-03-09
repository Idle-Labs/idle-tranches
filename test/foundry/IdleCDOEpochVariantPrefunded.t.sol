pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariantPrefunded} from "../../contracts/IdleCDOEpochVariantPrefunded.sol";
import {IdleCDOEpochQueue} from "../../contracts/IdleCDOEpochQueue.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error NotAllowed();

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
    cdoEpoch.setKeyringParams(address(0), 1, false);
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

  function testStopEpochWithoutQueueConfigurationDoesNotProcessDeposits() external {
    uint256 amount = 1e6;
    address user1 = makeAddr("user1");

    _requestDepositWithUser(user1, amount);
    uint256 requestEpoch = strategy.epochNumber() + 1;

    _stopCurrentEpoch();

    assertEq(queue.epochPendingDeposits(requestEpoch), amount, "deposits should remain pending");
    assertEq(queue.epochPrice(requestEpoch), 0, "epoch price should not be set");
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

  function _requestDepositWithUser(address _user, uint256 _amount) internal {
    deal(address(underlying), _user, _amount);
    vm.startPrank(_user);
    underlying.approve(address(queue), _amount);
    queue.requestDeposit(_amount);
    vm.stopPrank();
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
