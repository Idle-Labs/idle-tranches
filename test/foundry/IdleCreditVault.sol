// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error EpochRunning();
error EpochNotRunning();
error DeadlineNotMet();
error NotAllowed();
error AmountTooHigh();
error Default();

contract TestIdleCreditVault is TestIdleCDOLossMgmt {
  using stdStorage for StdStorage;

  uint256 internal constant FORK_BLOCK = 18678289;
  uint256 internal constant ONE_TRANCHE = 1e18;
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  string internal constant borrowerName = 'testBorrower';
  address internal manager = makeAddr('manager');
  address internal borrower = makeAddr('borrower');

  address internal defaultUnderlying = USDC;
  IdleCDOEpochVariant internal cdoEpoch;
  uint256 internal initialProvidedApr = 10e18;

  event AccrueInterest(uint256 interest, uint256 fees);
  event BorrowerDefault(uint256 payment);
  event Unpaused(address user);

  function setUp() public override {
    vm.createSelectFork("mainnet", FORK_BLOCK);
    super.setUp();
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOEpochVariant();
  }

  function _deployStrategy(address _owner)
    internal
    override
    returns (address _strategy, address _underlying)
  {
    _underlying = defaultUnderlying;
    strategy = new IdleCreditVault();
    strategyToken = IERC20Detailed(address(strategy));
    _strategy = address(strategy);

    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    IdleCreditVault(_strategy).initialize(_underlying, _owner, manager, borrower, borrowerName, initialProvidedApr);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleCreditVault(address(strategy)).setWhitelistedCDO(_cdo);
    /// borrower must approve CDO to withdraw funds
    vm.prank(borrower);
    IERC20Detailed(defaultUnderlying).approve(_cdo, type(uint256).max);
    cdoEpoch = IdleCDOEpochVariant(_cdo);

    // For testing let's support both tranches with AYS
    vm.startPrank(_owner);
    cdoEpoch.setIsAYSActive(true);
    cdoEpoch.setLossToleranceBps(5000);
    cdoEpoch.setEpochDuration(36.5 days); // set this to have an epoch during 1/10 of the year
    vm.stopPrank();
  }

  function _donateToken(address to, uint256 amount) internal override {
    deal(defaultUnderlying, to, amount);
  }

  function _createLoss(uint256) internal override {
    // TODO
    // uint256 totalAssets = defaultVault.totalAssets();
    // uint256 loss = totalAssets * _loss / FULL_ALLOC;
    // uint256 bal = underlying.balanceOf(address(defaultVault));
    // require(bal >= loss, "test: loss is too large");
    // vm.prank(address(defaultVault));
    // underlying.transfer(address(0xdead), loss);
    // update vault price
    _pokeLendingProtocol();
  }

  function _toggleEpoch(bool _start, uint256 newApr, uint256 funds) internal {
    IdleCDOEpochVariant _vault = IdleCDOEpochVariant(address(idleCDO));
    address _owner = IdleCreditVault(_vault.strategy()).manager();
    vm.startPrank(_owner); 
    if (_start) {
      _vault.startEpoch();
    } else {
      deal(defaultUnderlying, borrower, funds);
      vm.warp(_vault.epochEndDate() + 1);
      uint256 expectedInterest = _vault.expectedEpochInterest();
      uint256 fees = _vault.fee() * expectedInterest / FULL_ALLOC;
      uint256 pendingWithdraws = IdleCreditVault(address(strategy)).pendingWithdraws();
      vm.expectEmit(address(_vault));
      if (funds < expectedInterest + pendingWithdraws) {
        emit BorrowerDefault(expectedInterest + pendingWithdraws);
      } else {
        emit AccrueInterest(expectedInterest, fees);
      }
      _vault.stopEpoch(newApr);
    }
    vm.stopPrank(); 
  }

  function _getInstantFunds() internal {
    deal(defaultUnderlying, borrower, IdleCreditVault(address(strategy)).pendingInstantWithdraws());
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();
  }

  function testCantReinitialize() external override {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    IdleCreditVault(address(strategy)).initialize(defaultUnderlying, address(1), manager, borrower, borrowerName, 1e18);
  }

  function testCannotDepositWhenEpochRunningOrDefault() external {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    _toggleEpoch(true, 0, 0);

    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositAA(amount);

    // give less funds to borrower so default
    _toggleEpoch(false, initialApr, 1000);
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositAA(amount);
  }

  function testCannotRequestRedeemWhenEpochRunningOrDefault() external {
    uint256 amount = 1 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);
    vm.roll(block.number + 1);

    // start epoch
    _toggleEpoch(true, 0, 0);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdrawAA(0);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdrawBB(0);

    // give less funds to borrower so default
    _toggleEpoch(false, initialApr, 1000);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdrawAA(0);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdrawBB(0);
  }

  // @notice normal redeems are blocked
  function testRedeems() external override {
    uint256 amount = 1 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);
    vm.roll(block.number + 1);

    // start epoch
    _toggleEpoch(true, 0, 0);

    // When epoch is running the withdraw flows is blocked right away
    vm.expectRevert(bytes('3'));
    idleCDO.withdrawAA(0);
    vm.expectRevert(bytes('3'));
    idleCDO.withdrawBB(0);

    // stop epoch
    _toggleEpoch(false, 1e18, 1000);

    // While the epoch is stopped the withdraw flows is blocked in the _withdraw (overridden)
    // hence the different error
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    idleCDO.withdrawAA(0);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    idleCDO.withdrawBB(0);
  }

  function testMinStkIDLEBalance() external override {
    uint256 tolerance = 100;
    _internalTestMinStkIDLEBalance(tolerance);
  }

  function _expectedFundsEndEpoch() internal view returns (uint256 expected) {
    expected = cdoEpoch.expectedEpochInterest() + IdleCreditVault(address(strategy)).pendingWithdraws();
  }

  function testDeposits() external override {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;
    uint256 totAmount = amount * 2 * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    assertEq(cdoEpoch.totEpochDeposits(), amountWei, "totEpochDeposits after AA deposit");
    idleCDO.depositBB(amountWei);
    assertEq(cdoEpoch.totEpochDeposits(), totAmount, "totEpochDeposits after BB deposit");


    uint256 balAA = IERC20(AAtranche).balanceOf(address(this));
    uint256 balBB = IERC20(BBtranche).balanceOf(address(this));

    // Minted amount is 1:1 with underlyings
    assertEq(balAA, amount * ONE_TRANCHE_TOKEN, "AAtranche bal");
    assertEq(balBB, amount * ONE_TRANCHE_TOKEN, "BBtranche bal");

    assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal");

    // check that trancheAPRSplitRatio and aprs are updated 
    assertApproxEqAbs(idleCDO.trancheAPRSplitRatio(), 25000, 1, "split ratio");
    // limit is 50% of the strategy apr if AAratio is <= 50%
    assertEq(idleCDO.getApr(address(AAtranche)), initialApr / 2, "AA apr");
    // apr will be 150% of the strategy apr if AAratio is == 50%
    assertEq(idleCDO.getApr(address(BBtranche)), initialApr * 3 / 2, "BB apr");

    // start epoch
    _toggleEpoch(true, 0, 0);

    assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal is != 0 in CDO");
    assertEq(
      strategyToken.balanceOf(address(idleCDO)), 
      totAmount, 
      "strategy bal"
    );
    uint256 strategyPrice = strategy.price();
    // end epoch with gain, same apr
    _toggleEpoch(false, 1e18, _expectedFundsEndEpoch());

    // strategy token price is fixed to 1 underlying
    assertEq(strategy.price(), strategyPrice, "strategy price changed");

    // virtualPrice should increase too
    assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
    assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
  }

  /// @notice test init values for both cdo and strategy
  function testInitValues() external view {
    IdleCreditVault _strategy = IdleCreditVault(address(strategy));

    // IdleCDOEpoch vars
    assertEq(cdoEpoch.unlentPerc(), 0, "unlentPerc");
    // this is overidden in the test
    // assertEq(cdoEpoch.lossToleranceBps(), FULL_ALLOC, 'lossTokenranceBps is wrong');
    assertEq(cdoEpoch.trancheAPRSplitRatio(), FULL_ALLOC, 'trancheAPRSplitRatio is wrong');
    assertEq(cdoEpoch.epochDuration(), 30 days, 'epochDuration is wrong');
    assertEq(cdoEpoch.instantWithdrawDelay(), 3 days, 'instantWithdrawDelay is wrong');
    assertEq(cdoEpoch.allowAAWithdraw(), false, 'allowAAWithdraw is wrong');
    assertEq(cdoEpoch.allowBBWithdraw(), false, 'allowBBWithdraw is wrong');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), true, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), true, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.instantWithdrawAprDelta(), 1e18, 'instantWithdrawAprDelta is wrong');

    // IdleCreditVault vars
    assertEq(_strategy.manager(), manager, 'manager is wrong');
    assertEq(_strategy.borrower(), borrower, 'borrower is wrong');
    assertEq(_strategy.lastApr(), initialProvidedApr, 'lastApr is wrong');
    assertEq(IERC20Detailed(address(_strategy)).name(), "Idle Credit Vault testBorrower", 'token name is wrong');
    assertEq(IERC20Detailed(address(_strategy)).symbol(), "idle_testBorrower", 'symbol is wrong');
    assertEq(IERC20Detailed(address(_strategy)).decimals(), IERC20Detailed(defaultUnderlying).decimals(), 'decimals is wrong');
    assertEq(_strategy.owner(), owner, 'owner is wrong');
  }

  /// @notice test only owner or manager methods
  function testOnlyOwnerOrManagerVariables() external {
    // setEpochDuration
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setEpochDuration(1);

    vm.prank(owner);
    cdoEpoch.setEpochDuration(1);
    assertEq(cdoEpoch.epochDuration(), 1, 'epochDuration is wrong');

    vm.prank(manager);
    cdoEpoch.setEpochDuration(2);
    assertEq(cdoEpoch.epochDuration(), 2, 'epochDuration is wrong');

    // setInstantWithdrawDelay
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setInstantWithdrawDelay(1);

    vm.prank(owner);
    cdoEpoch.setInstantWithdrawDelay(1);
    assertEq(cdoEpoch.instantWithdrawDelay(), 1, 'instantWithdrawDelay is wrong');

    vm.prank(manager);
    cdoEpoch.setInstantWithdrawDelay(2);
    assertEq(cdoEpoch.instantWithdrawDelay(), 2, 'instantWithdrawDelay is wrong');

    // setInstantWithdrawAprDelta
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setInstantWithdrawAprDelta(1);

    vm.prank(owner);
    cdoEpoch.setInstantWithdrawAprDelta(1);
    assertEq(cdoEpoch.instantWithdrawAprDelta(), 1, 'instantWithdrawAprDelta is wrong');

    vm.prank(manager);
    cdoEpoch.setInstantWithdrawAprDelta(2);
    assertEq(cdoEpoch.instantWithdrawAprDelta(), 2, 'instantWithdrawAprDelta is wrong');

    // setDisableInstantWithdraw
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setDisableInstantWithdraw(true);

    vm.prank(owner);
    cdoEpoch.setDisableInstantWithdraw(true);
    assertEq(cdoEpoch.disableInstantWithdraw(), true, 'disableInstantWithdraw is wrong');

    vm.prank(manager);
    cdoEpoch.setDisableInstantWithdraw(false);
    assertEq(cdoEpoch.disableInstantWithdraw(), false, 'disableInstantWithdraw is wrong');
  }

  function testMaxWithdrawable() external {
    assertEq(cdoEpoch.maxWitdrawable(address(this), idleCDO.AATranche()), 0, 'maxWitdrawable AA is wrong');
    assertEq(cdoEpoch.maxWitdrawable(address(this), idleCDO.BBTranche()), 0, 'maxWitdrawable BB is wrong');

    // make a deposit
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    uint256 interest = strategy.getApr() * amount * cdoEpoch.epochDuration() / 365 days;
    assertEq(cdoEpoch.maxWitdrawable(address(this), idleCDO.AATranche()), amount + interest, 'maxWitdrawable is wrong');

    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%
    assertEq(cdoEpoch.maxWitdrawable(address(this), idleCDO.AATranche()), amount + interest - (interest / 10), 'maxWitdrawable with fees is wrong');
  }

  function testMaxInstantWithdrawable() external {
    assertEq(cdoEpoch.maxWitdrawableInstant(address(this), idleCDO.AATranche()), 0, 'maxWitdrawableInstant AA is wrong');
    assertEq(cdoEpoch.maxWitdrawableInstant(address(this), idleCDO.BBTranche()), 0, 'maxWitdrawableInstant BB is wrong');

    // make a deposit
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    assertEq(cdoEpoch.maxWitdrawableInstant(address(this), idleCDO.AATranche()), amount, 'maxWitdrawableInstant is wrong');
  }

  function testStartEpoch() external {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;
    uint256 totAmount = amount * 2 * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);

    uint256 time = block.timestamp;
    // start epoch
    _toggleEpoch(true, 0, 0);

    // check that manager cannot call startEpoch again
    vm.expectRevert(abi.encodeWithSelector(EpochRunning.selector));
    vm.prank(manager);
    cdoEpoch.startEpoch();

    assertEq(cdoEpoch.isEpochRunning(), true, 'epoch is not running');
    assertEq(cdoEpoch.paused(), true, 'cdo is not paused');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), false, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), false, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.expectedEpochInterest(), (initialProvidedApr / 100) * totAmount * cdoEpoch.epochDuration() / (365 days * ONE_TRANCHE_TOKEN), 'expectedEpochInterest is wrong');
    assertEq(cdoEpoch.epochEndDate(), time + cdoEpoch.epochDuration(), 'epochEndDate is wrong');
    assertEq(cdoEpoch.instantWithdrawDeadline(), time + cdoEpoch.instantWithdrawDelay(), 'instantWithdrawDeadline is wrong');
    assertEq(cdoEpoch.totEpochDeposits(), 0, 'totEpochDeposits is wrong');
    assertEq(IERC20Detailed(strategyToken).balanceOf(address(idleCDO)), totAmount, 'strategyToken bal in cdo is wrong');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(borrower), totAmount, 'funds are not sent to borrower');
  }

  function testStartEpochWithSpecificData() external {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;
    uint256 totAmount = amount * 2 * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);

    vm.startPrank(manager);
    IdleCreditVault(address(strategy)).setApr(10e18); // 10%
    cdoEpoch.setEpochDuration(365 days);
    vm.stopPrank();

    // start epoch
    _toggleEpoch(true, 0, 0);
    assertEq(cdoEpoch.expectedEpochInterest(), totAmount / 10, 'expectedEpochInterest with specific data is wrong');
  }

  function testStartEpochWithPendingInstant() external {
    vm.prank(manager);
    cdoEpoch.setInstantWithdrawAprDelta(1000);

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);

    uint256 interest = cdoEpoch.expectedEpochInterest();
    uint256 fees = cdoEpoch.fee() * interest / FULL_ALLOC;
    // end epoch with gain, lower apr so instant withdrawal are available
    _toggleEpoch(false, initialProvidedApr / 2, _expectedFundsEndEpoch());

    // request instant withdrawals for all AA which is more than the underlyings
    uint256 requested = cdoEpoch.requestWithdrawAA(0);

    // start epoch
    _startEpochAndCheckPrices(1);

    // borrower did not get any funds as there were instant withdraw to fullfill first
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(borrower), 0, 'borrower got funds');
    assertEq(IdleCreditVault(address(strategy)).pendingInstantWithdraws(), requested - (interest - fees) , 'pendingInstantWithdraws is wrong');

    // skip to instant withdraw deadline
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    // get pending instant withdraw funds from borrower
    _getInstantFunds();

    // end epoch with gain, lower apr so instant withdrawal are again available
    uint256 _expectedFunds = _expectedFundsEndEpoch();
    _toggleEpoch(false, initialProvidedApr / 4, _expectedFunds);

    // request tranche instant withdrawals for an amount which is expected funds - 1 underlying 
    uint256 _tranchePrice = cdoEpoch.virtualPrice(address(BBtranche));
    cdoEpoch.requestWithdrawBB((_expectedFunds - ONE_SCALE) * ONE_TRANCHE_TOKEN / _tranchePrice);
    
    // start epoch
    _startEpochAndCheckPrices(2);
    // borrower should get only 1 underlyings as the rest were used for instant withdraw
    assertApproxEqAbs(IERC20Detailed(defaultUnderlying).balanceOf(borrower), ONE_SCALE, 1, 'borrower got wrong amount of funds');

    // let's end the epoch once more with decreasing apr
    _expectedFunds = _expectedFundsEndEpoch();
    _toggleEpoch(false, initialProvidedApr / 8, _expectedFunds);

    // do some deposits
    uint256 newDeposit = amountWei;
    idleCDO.depositAA(newDeposit);

    // request another instant withdraw which is less than the underlyings available
    _tranchePrice = cdoEpoch.virtualPrice(address(BBtranche));
    cdoEpoch.requestWithdrawBB((_expectedFunds + newDeposit - ONE_SCALE) * ONE_TRANCHE_TOKEN / _tranchePrice);
    // start epoch
    _startEpochAndCheckPrices(2);
    // borrower should get only 1 underlyings as the rest were used for instant withdraw
    assertApproxEqAbs(IERC20Detailed(defaultUnderlying).balanceOf(borrower), ONE_SCALE, 1, 'borrower got wrong amount of funds after new deposits');
  }

  function _startEpochAndCheckPrices(uint256 epochNum) internal {
    // start epoch
    uint256 AAPricePre = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 BBPricePre = cdoEpoch.virtualPrice(address(BBtranche));
    _toggleEpoch(true, 0, 0);
    uint256 AAPricePost = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 BBPricePost = cdoEpoch.virtualPrice(address(BBtranche));
    assertApproxEqAbs(AAPricePost, AAPricePre, 1, 
      string(abi.encodePacked("AA price is not the same after starting epoch: ", epochNum))
    );
    assertApproxEqAbs(BBPricePost, BBPricePre, 1,
      string(abi.encodePacked("BB price is not the same after starting epoch: ", epochNum))
    );
  }

  function _stopEpochAndCheckPrices(uint256 epochNum, uint256 newApr, uint256 funds) internal {
    // start epoch
    uint256 AAPricePre = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 BBPricePre = cdoEpoch.virtualPrice(address(BBtranche));
    _toggleEpoch(false, newApr, funds);
    uint256 AAPricePost = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 BBPricePost = cdoEpoch.virtualPrice(address(BBtranche));
    assertGt(AAPricePost, AAPricePre,
      string(abi.encodePacked("AA price is not the same after stopping epoch: ", epochNum))
    );
    assertGt(BBPricePost, BBPricePre,
      string(abi.encodePacked("BB price is not the same after stopping epoch: ", epochNum))
    );
  }

  function testStopEpoch() external {
    vm.prank(manager);
    cdoEpoch.setInstantWithdrawAprDelta(1000);
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    // check that manager cannot call stopEpoch if there is no epoch running
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(initialApr);

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);

    // check that manager cannot call stopEpoch before end date
    vm.warp(cdoEpoch.epochEndDate() - 1);
    vm.expectRevert(abi.encodeWithSelector(EpochRunning.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(initialApr);

    uint256 expectedInterest = cdoEpoch.expectedEpochInterest();
    uint256 fees = cdoEpoch.fee() * expectedInterest / FULL_ALLOC;
    uint256 expectedNet = expectedInterest - fees;
    uint256 feeReceiverBal = IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver());

    // end epoch with gain, almost same apr so normal withdrawal are available
    _stopEpochAndCheckPrices(0, initialProvidedApr - 999, _expectedFundsEndEpoch());

    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(cdoEpoch)), expectedNet, 'cdo got wrong amount of funds');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver()) > 0, true, 'fee receiver got some fees');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver()) - feeReceiverBal, fees, 'fee receiver got wrong amount of fees');
    assertEq(cdoEpoch.unclaimedFees(), 0, 'unclaimedFees is reset');
    assertEq(cdoEpoch.lastEpochInterest(), expectedNet, 'lastEpochInterest is wrong');
    assertEq(cdoEpoch.lastEpochApr(), initialProvidedApr, 'lastEpochApr is wrong');
    assertEq(strategy.getApr(), initialProvidedApr - 999, 'strategy apr is wrong');
    assertEq(cdoEpoch.isEpochRunning(), false, 'isEpochRunning is wrong');
    assertEq(cdoEpoch.expectedEpochInterest(), 0, 'expectedEpochInterest is wrong');
    assertEq(cdoEpoch.paused(), false, 'isPaused is wrong');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), true, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), true, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowInstantWithdraw(), false, 'allowInstantWithdraw is wrong');
    
    // request normal withdraw
    cdoEpoch.requestWithdrawAA(0);

    // start epoch
    _startEpochAndCheckPrices(1);

    expectedInterest = cdoEpoch.expectedEpochInterest();
    uint256 fee = cdoEpoch.fee() * expectedInterest / FULL_ALLOC;
    uint256 pending = IdleCreditVault(address(strategy)).pendingWithdraws();
    uint256 balPreStrategy = IERC20Detailed(defaultUnderlying).balanceOf(address(strategy));

    // stop epoch 
    _stopEpochAndCheckPrices(1, initialProvidedApr, _expectedFundsEndEpoch());

    // interest minus fees are in the cdo contract
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(cdoEpoch)), expectedInterest - fee, 'cdo got wrong amount of funds with pending withdraw');
    // pending withdraw requests are in the strategy contract
    uint256 balPostStrategy = IERC20Detailed(defaultUnderlying).balanceOf(address(strategy));
    assertEq(balPostStrategy - balPreStrategy, pending, 'strategy got wrong amount of funds with pending withdraw');
  }

  function testStopEpochWithDefault() external {
    vm.prank(manager);
    cdoEpoch.setInstantWithdrawAprDelta(1000);
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);

    // end epoch with no enough funds to cover interest payment
    _toggleEpoch(false, initialProvidedApr, _expectedFundsEndEpoch() - 1);

    _checkDefault();
    assertEq(cdoEpoch.allowInstantWithdraw(), true, 'allowInstantWithdraw is wrong');
  }
  
  function _checkDefault() internal view {
    assertEq(cdoEpoch.defaulted(), true, 'pool is not defaulted');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), false, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), false, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.paused(), true, 'cdo is not paused');
  }

  function testOnlyCDOCanGetFundsFromBorrower() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(address(222));
    cdoEpoch.getFundsFromBorrower(1,1,1);

    deal(defaultUnderlying, borrower, 1000);

    // cdo can call this
    vm.prank(address(idleCDO));
    cdoEpoch.getFundsFromBorrower(1,1,1);
  }

  function testGetInstantWithdrawFunds() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(address(222));
    cdoEpoch.getInstantWithdrawFunds();

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);
    // end epoch with gain and decreased apy
    _toggleEpoch(false, initialProvidedApr / 2, _expectedFundsEndEpoch());
    // request instant withdraw
    cdoEpoch.requestWithdrawAA(0);

    // owner or manager cannot get funds if epoch is not running
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();

    // start new epoch
    _startEpochAndCheckPrices(0);

    // owner or manager cannot get funds before deadline
    vm.expectRevert(abi.encodeWithSelector(DeadlineNotMet.selector));
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();

    uint256 balStrategyPre = IERC20Detailed(defaultUnderlying).balanceOf(address(strategy));
    uint256 instantFunds = IdleCreditVault(address(strategy)).pendingInstantWithdraws();
    // skip to instant withdraw deadline
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    // get pending instant withdraw funds from borrower
    _getInstantFunds();

    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(strategy)) - balStrategyPre, instantFunds, 'strategy got wrong amount of funds');
    assertEq(cdoEpoch.allowInstantWithdraw(), true, 'allowInstantWithdraw is wrong');
    assertEq(IdleCreditVault(address(strategy)).pendingInstantWithdraws(), 0, 'pendingInstantWithdraws is wrong');
  }

  function testGetInstantWithdrawFundsDefault() external {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);
    // end epoch with gain and decreased apy
    _toggleEpoch(false, initialProvidedApr / 2, _expectedFundsEndEpoch());
    // request instant withdraw
    cdoEpoch.requestWithdrawAA(0);

    // start new epoch
    _startEpochAndCheckPrices(0);
    // skip to instant withdraw deadline
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);

    // assert that there are pending instant withdraw
    assertEq(IdleCreditVault(address(strategy)).pendingInstantWithdraws() > 0, true, 'pendingInstantWithdraws is wrong');

    // we don't deal funds to borrower so the pool will default and try to get funds
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();

    _checkDefault();
  }

  function testRequestWithdrawNormal() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // request normal withdraw, but with amount too high
    uint256 trancheReqAA = IERC20Detailed(address(AAtranche)).balanceOf(address(this)) + 1;
    vm.expectRevert(abi.encodeWithSelector(AmountTooHigh.selector));
    cdoEpoch.requestWithdrawAA(trancheReqAA);
    uint256 trancheReqBB = IERC20Detailed(address(BBtranche)).balanceOf(address(this)) + 1;
    vm.expectRevert(abi.encodeWithSelector(AmountTooHigh.selector));
    cdoEpoch.requestWithdrawBB(trancheReqBB);

    uint256 maxAA = cdoEpoch.maxWitdrawable(address(this), idleCDO.AATranche());
    uint256 maxBB = cdoEpoch.maxWitdrawable(address(this), idleCDO.BBTranche());

    // request max withdraw
    uint256 requestedAA = cdoEpoch.requestWithdrawAA(0);
    assertEq(IdleCreditVault(address(strategy)).pendingWithdraws(), requestedAA, 'pendingWithdraws for AA is wrong');
    assertEq(IdleCreditVault(address(strategy)).withdrawsRequests(address(this)), requestedAA, 'withdrawsRequests for AA is wrong');
    assertEq(maxAA > 0, true, 'maxAA is wrong');
    assertEq(requestedAA, maxAA, 'requested amount for AA is wrong');

    uint256 requestedBB = cdoEpoch.requestWithdrawBB(0);
    assertEq(IdleCreditVault(address(strategy)).pendingWithdraws(), requestedAA + requestedBB, 'pendingWithdraws for BB is wrong');
    assertEq(IdleCreditVault(address(strategy)).withdrawsRequests(address(this)), requestedAA + requestedBB, 'withdrawsRequests for BB is wrong');
    assertEq(maxBB > 0, true, 'maxBB is wrong');
    assertEq(requestedBB, maxBB, 'requested amount for BB is wrong');
  }

  // function testMultipleDeposits() external {
  //   uint256 _val = 100 * ONE_SCALE;
  //   uint256 scaledVal = _val * 10**(18 - decimals);
  //   deal(address(underlying), address(this), _val * 100000000);

  //   uint256 priceAAPre = idleCDO.virtualPrice(address(AAtranche));
  //   // try to deposit the correct bal
  //   idleCDO.depositAA(_val);
  //   assertApproxEqAbs(
  //     IERC20Detailed(address(AAtranche)).balanceOf(address(this)), 
  //     scaledVal, 
  //     // 1 wei less for each unit of underlying, scaled to 18 decimals
  //     // check _mintShares for more info
  //     100 * 10**(18 - decimals) + 1, 
  //     'AA Deposit 1 is not correct'
  //   );
  //   uint256 priceAAPost = idleCDO.virtualPrice(address(AAtranche));

  //   // now deposit again
  //   address user1 = makeAddr('user1');
  //   _depositWithUser(user1, _val, true);
  //   assertApproxEqAbs(
  //     IERC20Detailed(address(AAtranche)).balanceOf(user1), 
  //     scaledVal, 
  //     // 1 wei less for each unit of underlying, scaled to 18 decimals
  //     // check _mintShares for more info
  //     100 * 10**(18 - decimals) + 1, 
  //     'AA Deposit 2 is not correct'
  //   );
  //   uint256 priceAAPost2 = idleCDO.virtualPrice(address(AAtranche));

  //   assertApproxEqAbs(priceAAPost, priceAAPre, 1, 'AA price is not the same after deposit 1');
  //   assertApproxEqAbs(priceAAPost2, priceAAPost, 1, 'AA price is not the same after deposit 2');
  // }

  // // @dev Loss is between 0% and lossToleranceBps and is socialized
  // function testDepositWithLossSocialized(uint256 depositAmountAARatio) external override {
  //   vm.assume(depositAmountAARatio >= 0);
  //   vm.assume(depositAmountAARatio <= FULL_ALLOC);

  //   uint256 amountAA = 100000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
  //   uint256 amountBB = 100000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;
  //   uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
  //   uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

  //   idleCDO.depositAA(amountAA);
  //   idleCDO.depositBB(amountBB);

  //   uint256 prePrice = strategy.price();
  //   uint256 unclaimedFees = idleCDO.unclaimedFees();

  //   // now let's simulate a loss by decreasing strategy price
  //   // curr price - about 0.25%
  //   _createLoss(idleCDO.lossToleranceBps() / 2);

  //   uint256 priceDelta = ((prePrice - strategy.price()) * 1e18) / prePrice;
  //   uint256 lastNAVAA = idleCDO.lastNAVAA();
  //   uint256 currentAARatioScaled = lastNAVAA * ONE_SCALE / (idleCDO.lastNAVBB() + lastNAVAA);
  //   uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
  //   uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));

  //   // Both junior and senior lost
  //   if (currentAARatioScaled > 0) {
  //     assertApproxEqAbs(postAAPrice, (preAAPrice * (1e18 - priceDelta)) / 1e18, 100, "AA price after loss");
  //   } else {
  //     assertApproxEqAbs(postAAPrice, preAAPrice, 1, "AA price not changed");
  //   }
  //   if (currentAARatioScaled < ONE_SCALE) {
  //     assertApproxEqAbs(postBBPrice, (preBBPrice * (1e18 - priceDelta)) / 1e18, 100, "BB price after loss");
  //   } else {
  //     assertApproxEqAbs(postBBPrice, preBBPrice, 1, "BB price not changed");
  //   }

  //   assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 1, "AA price not updated until new interaction");
  //   assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 1, "BB price not updated until new interaction");
  //   assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 0, "Fees did not increase");
  // }
}