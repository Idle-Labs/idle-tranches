pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IdleCDOEpochQueue} from "../../contracts/IdleCDOEpochQueue.sol";
import {IKeyring} from "../../contracts/interfaces/keyring/IKeyring.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error NotAllowed();
error EpochNotRunning();
error Is0();

contract TestIdleCDOEpochQueue is Test {
  using stdStorage for StdStorage;

  uint256 public constant ONE_TRANCHE = 1e18;
  uint256 public constant ONE_TOKEN = 1e6; // vault uses USDC with 6 decimals
  IdleCDOEpochVariant public constant cdoEpoch = IdleCDOEpochVariant(0xf6223C567F21E33e859ED7A045773526E9E3c2D5);
  IdleCDOEpochQueue public queue;
  IERC20Detailed public underlying;
  IERC20Detailed public tranche;
  IdleCreditVault public strategy;
  address public manager;
  // LP address
  address public constant FASA = 0x7545CdbccD780DabAd6AdA8279D82E5ccfd4bF88;

  function setUp() public {
    vm.createSelectFork('mainnet', 20933865);

    // we deploy a new IdleCDOEpochVariant and IdleCreditVault contract used only to get the bytecode 
    // and etch at the same address of the original one so to enable console.log in the IdleCDOEpochVariant 
    // and new features not yet deployed on mainnet
    IdleCDOEpochVariant dummy = new IdleCDOEpochVariant();
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

    // approve queue contract to spend underlying of address(this)
    underlying.approve(address(queue), type(uint256).max);

    // allow everyone to deposit
    vm.prank(cdoEpoch.owner());
    cdoEpoch.setKeyringParams(address(0), 1, false);

    vm.prank(FASA);
    tranche.approve(address(queue), type(uint256).max);

    vm.prank(address(this));
    tranche.approve(address(queue), type(uint256).max);
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
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    queue.requestWithdraw(1e18);
    vm.clearMockedCalls();

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );

    // epoch is already running at specified block
    deal(address(underlying), address(this), 1e18);
    queue.requestDeposit(1e18);
    // trying to request a withdrawal
    vm.prank(FASA);
    queue.requestWithdraw(1e18);

    vm.clearMockedCalls();
  }

  function testCannotQueueIfEpochNotRunning() external {
    _stopCurrentEpoch();
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    queue.requestDeposit(1e18);
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    vm.prank(FASA);
    queue.requestWithdraw(1e18);
  }

  function testRequestDeposit() external {
    // epoch is already running at specified block
    uint256 amount = 1e6; // 1USDC
    deal(address(underlying), address(this), amount);
    queue.requestDeposit(amount);

    assertEq(underlying.balanceOf(address(this)), 0, 'underlying balance is wrong'); 
    assertEq(underlying.balanceOf(address(queue)), amount, 'underlying balance of queue contract is wrong'); 
    assertEq(queue.epochPendingDeposits(1), amount, 'pending deposits is wrong');
    assertEq(queue.userDepositsEpochs(address(this), strategy.epochNumber() + 1), amount, 'user deposits is wrong');

    // do another deposit
    deal(address(underlying), address(this), amount);
    queue.requestDeposit(amount);
    assertEq(queue.userDepositsEpochs(address(this), strategy.epochNumber() + 1), 2 * amount, 'user deposits is wrong after second deposit');
    assertEq(queue.epochPendingDeposits(1), 2 * amount, 'pending deposits is wrong after second deposit');

    // do another deposit with different user
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount);
    assertEq(queue.userDepositsEpochs(user1, strategy.epochNumber() + 1), amount, 'user deposits is wrong after user1 deposit');
    assertEq(queue.epochPendingDeposits(1), 3 * amount, 'pending deposits is wrong after user1 deposit');
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

    // only owner or manager can call processDeposits
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(address(1));
    queue.processDeposits();

    // process deposits
    vm.prank(manager);
    queue.processDeposits();

    assertEq(underlying.balanceOf(address(queue)), 0, 'underlying balance of queue contract is wrong');
    assertEq(underlying.balanceOf(address(strategy)) - balStrategyPre, 10 * amount, 'underlying balance of cdoEpoch contract is wrong');
    assertEq(queue.epochPendingDeposits(1), 0, 'pending deposits is wrong');

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
    vm.prank(queue.owner());
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
    uint256 pendingDepositsPre = queue.epochPendingDeposits(1);
    vm.prank(badUser);
    queue.deleteRequest(depositEpoch);
    assertEq(underlying.balanceOf(badUser) - balBadUser, 0, 'badUser balance is wrong after badUser delete');
    assertEq(queue.epochPendingDeposits(1), pendingDepositsPre, 'pending deposits is wrong after badUser delete');

    // delete request with user1
    vm.prank(user1);
    queue.deleteRequest(depositEpoch);

    assertEq(queue.userDepositsEpochs(user1, depositEpoch), 0, 'user1 userDepositsEpochs is wrong after delete');
    assertEq(queue.epochPendingDeposits(1), amount2, 'pending deposits is wrong after delete');
    assertEq(underlying.balanceOf(user1) - balUser1, amount1, 'user1 balance is wrong after delete');

    // process deposits
    vm.prank(manager);
    queue.processDeposits();

    // user cannot delete request after deposits were processed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user2);
    queue.deleteRequest(depositEpoch);
  }

  function testDeleteRequestForNonProcessedEpoch() public {
    // request deposit with user1
    uint256 depositEpochUser1 = strategy.epochNumber() + 1;
    uint256 amount1 = 1e6; // 1USDC
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount1);
    uint256 balUser1 = underlying.balanceOf(user1);

    _stopCurrentEpoch();
    // epoch 1 buffer

    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request deposit with user2
    uint256 amount2 = 10 * 1e6;
    address user2 = makeAddr('user2');
    _requestDepositWithUser(user2, amount2);

    _stopCurrentEpoch();
    // epoch 2 buffer

    vm.prank(manager);
    queue.processDeposits();

    assertEq(queue.epochPendingDeposits(1), amount1, 'pending deposits for epoch 1 is wrong after processDeposits');
    assertEq(queue.epochPendingDeposits(2), 0, 'pending deposits for epoch 2 is wrong after processDeposits');

    // delete request with user1 for epoch 1
    vm.prank(user1);
    queue.deleteRequest(depositEpochUser1);

    assertEq(underlying.balanceOf(user1), balUser1 + amount1, 'user1 balance is wrong after delete');
  }

  function testClaimRequestForNonProcessedEpoch() public {
    uint256 depositEpoch = strategy.epochNumber() + 1;
    // request deposit with user1
    uint256 amount1 = 1e6; // 1USDC
    address user1 = makeAddr('user1');
    _requestDepositWithUser(user1, amount1);

    // request deposit with user2
    uint256 amount2 = 10 * 1e6;
    address user2 = makeAddr('user2');
    _requestDepositWithUser(user2, amount2);

    _stopCurrentEpoch();
    // epoch 1 buffer

    vm.prank(manager);
    cdoEpoch.startEpoch();

    _stopCurrentEpoch();
    // epoch 2 buffer

    // claim request with user1 for epoch 1 before next process deposit (of epoch 2)
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user1);
    queue.claimDepositRequest(depositEpoch);

    vm.prank(manager);
    queue.processDeposits();

    // claim request with user2 for epoch 1 after process deposit (of epoch 2)
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user2);
    queue.claimDepositRequest(depositEpoch);
  }

  function testRequestWithdraw() external {
    // epoch is already running at specified block
    // so we stop the current epoch #0
    _stopCurrentEpoch();
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // do deposit with address(this)
    _depositWithUser(address(this), 100e6); // 100 USDC

    // try to request a withdraw in the buffer period, the request will revert
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    vm.prank(FASA);
    queue.requestWithdraw(1e18);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request a withdraw with FASA
    uint256 balPre = tranche.balanceOf(FASA);
    uint256 amount = 1e18; // 1 AA tranche token
    vm.prank(FASA);
    queue.requestWithdraw(amount);

    // we transferred tranche tokens in the queue contract
    assertEq(balPre - tranche.balanceOf(FASA), amount, 'tranche balance is wrong'); 
    assertEq(tranche.balanceOf(address(queue)), amount, 'tranche balance of queue contract is wrong'); 
    // withdraw request is queued for epoch #2
    assertEq(queue.epochPendingWithdrawals(2), amount, 'pending withdraw is wrong');
    assertEq(queue.userWithdrawalsEpochs(FASA, strategy.epochNumber() + 1), amount, 'user withdraw is wrong');

    // do another withdraw request with FASA
    vm.prank(FASA);
    queue.requestWithdraw(amount);
    assertEq(queue.epochPendingWithdrawals(2), 2 * amount, 'pending withdraw is wrong after second withdraw');
    assertEq(queue.userWithdrawalsEpochs(FASA, strategy.epochNumber() + 1), 2 * amount, 'user withdraw is wrong after second withdraw');

    // do another withdraw request with address(this)
    queue.requestWithdraw(amount);
    assertEq(queue.userWithdrawalsEpochs(address(this), strategy.epochNumber() + 1), amount, 'user withdraw is wrong after address(this) withdraw');
    assertEq(queue.epochPendingWithdrawals(2), 3 * amount, 'pending withdraw is wrong after address(this) deposit');
  }

  function testProcessWithdrawRequests() external {
    // stop epoch #0
    _stopCurrentEpoch();
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch #1
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, tranches1);
    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch, deposits got some interest
    _stopCurrentEpoch();
    // we are now in epoch #2

    // only owner or manager can call processWithdrawRequests
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(address(1));
    queue.processWithdrawRequests();

    // process withdraw requests, claims will be done in epoch #3
    vm.prank(manager);
    queue.processWithdrawRequests();
    
    // tranche tokens are burned in exchange for strategyTokens
    assertEq(tranche.balanceOf(address(queue)), 0, 'tranche balance of queue contract is wrong');
    uint256 tranchePrice = cdoEpoch.virtualPrice(address(tranche));
    uint256 pendingClaims = (tranches1 + tranches2) * tranchePrice / ONE_TRANCHE;
    // This credit vault has apr set to 0 so on withdraw requests the interest is not accrued during the waiting epoch. Deposits however got some interest at stopEpoch
    assertEq(IERC20Detailed(address(strategy)).balanceOf(address(queue)), pendingClaims, 'strategy token balance of queue contract is wrong');
    assertApproxEqAbs(queue.epochWithdrawPrice(2), tranchePrice, 1, 'pending withdraw is wrong');
    assertEq(queue.epochPendingClaims(2), pendingClaims, 'pending claims is wrong');
    assertEq(queue.epochPendingWithdrawals(2), 0, 'pending withdraw is wrong');
    assertEq(queue.pendingClaims(), true, 'pendingClaims is wrong');

    // try to call process withdraw again but will revert because pendingClaims is true
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    queue.processWithdrawRequests();
  }

  function testProcessWithdrawalClaims() external {
    // stop epoch #0
    _stopCurrentEpoch();
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, tranches1);
    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch, deposits got some interest
    _stopCurrentEpoch();
    // we are now in epoch #2

    uint256 epoch = strategy.epochNumber();

    // process withdraw requests, claims will be available at epoch #3
    vm.prank(manager);
    queue.processWithdrawRequests();
    uint256 expectedUnderlyings = queue.epochPendingClaims(epoch);

    // start epoch #2
    vm.prank(manager);
    cdoEpoch.startEpoch();
    // stopEpoch, deposits got some interest
    _stopCurrentEpoch();
    // we are now in epoch #3

    // only owner or manager can call processWithdrawalClaims
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(address(1));
    queue.processWithdrawalClaims(epoch);

    // claim withdraw requests
    uint256 balPre = underlying.balanceOf(address(queue));
    queue.processWithdrawalClaims(epoch);

    // strategy tokens are burned for underlyings
    assertEq(strategy.balanceOf(address(queue)), 0, 'strategy token balance of queue contract is wrong');
    assertEq(queue.pendingClaims(), false, 'pendingClaims is wrong');
    assertEq(queue.epochPendingClaims(epoch), 0, 'epochPendingClaims is wrong');
    assertEq(underlying.balanceOf(address(queue)) - balPre, expectedUnderlyings, 'underlying balance of queue contract is wrong');
  }

  function testProcessWithdrawalClaimsInstantEpoch() external {
    // stop epoch #0 and set apr for next epoch to 10%
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // enable instant withdrawals
    uint256 instantDelay = 100;
    vm.prank(manager);
    // 100s of delay after ne epoch started to make instant withdrawals, min apr diff 1%
    cdoEpoch.setInstantWithdrawParams(instantDelay, 1e18, false);

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, tranches1);
    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch with a low apr so instant withdraws are triggered
    _stopCurrentEpochWithApr(1e18);
    // we are now in epoch #2 (epoch starts at the beginning of the buffer period)

    uint256 epoch = strategy.epochNumber();

    // process withdraw requests, claims will be available at epoch #4
    vm.prank(manager);
    queue.processWithdrawRequests();

    uint256 tranchePrice = cdoEpoch.virtualPrice(address(tranche));
    uint256 pendingClaims = (tranches1 + tranches2) * tranchePrice / ONE_TRANCHE;
    // epoch number for claim is #2 as instant withdrawal claims will be available in current epoch
    assertEq(queue.epochPendingClaims(2), pendingClaims, 'pending claims is wrong');

    uint256 expectedUnderlyings = queue.epochPendingClaims(epoch);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();
    // wait for the instant withdraw delay
    skip(instantDelay + 1);

    uint256 balPre = underlying.balanceOf(address(queue));
    queue.processWithdrawalClaims(epoch);

    // strategy tokens are burned for underlyings
    assertEq(strategy.balanceOf(address(queue)), 0, 'strategy token balance of queue contract is wrong');
    assertEq(queue.pendingClaims(), false, 'pendingClaims is wrong');
    assertEq(queue.epochPendingClaims(epoch), 0, 'epochPendingClaims is wrong');
    assertEq(underlying.balanceOf(address(queue)) - balPre, expectedUnderlyings, 'underlying balance of queue contract is wrong');
  }

  function testProcessWithdrawalClaimsMixedInstantAndNormalEpoch() external {
    // stop epoch #0 and set apr for next epoch to 10%
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // enable instant withdrawals
    uint256 instantDelay = 100;
    vm.prank(manager);
    // 100s of delay after ne epoch started to make instant withdrawals, min apr diff 1%
    cdoEpoch.setInstantWithdrawParams(instantDelay, 1e18, false);

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with user1
    _requestWithdrawWithUser(user1, tranches1);

    // stopEpoch with same apr so to have normal withdraws
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #2 (epoch starts at the beginning of the buffer period)

    uint256 epoch = strategy.epochNumber();

    // process withdraw requests, claims will be available at epoch #4
    vm.prank(manager);
    queue.processWithdrawRequests();

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();
    // stopEpoch with lower apr so to trigger instant withdraws
    _stopCurrentEpochWithApr(1e18);
    // we are now in epoch #3, normal claims are available

    // user2 calls requestWithdraw directly in the cdoEpoch
    // before processWithdrawalClaims is called
    vm.prank(user2);
    cdoEpoch.requestWithdraw(tranches2, address(tranche));

    uint256 expectedUnderlyings = queue.epochPendingClaims(epoch);
    uint256 balPre = underlying.balanceOf(address(queue));
    // process claims for the previous epoch
    queue.processWithdrawalClaims(epoch);
    assertEq(underlying.balanceOf(address(queue)) - balPre, expectedUnderlyings, 'underlying balance of queue contract is wrong');
  }

  function testProcessWithdrawalClaimsWithProcessRequestsInSameBuffer() external {
    // stop epoch #0 and set apr for next epoch to 10%
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // enable instant withdrawals
    uint256 instantDelay = 100;
    vm.prank(manager);
    // 100s of delay after ne epoch started to make instant withdrawals, min apr diff 1%
    cdoEpoch.setInstantWithdrawParams(instantDelay, 1e18, false);

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with user1
    _requestWithdrawWithUser(user1, tranches1);

    // stopEpoch with same apr so to have normal withdraws
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #2 (epoch starts at the beginning of the buffer period)

    uint256 epoch = strategy.epochNumber();

    // process withdraw requests, claims will be available at epoch #4
    vm.prank(manager);
    queue.processWithdrawRequests();

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with user2
    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch with lower apr so to trigger instant withdraws
    _stopCurrentEpochWithApr(1e18);
    // we are now in epoch #3, normal claims are available

    // process claims for the previous epoch
    queue.processWithdrawalClaims(epoch);
    // epochPendingClaims is set to 0
    assertEq(queue.epochPendingClaims(epoch), 0, 'pending claims is wrong');

    // process withdraw requests for the instant withdraws
    queue.processWithdrawRequests();
    // assertEq(queue.epochPendingClaims(epoch + 1), 0, 'pending claims is wrong');

    // claim with user1
    uint256 expectedUnderlyings = tranches1 * queue.epochWithdrawPrice(epoch) / ONE_TRANCHE;
    uint256 balPre = underlying.balanceOf(address(user1));
    vm.prank(user1);
    queue.claimWithdrawRequest(epoch);
    assertEq(underlying.balanceOf(user1) - balPre, expectedUnderlyings, 'user1 balance is wrong after claim');
  }

  function testProcessWithdrawWhenInstantAreDisabled() external {
    // stop epoch #0 and set apr for next epoch to 10%
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // enable instant withdrawals
    uint256 instantDelay = 100;
    vm.prank(manager);
    // 100s of delay after ne epoch started to make instant withdrawals, min apr diff 1%
    cdoEpoch.setInstantWithdrawParams(instantDelay, 1e18, false);

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with user2
    _requestWithdrawWithUser(user2, tranches2);

    _stopCurrentEpochWithApr(1e18);
    // we are now in epoch #2, instant withdrawals are enabled

    uint256 _epoch = strategy.epochNumber();

    // user1 requests instant withdraw directly in cdoEpoch
    vm.prank(user1);
    cdoEpoch.requestWithdraw(tranches1, address(tranche));

    // instant withdrawals are disabled
    vm.prank(manager);
    cdoEpoch.setInstantWithdrawParams(instantDelay, 10e18, true);

    // process withdraw requests
    queue.processWithdrawRequests();

    // epochPendingClaims should be set for next epoch as now the available withdraws are only the normal ones
    assertGt(queue.epochPendingClaims(_epoch), 0, 'pending claims for epoch + 1 is wrong');
  }

  function testClaimWithdrawRequest() external {
    // stop epoch #0
    _stopCurrentEpoch();
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, tranches1);
    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch, deposits got some interest
    _stopCurrentEpoch();
    // we are now in epoch #2

    uint256 epoch = strategy.epochNumber();
    // check that user cannot claim right away as withdraw requests were not processed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user1);
    queue.claimWithdrawRequest(epoch);

    // process withdraw requests, claims will be available at epoch #3
    vm.prank(manager);
    queue.processWithdrawRequests();

    // start epoch #2
    vm.prank(manager);
    cdoEpoch.startEpoch();
    // stopEpoch, deposits got some interest
    _stopCurrentEpoch();
    // we are now in epoch #3

    // check that user cannot claim right away as claims were not processed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user1);
    // epoch is #2 ie when processWithdrawRequests was called
    queue.claimWithdrawRequest(epoch);

    // claim withdraw requests
    queue.processWithdrawalClaims(epoch);

    // check that user1 can claim right away for epoch #2 withdraw request
    uint256 underlyingsExpected1 = tranches1 * queue.epochWithdrawPrice(epoch) / ONE_TRANCHE;
    uint256 underlyingsExpected2 = tranches2 * queue.epochWithdrawPrice(epoch) / ONE_TRANCHE;
    uint256 bal1Pre = underlying.balanceOf(user1);
    vm.prank(user1);
    queue.claimWithdrawRequest(epoch);
    // check that user1 claimed amount is correct
    assertEq(underlying.balanceOf(user1) - bal1Pre, underlyingsExpected1, 'user1 balance is wrong after claim');
    assertEq(queue.userWithdrawalsEpochs(user1, epoch), 0, 'user1 userWithdrawalsEpochs is wrong after claim');

    // start epoch #3
    vm.prank(manager);
    cdoEpoch.startEpoch();
    _stopCurrentEpoch();

    // check that user2 can claim in the next epoch too for epoch #2 claims
    uint256 bal2Pre = underlying.balanceOf(user2);
    vm.prank(user2);
    queue.claimWithdrawRequest(epoch);
    // check that user2 claimed amount is correct
    assertEq(underlying.balanceOf(user2) - bal2Pre, underlyingsExpected2, 'user2 balance is wrong after claim');
    assertEq(queue.userWithdrawalsEpochs(user2, epoch), 0, 'user2 userWithdrawalsEpochs is wrong after claim');
  }

  function testClaimInstantWithdrawRequest() external {
    // stop epoch #0 and set apr for next epoch to 10%
    _stopCurrentEpochWithApr(10e18);
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // enable instant withdrawals
    uint256 instantDelay = 100;
    vm.prank(manager);
    // 100s of delay after ne epoch started to make instant withdrawals, min apr diff 1%
    cdoEpoch.setInstantWithdrawParams(instantDelay, 1e18, false);

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    // deposit with user2
    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, tranches1);
    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch with a low apr so instant withdraws are triggered
    _stopCurrentEpochWithApr(1e18);
    // we are now in epoch #2 (epoch starts at the beginning of the buffer period)

    uint256 epoch = strategy.epochNumber();

    // process withdraw requests, claims will be available at epoch #4
    vm.prank(manager);
    queue.processWithdrawRequests();

    uint256 tranchePrice = cdoEpoch.virtualPrice(address(tranche));
    uint256 pendingClaims = (tranches1 + tranches2) * tranchePrice / ONE_TRANCHE;
    // epoch number for claim is #2 as instant withdrawal claims will be available in current epoch
    assertEq(queue.epochPendingClaims(2), pendingClaims, 'pending claims is wrong');

    // start epoch
    vm.prank(manager);
    cdoEpoch.startEpoch();
    // wait for the instant withdraw delay
    skip(instantDelay + 1);

    queue.processWithdrawalClaims(epoch);

    // check that user1 can claim right away for epoch #2 withdraw request
    uint256 underlyingsExpected1 = tranches1 * queue.epochWithdrawPrice(epoch) / ONE_TRANCHE;
    uint256 underlyingsExpected2 = tranches2 * queue.epochWithdrawPrice(epoch) / ONE_TRANCHE;
    uint256 bal1Pre = underlying.balanceOf(user1);
    vm.prank(user1);
    queue.claimWithdrawRequest(epoch);
    // check that user1 claimed amount is correct
    assertEq(underlying.balanceOf(user1) - bal1Pre, underlyingsExpected1, 'user1 balance is wrong after claim');
    assertEq(queue.userWithdrawalsEpochs(user1, epoch), 0, 'user1 userWithdrawalsEpochs is wrong after claim');

    _stopCurrentEpoch();

    // start epoch #3
    vm.prank(manager);
    cdoEpoch.startEpoch();
    _stopCurrentEpoch();

    // check that user2 can claim in the next epoch too for epoch #2 claims
    uint256 bal2Pre = underlying.balanceOf(user2);
    vm.prank(user2);
    queue.claimWithdrawRequest(epoch);
    // check that user2 claimed amount is correct
    assertEq(underlying.balanceOf(user2) - bal2Pre, underlyingsExpected2, 'user2 balance is wrong after claim');
    assertEq(queue.userWithdrawalsEpochs(user2, epoch), 0, 'user2 userWithdrawalsEpochs is wrong after claim');
  }

  function testDeleteWithdrawRequest() external {
    _stopCurrentEpoch();

    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // startEpoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, tranches1);
    _requestWithdrawWithUser(user2, tranches2);

    uint256 requestWithdrawEpoch = strategy.epochNumber() + 1;
    // stopEpoch
    _stopCurrentEpoch();

    // trying to delete a non existent request
    address badUser = makeAddr('badUser');
    uint256 balBadUser = tranche.balanceOf(badUser);
    uint256 pendingWithdrawalsPre = queue.epochPendingWithdrawals(2);
    vm.prank(badUser);
    queue.deleteWithdrawRequest(requestWithdrawEpoch);
    assertEq(tranche.balanceOf(badUser) - balBadUser, 0, 'badUser balance is wrong after badUser delete');
    assertEq(queue.epochPendingWithdrawals(2), pendingWithdrawalsPre, 'pending withdrawals is wrong after badUser delete');
    assertEq(queue.userWithdrawalsEpochs(badUser, 2), 0, 'userWithdrawalsEpochs is wrong after badUser delete');

    // delete request with user1
    vm.prank(user1);
    queue.deleteWithdrawRequest(requestWithdrawEpoch);

    assertEq(queue.userDepositsEpochs(user1, requestWithdrawEpoch), 0, 'user1 userWithdrawalsEpochs is wrong after delete');
    assertEq(queue.epochPendingWithdrawals(2), tranches2, 'pending withdrawals is wrong after delete');
    assertEq(tranche.balanceOf(user1), tranches1, 'user1 tranche balance is wrong after delete');

    // process withdrawals
    vm.prank(manager);
    queue.processWithdrawRequests();

    // user cannot delete request after deposits were processed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(user2);
    queue.deleteWithdrawRequest(requestWithdrawEpoch);
  }

  function testDeleteWithdrawRequestForNonProcessedEpoch() public {
    _stopCurrentEpoch();

    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    uint256 tranches1 = _depositWithUser(user1, amount1);

    uint256 amount2 = 100e6; // 100 USDC
    address user2 = makeAddr('user2');
    uint256 tranches2 = _depositWithUser(user2, amount2);

    // startEpoch
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with user1
    _requestWithdrawWithUser(user1, tranches1);

    uint256 requestWithdrawEpoch = strategy.epochNumber() + 1;
    // stopEpoch
    _stopCurrentEpoch();

    // start new epoch without processing withdraws
    vm.prank(manager);
    cdoEpoch.startEpoch();

    _requestWithdrawWithUser(user2, tranches2);

    // stopEpoch
    _stopCurrentEpoch();

    // process withdrawal of user 2
    vm.prank(manager);
    queue.processWithdrawRequests();

    // delete request with user1 for non processed epoch
    uint256 trancheBalPre = tranche.balanceOf(user1);
    vm.prank(user1);
    queue.deleteWithdrawRequest(requestWithdrawEpoch);
    // user1 redeemed tranche tokens eq to the number requested
    assertEq(tranche.balanceOf(user1) - trancheBalPre, tranches1, 'user1 tranche balance is wrong after delete');
  }

  function testProcessWithdrawRequestsWith0Price() external {
    // stop epoch #0
    _stopCurrentEpoch();
    // we are now in epoch #1 (epoch starts at the beginning of the buffer period)

    // deposit with user1
    uint256 amount1 = 1e6; // 1 USDC
    address user1 = makeAddr('user1');
    _depositWithUser(user1, amount1);

    // start epoch #1
    vm.prank(manager);
    cdoEpoch.startEpoch();

    // request withdrawals with both users
    _requestWithdrawWithUser(user1, 100);

    // stopEpoch, deposits got some interest
    _stopCurrentEpoch();
    // we are now in epoch #2

    // can't call process deposits with 0 price
    vm.expectRevert(abi.encodeWithSelector(Is0.selector));
    vm.prank(manager);
    queue.processWithdrawRequests();
  }

  function _requestDepositWithUser(address _user, uint256 amount) internal {
    deal(address(underlying), _user, amount);
    vm.startPrank(_user);
    underlying.approve(address(queue), amount);
    queue.requestDeposit(amount);
    vm.stopPrank();
  }

  function _requestWithdrawWithUser(address _user, uint256 trancheAmount) internal {
    vm.startPrank(_user);
    tranche.approve(address(queue), trancheAmount);
    queue.requestWithdraw(trancheAmount);
    vm.stopPrank();
  }

  function _depositWithUser(address user, uint256 amount) internal returns (uint256 _trancheTokens) {
    // do deposit with user
    deal(address(underlying), user, amount);
    vm.startPrank(user);
    underlying.approve(address(cdoEpoch), amount);
    _trancheTokens = cdoEpoch.depositAA(amount);
    vm.stopPrank();
  }

  function _stopCurrentEpoch() internal {
    _stopCurrentEpochWithApr(0);
  }

  function _stopCurrentEpochWithApr(uint256 _apr) internal {
    uint256 interest = 1000 * 1e6; // 1000 USDC
    uint256 pendingWithdraw = strategy.pendingWithdraws();
    address borrower = strategy.borrower();

    uint256 toRepay = _apr == 0 ? interest + pendingWithdraw : _expectedFundsEndEpoch();

    deal(address(underlying), borrower, toRepay);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), toRepay);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.prank(cdoEpoch.owner());
    if (_apr == 0) {
      cdoEpoch.stopEpoch(0, interest);
    } else {
      cdoEpoch.stopEpoch(_apr, 0);
    }

    assertEq(cdoEpoch.defaulted(), false, 'pool should not be defaulted');
  }

  function _expectedFundsEndEpoch() internal view returns (uint256 expected) {
    expected = cdoEpoch.expectedEpochInterest() + IdleCreditVault(address(strategy)).pendingWithdraws();
  }
}