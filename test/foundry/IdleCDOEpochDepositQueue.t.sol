pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IdleCDOEpochDepositQueue} from "../../contracts/IdleCDOEpochDepositQueue.sol";
import {IKeyring} from "../../contracts/interfaces/keyring/IKeyring.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error NotAllowed();
error EpochNotRunning();

contract TestIdleCDOEpochDepositQueue is Test {
  using stdStorage for StdStorage;

  uint256 public constant ONE_TRANCHE = 1e18;
  IdleCDOEpochVariant public constant cdoEpoch = IdleCDOEpochVariant(0xf6223C567F21E33e859ED7A045773526E9E3c2D5);
  IdleCDOEpochDepositQueue public queue;
  IERC20Detailed public underlying;
  IERC20Detailed public tranche;
  IdleCreditVault public strategy;
  address public manager;


  function setUp() public {
    vm.createSelectFork('mainnet', 20933865);

    queue = new IdleCDOEpochDepositQueue();
    stdstore.target(address(queue)).sig(queue.idleCDOEpoch.selector).checked_write(address(0));
    queue.initialize(address(cdoEpoch), address(this), true);
    underlying = IERC20Detailed(cdoEpoch.token());
    strategy = IdleCreditVault(cdoEpoch.strategy());
    manager = strategy.manager();
    tranche = IERC20Detailed(cdoEpoch.AATranche());

    // approve queue contract to spend underlying of address(this)
    underlying.approve(address(queue), type(uint256).max);

    // allow everyone to deposit
    vm.prank(cdoEpoch.owner());
    cdoEpoch.setKeyringParams(address(0), 1, false);
  }

  function testInitialize() public view {
    assertEq(queue.idleCDOEpoch(), address(cdoEpoch));
    assertEq(queue.strategy(), cdoEpoch.strategy());
    assertEq(queue.underlying(), cdoEpoch.token());
    assertEq(queue.tranche(), cdoEpoch.AATranche());
    assertEq(queue.owner(), address(this));
  }

  function testCantReinitialize() public {
    vm.expectRevert('Initializable: contract is already initialized');
    queue.initialize(address(cdoEpoch), address(this), true);
  }

  function testOnlyKeyringUsersCanInteract() external {
    address keyring = address(1);

    vm.prank(cdoEpoch.owner());
    cdoEpoch.setKeyringParams(keyring, 1, false);

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    queue.requestDeposit(1e18);
    vm.clearMockedCalls();

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );

    // epoch is already running at specified block
    deal(address(underlying), address(this), 1e18);
    queue.requestDeposit(1e18);

    vm.clearMockedCalls();
  }

  function testCannotQueueIfEpochNotRunning() external {
    _stopCurrentEpoch();
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    queue.requestDeposit(1e18);
  }

  function testRequestDeposit() external {
    // epoch is already running at specified block
    uint256 amount = 1e6; // 1USDC
    deal(address(underlying), address(this), amount);
    queue.requestDeposit(amount);

    assertEq(underlying.balanceOf(address(this)), 0, 'underlying balance is wrong'); 
    assertEq(underlying.balanceOf(address(queue)), amount, 'underlying balance of queue contract is wrong'); 
    assertEq(queue.pendingDeposits(), amount, 'pending deposits is wrong');
    assertEq(queue.userDepositsEpochs(address(this), strategy.epochNumber() + 1), amount, 'user deposits is wrong');

    // do another deposit
    deal(address(underlying), address(this), amount);
    queue.requestDeposit(amount);
    assertEq(queue.userDepositsEpochs(address(this), strategy.epochNumber() + 1), 2 * amount, 'user deposits is wrong after second deposit');
    assertEq(queue.pendingDeposits(), 2 * amount, 'pending deposits is wrong after second deposit');

    // do another deposit with different user
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount);
    assertEq(queue.userDepositsEpochs(user1, strategy.epochNumber() + 1), amount, 'user deposits is wrong after user1 deposit');
    assertEq(queue.pendingDeposits(), 3 * amount, 'pending deposits is wrong after user1 deposit');
  }

  function testProcessDeposits() external {
    uint256 amount = 1e6; // 1USDC

    // request deposit with user1
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount);

    // request deposit with user2
    address user2 = makeAddr('user2');
    _requestDepositWithUser(user2, amount * 9);

    // stopEpoch
    _stopCurrentEpoch();

    uint256 balStrategyPre = underlying.balanceOf(address(strategy));
    // process deposits
    vm.prank(manager);
    queue.processDeposits();

    assertEq(underlying.balanceOf(address(queue)), 0, 'underlying balance of queue contract is wrong');
    assertEq(underlying.balanceOf(address(strategy)) - balStrategyPre, 10 * amount, 'underlying balance of cdoEpoch contract is wrong');
    assertEq(queue.pendingDeposits(), 0, 'pending deposits is wrong');

    uint256 tranchePrice = cdoEpoch.virtualPrice(address(tranche));
    uint256 trancheTokensMinted = amount * 10 * ONE_TRANCHE / tranchePrice;
    assertEq(tranche.balanceOf(address(queue)), trancheTokensMinted, 'tranche balance of user is wrong');
    assertEq(queue.epochPrice(strategy.epochNumber()), tranchePrice, 'epoch price is wrong');
  }

  function testClaimDepositRequest() external {
    // request deposit with user1
    uint256 amount1 = 1e6; // 1USDC
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount1);

    // request deposit with user2
    uint256 amount2 = 9 * 1e6;
    address user2 = makeAddr('user2');
    _requestDepositWithUser(user2, amount2);

    // request deposit with user3
    uint256 amount3 = 10 * 1e6;
    address user3 = makeAddr('user3');
    _requestDepositWithUser(user3, amount3);

    // stopEpoch
    _stopCurrentEpoch();

    // vPrice is == to epochPrice[epochNumber]
    uint256 vPrice = cdoEpoch.virtualPrice(address(tranche));
    uint256 epochNumber = strategy.epochNumber();

    // process deposits
    vm.prank(manager);
    queue.processDeposits();

    // claim deposit request with user0 who had no deposit requests
    address user0 = makeAddr('user0');
    uint256 trancheBal0Pre = tranche.balanceOf(user0);
    vm.prank(user0);
    queue.claimDepositRequest(epochNumber);
    assertEq(tranche.balanceOf(user0) - trancheBal0Pre, 0, 'user0 tranche balance is wrong after claim');

    // claim deposit request with user1 during buffer period
    uint256 trancheBal1Pre = tranche.balanceOf(user1);
    vm.prank(user1);
    queue.claimDepositRequest(epochNumber);
    assertEq(queue.userDepositsEpochs(user1, epochNumber), 0, 'user1 userDepositsEpochs is wrong after claim');
    assertEq(tranche.balanceOf(user1) - trancheBal1Pre, amount1 * ONE_TRANCHE / vPrice, 'user1 tranche balance is wrong after claim');

    // start a new epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // claim deposit request with user2 when epoch is running
    uint256 trancheBal2Pre = tranche.balanceOf(user2);
    vm.prank(user2);
    queue.claimDepositRequest(epochNumber);
    assertEq(queue.userDepositsEpochs(user2, epochNumber), 0, 'user2 userDepositsEpochs is wrong after claim');
    assertEq(tranche.balanceOf(user2) - trancheBal2Pre, amount2 * ONE_TRANCHE / vPrice, 'user2 tranche balance is wrong after claim');

    // request deposit with user4
    address user4 = makeAddr('user4');
    uint256 amount4 = 1e6;
    _requestDepositWithUser(user4, amount4);

    // _stopEpoch
    _stopCurrentEpoch();

    // claim deposit request with user3 when epoch number changed
    uint256 trancheBal3Pre = tranche.balanceOf(user3);
    vm.prank(user3);
    queue.claimDepositRequest(epochNumber);
    assertEq(queue.userDepositsEpochs(user3, epochNumber), 0, 'user3 userDepositsEpochs is wrong after claim');
    assertEq(tranche.balanceOf(user3) - trancheBal3Pre, amount3 * ONE_TRANCHE / vPrice, 'user3 tranche balance is wrong after claim');
  }

  function testDeleteRequest() external {
    uint256 depositEpoch = strategy.epochNumber() + 1;
    // request deposit with user1
    uint256 amount1 = 1e6; // 1USDC
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount1);
    uint256 balUser1 = underlying.balanceOf(user1);

    // request deposit with user2
    uint256 amount2 = 10 * 1e6;
    address user2 = makeAddr('user2');
    _requestDepositWithUser(user2, amount2);

    // trying to delete request while the epoch is running
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    queue.deleteRequest(depositEpoch);

    // stop epoch
    _stopCurrentEpoch();

    // trying to delete a non existent request
    address badUser = makeAddr('badUser');
    uint256 balBadUser = underlying.balanceOf(badUser);
    uint256 pendingDepositsPre = queue.pendingDeposits();
    vm.prank(badUser);
    queue.deleteRequest(depositEpoch);
    assertEq(underlying.balanceOf(badUser) - balBadUser, 0, 'badUser balance is wrong after badUser delete');
    assertEq(queue.pendingDeposits(), pendingDepositsPre, 'pending deposits is wrong after badUser delete');

    // delete request with user1
    vm.prank(user1);
    queue.deleteRequest(depositEpoch);

    assertEq(queue.userDepositsEpochs(user1, depositEpoch), 0, 'user1 userDepositsEpochs is wrong after delete');
    assertEq(queue.pendingDeposits(), amount2, 'pending deposits is wrong after delete');
    assertEq(underlying.balanceOf(user1) - balUser1, amount1, 'user1 balance is wrong after delete');

    // process deposits
    vm.prank(manager);
    queue.processDeposits();

    // user cannot delete request after deposits were processed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user2);
    queue.deleteRequest(depositEpoch);
  }

  function _requestDepositWithUser(address _user, uint256 amount) internal {
    deal(address(underlying), _user, amount);
    vm.startPrank(_user);
    underlying.approve(address(queue), amount);
    queue.requestDeposit(amount);
    vm.stopPrank();
  }

  function _stopCurrentEpoch() internal {
    uint256 interest = 1000 * 1e6; // 1000 USDC
    address borrower = strategy.borrower();

    deal(address(underlying), borrower, interest);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), interest);

    // interest is passed at stopEpoch for this credit vault
    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.prank(cdoEpoch.owner());
    cdoEpoch.stopEpoch(0, interest);

    assertEq(cdoEpoch.defaulted(), false, 'pool should not be defaulted');
  }
}