// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IKeyring} from "../../contracts/interfaces/keyring/IKeyring.sol";

error EpochRunning();
error NotAllowed();
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

  function _deployLocalContracts() internal override returns (IdleCDO _cdo) {
    // We modified only the initial apr split ratio
    address _owner = address(0xdeadbad);
    address _rebalancer = address(0xbaddead);
    (address _strategy, address _underlying) = _deployStrategy(_owner);
    
    // deploy idleCDO and tranches
    _cdo = _deployCDO();
    stdstore
      .target(address(_cdo))
      .sig(_cdo.token.selector)
      .checked_write(address(0));
    _cdo.initialize(
      0,
      _underlying,
      address(this), // governanceFund,
      _owner, // owner,
      _rebalancer, // rebalancer,
      _strategy, // strategyToken
      100000 // apr split: 100000 is 100% to AA
    );

    vm.startPrank(_owner);
    _cdo.setIsAYSActive(true);
    _cdo.setUnlentPerc(0);
    _cdo.setFee(0);
    vm.stopPrank();

    _postDeploy(address(_cdo), _owner);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleCreditVault cv = IdleCreditVault(address(strategy));
    cv.setWhitelistedCDO(_cdo);
    /// borrower must approve CDO to withdraw funds
    vm.prank(borrower);
    IERC20Detailed(defaultUnderlying).approve(_cdo, type(uint256).max);
    cdoEpoch = IdleCDOEpochVariant(_cdo);
    uint256 epochDuration = 36.5 days;
    uint256 buffer = 5 days;
    // For testing let's support both tranches with AYS
    vm.startPrank(_owner);
    cdoEpoch.setIsAYSActive(true);
    cdoEpoch.setInstantWithdrawParams(3 days, 1.5e18, false);
    cdoEpoch.setLossToleranceBps(5000);
    cdoEpoch.setEpochParams(epochDuration, buffer); // set this to have an epoch during 1/10 of the year
    cdoEpoch.setKeyringParams(address(0), 0, false); // deactivate keyring
    vm.stopPrank();

    // we set the apr again manually for tests because we changed epoch params
    // scaled by the buffer period
    vm.startPrank(cv.manager());
    cv.setApr(_scaleAprWithBuffer(initialProvidedApr));
    vm.stopPrank();
  }

  function _scaleAprWithBuffer(uint256 _apr) internal view returns (uint256) {
    uint256 _duration = cdoEpoch.epochDuration();
    return _apr * (_duration + cdoEpoch.bufferPeriod()) / _duration;
  }

  function _donateToken(address to, uint256 amount) internal override {
    deal(defaultUnderlying, to, amount);
  }

  function _createLoss(uint256 _loss) internal override {
    // NOTE: this will decrease tranche prices but not the strategy price so no 
    // automatic default can be triggered
    uint256 loss = cdoEpoch.getContractValue() * _loss / FULL_ALLOC;
    // To create loss we move strategyTokens away from IdleCDO
    uint256 bal = strategyToken.balanceOf(address(cdoEpoch));
    require(bal >= loss, "test: loss is too large");
    vm.prank(owner);
    cdoEpoch.transferToken(address(strategy), loss);
  }

  function _toggleEpoch(bool _start, uint256 newApr, uint256 funds) internal {
    IdleCDOEpochVariant _vault = IdleCDOEpochVariant(address(idleCDO));
    address _owner = IdleCreditVault(_vault.strategy()).manager();
    vm.startPrank(_owner); 
    if (_start) {
      if (_vault.epochEndDate() != 0) {
        vm.warp(block.timestamp + _vault.bufferPeriod() + 1);
      }
      _vault.startEpoch();
    } else {
      deal(defaultUnderlying, borrower, funds);
      vm.warp(_vault.epochEndDate() + 1);
      uint256 pendingFees = _vault.pendingWithdrawFees();
      uint256 expectedInterest = _vault.expectedEpochInterest();
      uint256 fees = _vault.fee() * (expectedInterest - pendingFees) / FULL_ALLOC;
      uint256 pendingWithdraws = IdleCreditVault(address(strategy)).pendingWithdraws();
      vm.expectEmit(address(_vault));
      if (funds < expectedInterest + pendingWithdraws) {
        emit BorrowerDefault(expectedInterest + pendingWithdraws);
      } else {
        emit AccrueInterest(expectedInterest, fees + pendingFees);
      }
      _vault.stopEpoch(newApr, 0);
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
    cdoEpoch.requestWithdraw(0, address(AAtranche));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(0, address(BBtranche));

    // give less funds to borrower so default
    _toggleEpoch(false, initialApr, 1000);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(0, address(AAtranche));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(0, address(BBtranche));
  }

  // @notice normal redeems are blocked
  function testRedeems() external override {
    uint256 amount = 1 * ONE_SCALE;
    uint256 mintedAA = idleCDO.depositAA(amount);
    uint256 mintedBB = idleCDO.depositBB(amount);
    vm.roll(block.number + 1);

    // start epoch
    _toggleEpoch(true, 0, 0);

    // stop epoch
    _toggleEpoch(false, 1e18, 1e18);

    // nothing happens if normal withdraw is triggered
    idleCDO.withdrawAA(0);
    assertEq(mintedAA, IERC20(AAtranche).balanceOf(address(this)), "AAtranche balance changed");
    idleCDO.withdrawBB(0);
    assertEq(mintedBB, IERC20(BBtranche).balanceOf(address(this)), "BBtranche balance changed");
  }

  function testMinStkIDLEBalance() external override {
    // Overridden and not used
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
    assertEq(IdleCreditVault(address(strategy)).totEpochDeposits(), amountWei, "totEpochDeposits after AA deposit");
    idleCDO.depositBB(amountWei);
    assertEq(IdleCreditVault(address(strategy)).totEpochDeposits(), totAmount, "totEpochDeposits after BB deposit");
    assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal is != 0 in CDO after deposit");
    assertEq(
      strategyToken.balanceOf(address(idleCDO)), 
      totAmount, 
      "strategy bal after deposits is wrong"
    );

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
    assertEq(cdoEpoch.epochDuration(), 36.5 days, 'epochDuration is wrong');
    assertEq(cdoEpoch.bufferPeriod(), 5 days, 'bufferPeriod is wrong');
    assertEq(cdoEpoch.instantWithdrawDelay(), 3 days, 'instantWithdrawDelay is wrong');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), true, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), true, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.instantWithdrawAprDelta(), 1.5e18, 'instantWithdrawAprDelta is wrong');
    assertEq(cdoEpoch.directDeposit(), true, 'directDeposit is wrong');
    // assertEq(cdoEpoch.keyring() != address(0), true, 'keyring address is wrong');
    // assertEq(cdoEpoch.keyringPolicyId() != 0, true, 'keyring policy id is wrong');

    // IdleCreditVault vars
    assertEq(_strategy.epochNumber(), 0, 'epochNumber is wrong');
    assertEq(_strategy.manager(), manager, 'manager is wrong');
    assertEq(_strategy.borrower(), borrower, 'borrower is wrong');
    assertEq(_strategy.lastApr(), _scaleAprWithBuffer(initialProvidedApr), 'lastApr is wrong');
    assertEq(IERC20Detailed(address(_strategy)).name(), "Idle Credit Vault testBorrower USDC", 'token name is wrong');
    assertEq(IERC20Detailed(address(_strategy)).symbol(), "testBorrowerUSDC", 'symbol is wrong');
    assertEq(IERC20Detailed(address(_strategy)).decimals(), IERC20Detailed(defaultUnderlying).decimals(), 'decimals is wrong');
    assertEq(_strategy.owner(), owner, 'owner is wrong');
  }

  /// @notice test only owner or manager methods
  function testOnlyOwnerOrManagerVariables() external {
    // setEpochParams
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setEpochParams(1, 5 days);

    vm.prank(owner);
    cdoEpoch.setEpochParams(1, 4 days);
    assertEq(cdoEpoch.epochDuration(), 1, 'epochDuration is wrong');
    assertEq(cdoEpoch.bufferPeriod(), 4 days, 'bufferPeriod is wrong');

    vm.prank(manager);
    cdoEpoch.setEpochParams(2, 3 days);
    assertEq(cdoEpoch.epochDuration(), 2, 'epochDuration is wrong');
    assertEq(cdoEpoch.bufferPeriod(), 3 days, 'bufferPeriod is wrong');

    // epochDuration cannot be 0
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.setEpochParams(0, 1 days);

    // setInstantWithdrawParams
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setInstantWithdrawParams(1, 1, true);

    vm.prank(owner);
    cdoEpoch.setInstantWithdrawParams(1, 1, true);
    assertEq(cdoEpoch.instantWithdrawDelay(), 1, 'instantWithdrawDelay is wrong');
    assertEq(cdoEpoch.instantWithdrawAprDelta(), 1, 'instantWithdrawAprDelta is wrong');
    assertEq(cdoEpoch.disableInstantWithdraw(), true, 'disableInstantWithdraw is wrong');

    vm.prank(owner);
    cdoEpoch.setInstantWithdrawParams(2, 2, false);
    assertEq(cdoEpoch.instantWithdrawDelay(), 2, 'instantWithdrawDelay update 2 is wrong');
    assertEq(cdoEpoch.instantWithdrawAprDelta(), 2, 'instantWithdrawAprDelta update 2 is wrong');
    assertEq(cdoEpoch.disableInstantWithdraw(), false, 'disableInstantWithdraw update 2 is wrong');

    _toggleEpoch(true, 0, 0);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.setEpochParams(4, 3 days);

    vm.expectRevert(abi.encodeWithSelector(EpochRunning.selector));
    vm.prank(manager);
    cdoEpoch.setInstantWithdrawParams(4, 3 days, false);

    vm.startPrank(manager);
    IdleCDOEpochVariant _vault = IdleCDOEpochVariant(address(idleCDO));
    vm.warp(_vault.epochEndDate() + 1);
    // stopEpoch and close pool by passing 1 as second param
    _vault.stopEpoch(0, 1);
    // epoch params cannot be updated anymore
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.setEpochParams(1, 1 days);
    vm.stopPrank();
  }

  function testMaxWithdrawable() external {
    assertEq(cdoEpoch.maxWithdrawable(address(this), idleCDO.AATranche()), 0, 'maxWithdrawable AA is wrong');
    assertEq(cdoEpoch.maxWithdrawable(address(this), idleCDO.BBTranche()), 0, 'maxWithdrawable BB is wrong');

    // make a deposit
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    (uint256 interest,) = _calcInterestForTranche(address(AAtranche), 10000 * ONE_TRANCHE_TOKEN);
    assertEq(cdoEpoch.maxWithdrawable(address(this), idleCDO.AATranche()), amount + interest, 'maxWithdrawable is wrong');

    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%
    assertEq(cdoEpoch.maxWithdrawable(address(this), idleCDO.AATranche()), amount + interest - (interest / 10), 'maxWithdrawable with fees is wrong');
  }

  function testMaxInstantWithdrawable() external {
    assertEq(cdoEpoch.maxWithdrawableInstant(address(this), idleCDO.AATranche()), 0, 'maxWithdrawableInstant AA is wrong');
    assertEq(cdoEpoch.maxWithdrawableInstant(address(this), idleCDO.BBTranche()), 0, 'maxWithdrawableInstant BB is wrong');

    // make a deposit
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    assertEq(cdoEpoch.maxWithdrawableInstant(address(this), idleCDO.AATranche()), amount, 'maxWithdrawableInstant is wrong');
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
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.startEpoch();

    assertEq(cdoEpoch.isEpochRunning(), true, 'epoch is not running');
    assertEq(cdoEpoch.paused(), true, 'cdo is not paused');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), false, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), false, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.expectedEpochInterest(), _scaleAprWithBuffer(initialProvidedApr / 100) * totAmount * cdoEpoch.epochDuration() / (365 days * ONE_TRANCHE_TOKEN), 'expectedEpochInterest is wrong');
    assertEq(cdoEpoch.epochEndDate(), time + cdoEpoch.epochDuration(), 'epochEndDate is wrong');
    assertEq(cdoEpoch.instantWithdrawDeadline(), time + cdoEpoch.instantWithdrawDelay(), 'instantWithdrawDeadline is wrong');
    assertEq(IERC20Detailed(strategyToken).balanceOf(address(idleCDO)), totAmount, 'strategyToken bal in cdo is wrong');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(borrower), totAmount, 'funds are not sent to borrower');
  }

  function testStartEpochWithoutWaitingBuffer() external {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);

    // start epoch
    _toggleEpoch(true, 0, 0);

    // stop epoch
    _toggleEpoch(false, 1e18, _expectedFundsEndEpoch());

    // check that manager cannot call startEpoch again without waiting for the buffer period
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.startEpoch();
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
    cdoEpoch.setEpochParams(365 days, 5 days);
    vm.stopPrank();

    // start epoch
    _toggleEpoch(true, 0, 0);
    assertEq(cdoEpoch.expectedEpochInterest(), totAmount / 10, 'expectedEpochInterest with specific data is wrong');
  }

  function testStartEpochWithPendingInstant() external {
    vm.startPrank(manager);
    cdoEpoch.setInstantWithdrawParams(cdoEpoch.instantWithdrawDelay(), 1000, false);
    vm.stopPrank();

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
    uint256 requested = cdoEpoch.requestWithdraw(0, address(AAtranche));

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
    cdoEpoch.requestWithdraw((_expectedFunds - ONE_SCALE) * ONE_TRANCHE_TOKEN / _tranchePrice, address(BBtranche));
    
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
    cdoEpoch.requestWithdraw((_expectedFunds + newDeposit - ONE_SCALE) * ONE_TRANCHE_TOKEN / _tranchePrice, address(BBtranche));
    // start epoch
    _startEpochAndCheckPrices(2);
    // borrower should get only 1 underlyings as the rest were used for instant withdraw
    assertApproxEqAbs(IERC20Detailed(defaultUnderlying).balanceOf(borrower), ONE_SCALE, 1, 'borrower got wrong amount of funds after new deposits');
  }

  function testStartEpochWithPendingNormal() external {
    IdleCreditVault _strategy = IdleCreditVault(address(strategy));

    vm.startPrank(owner);
    cdoEpoch.setFee(10000); // 10%
    cdoEpoch.setIsAYSActive(false); // we do the test only with AA so 100% of the interest shoudl go to AA
    vm.stopPrank();

    uint256 amountWei = 10000 * ONE_SCALE;
    uint256 fee = cdoEpoch.fee();
    uint256 totTVLBase = amountWei * 2;

    uint256 depositedAA = idleCDO.depositAA(totTVLBase / 2);
    _depositWithUser(makeAddr('user1'), totTVLBase / 2, true);
    // tot tvl = 20000

    // start epoch
    _startEpochAndCheckPrices(0);
    // We have apr = 11.37% (ie 10% + buffer) and 1 epoch = 1/10 of the year so the expected amount is amountWei * 2 * 11.37%
    uint256 interest = _scaleAprWithBuffer(totTVLBase / 100);
    uint256 fees = fee * interest / FULL_ALLOC;
    uint256 feeBalPre = IERC20(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver());

    // stop epoch.
    _stopEpochAndCheckPrices(0, initialProvidedApr, interest);
    
    totTVLBase += interest - fees;

    assertEq(cdoEpoch.getContractValue(), totTVLBase, 'tvl is wrong');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver()) - feeBalPre, fees, 'fee balance is wrong on epoch 1');
    
    // we request a withdraw for all the amount of user 1
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    // fee is already removed in _calcInterestForTranche
    (uint256 withdrawInterest, uint256 withdrawFees) = _calcInterestForTranche(address(AAtranche), depositedAA);
    assertApproxEqAbs(
      _strategy.pendingWithdraws(), 
      totTVLBase / 2 + withdrawInterest, 
      amountWei / ONE_SCALE, // we have up to 1 wei per underlying of difference due to having tranche price with 6 decimals and trache amount 18 decimals
      'pendingWithdraw is wrong'
    );

    // start epoch
    _startEpochAndCheckPrices(1);
    // expected interest is interest of the user still deposited (totTVLBase / 2 / 100, fees included) + the fee
    // of the user with a pending withdraw (we scale the interest with the buffer period as we do with the apr)
    assertEq(cdoEpoch.expectedEpochInterest(), _scaleAprWithBuffer(cdoEpoch.getContractValue() / 100) + withdrawFees, 'expectedEpochInterest is wrong epoch 1');
    // stop epoch.

    // gross interest
    interest = _scaleAprWithBuffer(cdoEpoch.getContractValue() / 100) + withdrawInterest + withdrawFees;
    fees = fee * interest / FULL_ALLOC;
    feeBalPre = IERC20(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver());

    // borrower should pay for pending withdraw + interest + fees + interest of the other deposit (fee included)
    // we scale the interest with the buffer period as we do with the apr
    _stopEpochAndCheckPrices(1, initialProvidedApr, _strategy.pendingWithdraws() + fees - withdrawFees + _scaleAprWithBuffer(totTVLBase / 2 / 100));

    assertApproxEqAbs(IERC20(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver()) - feeBalPre, fees, 1, 'fee balance is wrong');
    assertEq(cdoEpoch.defaulted(), false, 'borower defaulted');

    totTVLBase = cdoEpoch.getContractValue();

    // we don't claim the requested amount and start another epoch
    // interest should not be calculated for the request not withdrawn yet
    _startEpochAndCheckPrices(2);
    assertEq(cdoEpoch.expectedEpochInterest(), _scaleAprWithBuffer(totTVLBase / 100), 'expectedEpochInterest is wrong epoch 2');
    _stopEpochAndCheckPrices(2, initialProvidedApr, _scaleAprWithBuffer(totTVLBase / 100));
    assertEq(cdoEpoch.defaulted(), false, 'borower defaulted on epoch 2');
  
    totTVLBase = cdoEpoch.getContractValue();

    _startEpochAndCheckPrices(3);
    assertEq(cdoEpoch.expectedEpochInterest(), _scaleAprWithBuffer(totTVLBase / 100), 'expectedEpochInterest is wrong epoch 3');
    _stopEpochAndCheckPrices(3, initialProvidedApr, _scaleAprWithBuffer(totTVLBase / 100));
    assertEq(cdoEpoch.defaulted(), false, 'borower defaulted on epoch 3');
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
    // stop epoch
    uint256 AAPricePre = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 BBPricePre = cdoEpoch.virtualPrice(address(BBtranche));
    _toggleEpoch(false, newApr, funds);
    uint256 AAPricePost = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 BBPricePost = cdoEpoch.virtualPrice(address(BBtranche));
    if (IERC20(address(AAtranche)).totalSupply() > 0 && funds != 0) {
      assertGt(AAPricePost, AAPricePre,
        string(abi.encodePacked("AA price is not increased after stopping epoch: ", epochNum))
      );
    }
    if (IERC20(address(BBtranche)).totalSupply() > 0 && funds != 0) {
      assertGt(BBPricePost, BBPricePre,
        string(abi.encodePacked("BB price is not increased after stopping epoch: ", epochNum))
      );
    }
  }

  function testStopEpoch() external {
    vm.startPrank(manager);
    cdoEpoch.setInstantWithdrawParams(cdoEpoch.instantWithdrawDelay(), 1000, false);
    vm.stopPrank();
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    // check that manager cannot call stopEpoch if there is no epoch running
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(initialApr, 0);

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);

    // check that manager cannot call stopEpoch before end date
    vm.warp(cdoEpoch.epochEndDate() - 1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(initialApr, 0);

    uint256 expectedInterest = cdoEpoch.expectedEpochInterest();
    uint256 fees = cdoEpoch.fee() * expectedInterest / FULL_ALLOC;
    uint256 expectedNet = expectedInterest - fees;
    uint256 feeReceiverBal = IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver());
    uint256 strategyTokenBalPre = IERC20Detailed(address(strategy)).balanceOf(address(cdoEpoch));

    // end epoch with gain, almost same apr so normal withdrawal are available
    _stopEpochAndCheckPrices(0, initialProvidedApr - 999, _expectedFundsEndEpoch());

    assertEq(IdleCreditVault(address(strategy)).totEpochDeposits(), 0, 'totEpochDeposits is wrong');
    assertEq(IdleCreditVault(address(strategy)).epochNumber(), 1, 'epochNumber is wrong');
    assertEq(IERC20Detailed(address(strategy)).balanceOf(address(cdoEpoch)) - strategyTokenBalPre, expectedNet, 'cdo got wrong amount of strategyTokens');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(strategy)), expectedNet, 'strategy got wrong amount of funds');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver()) > 0, true, 'fee receiver got some fees');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(cdoEpoch.feeReceiver()) - feeReceiverBal, fees, 'fee receiver got wrong amount of fees');
    assertEq(cdoEpoch.unclaimedFees(), 0, 'unclaimedFees is reset');
    assertEq(cdoEpoch.lastEpochInterest(), expectedNet, 'lastEpochInterest is wrong');
    assertEq(cdoEpoch.lastEpochApr(), initialProvidedApr, 'lastEpochApr is wrong');
    assertEq(strategy.getApr(), _scaleAprWithBuffer(initialProvidedApr - 999), 'strategy apr is wrong');
    assertEq(IdleCreditVault(address(strategy)).unscaledApr(), initialProvidedApr - 999, 'strategy apr is wrong');
    assertEq(cdoEpoch.isEpochRunning(), false, 'isEpochRunning is wrong');
    assertEq(cdoEpoch.expectedEpochInterest(), 0, 'expectedEpochInterest is wrong');
    assertEq(cdoEpoch.paused(), false, 'isPaused is wrong');
    assertEq(cdoEpoch.allowAAWithdrawRequest(), true, 'allowAAWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowBBWithdrawRequest(), true, 'allowBBWithdrawRequest is wrong');
    assertEq(cdoEpoch.allowInstantWithdraw(), false, 'allowInstantWithdraw is wrong');
    
    // request normal withdraw
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    // start epoch
    _startEpochAndCheckPrices(1);

    uint256 pendingWithdrawFees = cdoEpoch.pendingWithdrawFees();
    expectedInterest = cdoEpoch.expectedEpochInterest();
    fees = cdoEpoch.fee() * (expectedInterest - pendingWithdrawFees) / FULL_ALLOC + pendingWithdrawFees;
    strategyTokenBalPre = IERC20Detailed(address(strategy)).balanceOf(address(cdoEpoch));
    uint256 pending = IdleCreditVault(address(strategy)).pendingWithdraws();
    uint256 balPreStrategy = IERC20Detailed(defaultUnderlying).balanceOf(address(strategy));

    // stop epoch 
    _stopEpochAndCheckPrices(1, initialProvidedApr, _expectedFundsEndEpoch());

    // all pending withdrawals were fullfilled
    assertEq(IdleCreditVault(address(strategy)).pendingWithdraws(), 0, 'wrong value of pendingWithdraw');
    // epoch number updated
    assertEq(IdleCreditVault(address(strategy)).epochNumber(), 2, 'wrong value of epochNumber');
    // interest minus fees are sent directly to the strategy
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(cdoEpoch)), 0, 'cdo got wrong amount of funds with pending withdraw');
    // interest minus fees are mint as strategyTokens in the cdo
    assertEq(IERC20Detailed(address(strategy)).balanceOf(address(cdoEpoch)) - strategyTokenBalPre, expectedInterest - fees, 'cdo got wrong amount of strategyTokens in second epoch');
    // pending withdraw requests are in the strategy contract
    uint256 balPostStrategy = IERC20Detailed(defaultUnderlying).balanceOf(address(strategy));
    assertEq(balPostStrategy - balPreStrategy, pending + (expectedInterest - fees), 'strategy got wrong amount of funds with pending withdraw');
  }

  function testStopEpochWithInterest() external {
    vm.startPrank(manager);
    cdoEpoch.setInstantWithdrawParams(cdoEpoch.instantWithdrawDelay(), 1000, true);
    vm.stopPrank();

    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;
    IdleCreditVault _strategy = IdleCreditVault(address(strategy));

    // AARatio 50%
    idleCDO.depositAA(amountWei / 2);
    idleCDO.depositBB(amountWei / 2);
    
    // start epoch
    _startEpochAndCheckPrices(0);

    // skip to end date
    vm.warp(cdoEpoch.epochEndDate() + 1);

    // cannot stop epoch with interest AND apr > 0
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(initialApr, ONE_SCALE);

    // stop epoch normally
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // instant withdraw are disabled so this is a normal withdraw request
    cdoEpoch.requestWithdraw(0, address(AAtranche));
    uint256 pendingWithdrawFee = cdoEpoch.pendingWithdrawFees();
    uint256 pendingWithdraw = _strategy.pendingWithdraws();
    assertEq(pendingWithdrawFee > 0, true, 'pendingWithdrawFees are wrong');

    // start new epoch
    _startEpochAndCheckPrices(1);

    // cannot stop the epoch with an amount of interest less then pendingWithdrawFee
    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.stopEpoch(0, pendingWithdrawFee - 1);

    // end epoch with 100 underlyings as intrerest + pendingWithdrawFee
    uint256 interest = ONE_SCALE * 100;
    deal(defaultUnderlying, borrower, interest + pendingWithdraw + pendingWithdrawFee);
    vm.prank(manager);
    cdoEpoch.stopEpoch(0, interest + pendingWithdrawFee);

    assertEq(cdoEpoch.lastEpochInterest(), 90 * ONE_SCALE, 'lastEpochInterest is wrong');
    assertEq(_strategy.getApr(), 0, 'apr is wrong');
    assertEq(cdoEpoch.pendingWithdrawFees(), 0, 'pendingWithdrawFees must be 0');
  }

  function testStopEpochWithDefault() external {
    vm.startPrank(manager);
    cdoEpoch.setInstantWithdrawParams(cdoEpoch.instantWithdrawDelay(), 1000, false);
    vm.stopPrank();
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
    assertEq(cdoEpoch.isEpochRunning(), false, 'isEpochRunning is wrong');
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
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    // owner or manager cannot get funds if epoch is not running
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();

    // start new epoch
    _startEpochAndCheckPrices(0);

    // owner or manager cannot get funds before deadline
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
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
    cdoEpoch.requestWithdraw(0, address(AAtranche));

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

    uint256 amountWei = 10000 * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    uint256 mintedBB = idleCDO.depositBB(amountWei);

    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // request normal withdraw, but with amount too high
    uint256 trancheReqAA = IERC20Detailed(address(AAtranche)).balanceOf(address(this)) + 1;
    vm.expectRevert();
    cdoEpoch.requestWithdraw(trancheReqAA, address(AAtranche));
    uint256 trancheReqBB = IERC20Detailed(address(BBtranche)).balanceOf(address(this)) + 1;
    vm.expectRevert();
    cdoEpoch.requestWithdraw(trancheReqBB, address(BBtranche));

    IdleCreditVault _strategy = IdleCreditVault(address(strategy));
    uint256 maxAA = cdoEpoch.maxWithdrawable(address(this), idleCDO.AATranche());
    uint256 lastNAVAA = cdoEpoch.lastNAVAA();
    (uint256 netInterest, ) = _calcInterestForTranche(address(AAtranche), mintedAA / 2);

    // request max withdraw (returned value is amount + net interest for next epoch)
    uint256 strategyTokenBalUser = IERC20Detailed(strategyToken).balanceOf(address(this));
    uint256 strategyTokenBalCDO = IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch));
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    assertEq(IERC20Detailed(address(strategy)).balanceOf(address(this)) - strategyTokenBalUser, requestedAA1, 'strategyTokens for user not minted properly on first request');
    assertEq(strategyTokenBalCDO - IERC20Detailed(address(strategy)).balanceOf(address(cdoEpoch)), requestedAA1 - netInterest, 'strategyTokens for cdo not burned properly on first request');
    assertEq(IERC20Detailed(address(AAtranche)).balanceOf(address(this)), mintedAA / 2, 'AA tranches not burned after first request');
    assertEq(requestedAA1, maxAA / 2, 'first requested amount for AA is wrong');
    assertEq(lastNAVAA - cdoEpoch.lastNAVAA(), requestedAA1 - netInterest, 'lastNAVAA is wrong after first request');

    // between first and second request the AA tranche apr split ratio changes so we need to refetch it
    maxAA = cdoEpoch.maxWithdrawable(address(this), idleCDO.AATranche());
    strategyTokenBalUser = IERC20Detailed(strategyToken).balanceOf(address(this));
    strategyTokenBalCDO = IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch));
    // recalculate interest as trancheAPRSplitRatio changed
    (netInterest,) = _calcInterestForTranche(address(AAtranche), mintedAA / 2);

    uint256 requestedAA2 = cdoEpoch.requestWithdraw(0, address(AAtranche));

    assertEq(requestedAA2, maxAA, 'first requested amount for AA is wrong');
    // approximated because of different decimals between tranche token and underlying
    assertApproxEqAbs(cdoEpoch.lastNAVAA(), 0, 10000, 'lastNAVAA should be 0');
    assertEq(IERC20Detailed(address(AAtranche)).balanceOf(address(this)), 0, 'AA tranches not burned');
    assertEq(IERC20Detailed(address(strategy)).balanceOf(address(this)) - strategyTokenBalUser, requestedAA2, 'strategyTokens for user not minted properly on second request');
    assertEq(strategyTokenBalCDO - IERC20Detailed(address(strategy)).balanceOf(address(cdoEpoch)), requestedAA2 - netInterest, 'strategyTokens for cdo not burned properly on second request');
    assertEq(_strategy.pendingWithdraws(), requestedAA1 + requestedAA2, 'pendingWithdraws for AA is wrong');
    assertEq(_strategy.withdrawsRequests(address(this)), requestedAA1 + requestedAA2, 'withdrawsRequests for AA is wrong');

    strategyTokenBalUser = IERC20Detailed(strategyToken).balanceOf(address(this));
    strategyTokenBalCDO = IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch));
    // recalculate interest as trancheAPRSplitRatio changed
    (netInterest,) = _calcInterestForTranche(address(BBtranche), mintedBB);
    uint256 maxBB = cdoEpoch.maxWithdrawable(address(this), idleCDO.BBTranche());
    uint256 requestedBB = cdoEpoch.requestWithdraw(0, address(BBtranche));
    // approximated because of different decimals between tranche token and underlying
    assertApproxEqAbs(cdoEpoch.lastNAVBB(), 0, 10000, 'lastNAVBB should be 0');
    assertEq(IERC20Detailed(address(BBtranche)).balanceOf(address(this)), 0, 'AA tranches not burned');
    assertEq(IERC20Detailed(strategyToken).balanceOf(address(this)) - strategyTokenBalUser, requestedBB, 'strategyTokens for user not minted properly on BB request');
    assertEq(strategyTokenBalCDO - IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch)), requestedBB - netInterest, 'strategyTokens for cdo not burned properly on BB request');
    assertEq(_strategy.pendingWithdraws(), requestedAA1 + requestedAA2 + requestedBB, 'pendingWithdraws for BB request is wrong');
    assertEq(_strategy.withdrawsRequests(address(this)), requestedAA1 + requestedAA2 + requestedBB, 'withdrawsRequests for BB is wrong');
    assertEq(maxBB > 0, true, 'maxBB is wrong');
    assertEq(requestedBB, maxBB, 'requested amount for BB is wrong');
  }

  function testRequestWithdrawNormalWithPrevRequests() external {
    vm.prank(owner);
    cdoEpoch.setFee(0); // 10%

    // deposit 10000 with this contract
    uint256 amountWei = 10000 * ONE_SCALE;
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    // deposit 10000 with user1
    address user1 = makeAddr('user1');
    _depositWithUser(user1, amountWei, true);

    // we request a withdraw right after deposit for user1 for the whole amount + interest of next epoch
    vm.startPrank(user1);
    cdoEpoch.requestWithdraw(0, address(AAtranche));
    vm.stopPrank();

    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // we now request a withdraw for address(this) for half of the funds
    cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));
    // and now we try to claim directly right after, trying 
    // to take funds that were reserved for user1 without waiting for the epoch
    vm.expectRevert();
    cdoEpoch.claimWithdrawRequest();

    // now claim with user1
    vm.startPrank(user1);
    cdoEpoch.claimWithdrawRequest();
    vm.stopPrank();

    // start epoch
    _startEpochAndCheckPrices(1);
    // stop epoch
    _stopEpochAndCheckPrices(1, initialProvidedApr, _expectedFundsEndEpoch());

    // after an epoch the user can claim
    cdoEpoch.claimWithdrawRequest();
  }

  function _calcInterest(uint256 _amount) internal view returns (uint256) {
    return _amount * (IdleCreditVault(address(strategy)).getApr() / 100) * cdoEpoch.epochDuration() / (365 days * ONE_TRANCHE_TOKEN);
  }

  function _calcInterestWithdrawRequest(uint256 _amount) internal view returns (uint256) {
    return _calcInterest(_amount) * cdoEpoch.epochDuration() / (cdoEpoch.epochDuration() + cdoEpoch.bufferPeriod());
  }

  function _calcInterestForTranche(address _tranche, uint256 trancheAmount) internal view returns (uint256, uint256) {
    uint256 trancheAPRSplitRatio = cdoEpoch.trancheAPRSplitRatio();
    uint256 aprRatio = _tranche == address(AAtranche) ? trancheAPRSplitRatio : FULL_ALLOC - trancheAPRSplitRatio;
    uint256 interest = _calcInterestWithdrawRequest(
      trancheAmount * cdoEpoch.tranchePrice(_tranche) / ONE_TRANCHE_TOKEN
    ) * aprRatio / FULL_ALLOC;
    uint256 fees = interest * cdoEpoch.fee() / FULL_ALLOC;
    return (interest - fees, fees);
  }

  function testRequestWithdrawInstant() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch with less apr so instant withdrawal are available
    _stopEpochAndCheckPrices(0, initialProvidedApr - (cdoEpoch.instantWithdrawAprDelta() + 1), _expectedFundsEndEpoch());

    // request instant withdraw, but with amount too high
    uint256 trancheReqAA = IERC20Detailed(address(AAtranche)).balanceOf(address(this)) + 1;
    vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
    cdoEpoch.requestWithdraw(trancheReqAA, address(AAtranche));
    uint256 trancheReqBB = IERC20Detailed(address(BBtranche)).balanceOf(address(this)) + 1;
    vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
    cdoEpoch.requestWithdraw(trancheReqBB, address(BBtranche));

    uint256 maxAA = cdoEpoch.maxWithdrawableInstant(address(this), idleCDO.AATranche());
    uint256 maxBB = cdoEpoch.maxWithdrawableInstant(address(this), idleCDO.BBTranche());

    // request max withdraw
    uint256 strategyTokenBalPre = IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch));
    uint256 strategyTokenUserBalPre = IERC20Detailed(strategyToken).balanceOf(address(this));
    uint256 lastNAVAAPre = cdoEpoch.lastNAVAA();

    uint256 requestedAA = cdoEpoch.requestWithdraw(0, address(AAtranche));

    assertEq(IdleCreditVault(address(strategy)).pendingInstantWithdraws(), requestedAA, 'pendingWithdraws for AA is wrong');
    assertEq(IdleCreditVault(address(strategy)).instantWithdrawsRequests(address(this)), requestedAA, 'withdrawsRequests for AA is wrong');
    assertEq(maxAA > 0, true, 'maxAA is wrong');
    assertEq(requestedAA, maxAA, 'requested amount for AA is wrong');
    assertEq(strategyTokenBalPre - IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch)), requestedAA, 'strategyToken bal is wrong for cdo');
    assertEq(IERC20Detailed(strategyToken).balanceOf(address(this)) - strategyTokenUserBalPre, requestedAA, 'strategyToken bal is wrong for user');
    assertEq(IERC20Detailed(address(AAtranche)).balanceOf(address(this)), 0, 'trancheToken bal is wrong for user');
    assertEq(lastNAVAAPre - cdoEpoch.lastNAVAA(), requestedAA, 'lastNAVAA is wrong');

    uint256 strategyTokenBalPreBB = IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch));
    uint256 strategyTokenUserBalPreBB = IERC20Detailed(strategyToken).balanceOf(address(this));
    uint256 lastNAVBBPre = cdoEpoch.lastNAVBB();

    uint256 requestedBB = cdoEpoch.requestWithdraw(0, address(BBtranche));

    assertEq(IdleCreditVault(address(strategy)).pendingInstantWithdraws(), requestedAA + requestedBB, 'pendingWithdraws for BB is wrong');
    assertEq(IdleCreditVault(address(strategy)).instantWithdrawsRequests(address(this)), requestedAA + requestedBB, 'withdrawsRequests for BB is wrong');
    assertEq(maxBB > 0, true, 'maxBB is wrong');
    assertEq(requestedBB, maxBB, 'requested amount for BB is wrong');
    assertEq(strategyTokenBalPreBB - IERC20Detailed(strategyToken).balanceOf(address(cdoEpoch)), requestedBB, 'strategyToken bal is wrong for cdo');
    assertEq(IERC20Detailed(strategyToken).balanceOf(address(this)) - strategyTokenUserBalPreBB, requestedBB, 'strategyToken bal is wrong for user');
    assertEq(IERC20Detailed(address(BBtranche)).balanceOf(address(this)), 0, 'trancheToken bal is wrong for user');
    assertEq(lastNAVBBPre - cdoEpoch.lastNAVBB(), requestedBB, 'lastNAVBB is wrong');
  }
  
  function testClaimWithdrawRequest() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    uint256 mintedBB = idleCDO.depositBB(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    IdleCreditVault _strategy = IdleCreditVault(address(strategy));
    // request withdraw
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // do some intermediate deposits to check that everything works even when there are new deposits
    mintedAA = idleCDO.depositAA(amountWei);
    mintedBB = idleCDO.depositBB(amountWei / 2);

    uint256 requestedAA2 = cdoEpoch.requestWithdraw(0, address(AAtranche));
    uint256 requestedBB = cdoEpoch.requestWithdraw(0, address(BBtranche));

    // start epoch
    _startEpochAndCheckPrices(1);

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.claimWithdrawRequest();

    // we skip right before the end epoch
    vm.warp(block.timestamp + cdoEpoch.epochDuration() - 1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.claimWithdrawRequest();

    // stop epoch
    _stopEpochAndCheckPrices(1, initialProvidedApr, _expectedFundsEndEpoch());
    assertEq(_strategy.pendingWithdraws(), 0, 'wrong value of pendingWithdraw');

    uint256 balPre = IERC20Detailed(defaultUnderlying).balanceOf(address(this));
    uint256 strategyTokensPre = IERC20Detailed(strategyToken).balanceOf(address(this));

    cdoEpoch.claimWithdrawRequest();

    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(this)) - balPre, requestedAA1 + requestedAA2 + requestedBB, 'claimWithdrawRequest is wrong');
    assertEq(IERC20Detailed(address(AAtranche)).balanceOf(address(this)), 0, 'trancheToken bal is wrong for user');
    assertEq(_strategy.withdrawsRequests(address(this)), 0, 'withdrawsRequests is wrong');
    assertEq(strategyTokensPre - IERC20Detailed(strategyToken).balanceOf(address(this)), requestedAA1 + requestedAA2 + requestedBB, 'strategyToken bal is wrong for cdo');
  }

  function testClaimWithdrawRequestEpochRunning() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    
    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // request withdraw
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // start epoch
    _startEpochAndCheckPrices(1);
    // stop epoch
    _stopEpochAndCheckPrices(1, initialProvidedApr, _expectedFundsEndEpoch());

    // start another epoch
    _startEpochAndCheckPrices(2);

    // try to claim while epoch is running
    uint256 balPre = IERC20Detailed(defaultUnderlying).balanceOf(address(this));
    cdoEpoch.claimWithdrawRequest();

    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(this)) - balPre, requestedAA1, 'claimWithdrawRequest is wrong');
  }

  function testClaimWithdrawRequestWithInstantDefault() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    
    // run epoch 0 till the end
    _startEpochAndCheckPrices(0);
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // request normal withdraw
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // run epoch 0 till the end, with less apr so instant withdrawal are available
    _startEpochAndCheckPrices(1);
    _stopEpochAndCheckPrices(1, initialProvidedApr / 2, _expectedFundsEndEpoch());

    // request instant withdraw
    cdoEpoch.requestWithdraw(mintedAA / 3, address(AAtranche));

    _startEpochAndCheckPrices(2);
    // skip to instant withdraw deadline
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    // we don't deal funds to borrower so the pool will default on instant withdraw
    vm.prank(manager);
    cdoEpoch.getInstantWithdrawFunds();

    // stopEpoch will revert as isEpochRunning = false
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.stopEpoch(initialProvidedApr / 2, 0);

    uint256 balPre = IERC20Detailed(defaultUnderlying).balanceOf(address(this));
    // we try to claim the previous normal withdraw requests which should work
    cdoEpoch.claimWithdrawRequest();

    // user can only claim the first funds back as the second ones were
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(this)) - balPre, requestedAA1, 'claimWithdrawRequestAA is wrong');
  }

  function testClaimWithdrawRequestWithDefault() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);

    // deposit 10000 with user1
    address user1 = makeAddr('user1');
    _depositWithUser(user1, amountWei, true);
    uint256 balUser1 = underlying.balanceOf(user1);

    // request withdraw right away with user1
    vm.prank(user1);
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    // run epoch 0 till the end
    _startEpochAndCheckPrices(0);
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    // request normal withdraw with this contract
    cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // run epoch 0 till the end, with same apr but borrower defaults
    _startEpochAndCheckPrices(1);
    _stopEpochAndCheckPrices(1, initialProvidedApr, 0);

    // we try to claim the previous normal withdraw request but new epoch did not roll due to default
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.claimWithdrawRequest();

    // user1 can still withdraw
    vm.prank(user1);
    cdoEpoch.claimWithdrawRequest();
    assertGt(underlying.balanceOf(user1), balUser1, 'User 1 bal did not increase');
  }

  function testClaimInstantWithdrawRequest() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    uint256 mintedBB = idleCDO.depositBB(amountWei);
    
    // run epoch 0
    _startEpochAndCheckPrices(0);
    _stopEpochAndCheckPrices(0, initialProvidedApr / 2, _expectedFundsEndEpoch());

    IdleCreditVault _strategy = IdleCreditVault(address(strategy));
    // request instant withdraw (5000)
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // do some intermediate deposits to check that everything works even when there are new deposits
    // deposit 15000 with this contract
    mintedAA = idleCDO.depositAA(amountWei);
    mintedBB = idleCDO.depositBB(amountWei / 2);

    // deposit 10000 with user1
    address user1 = makeAddr('user1');
    _depositWithUser(user1, amountWei, false);

    // request another instant withdraw for the same tranche (5000)
    uint256 requestedAA2 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));
    // request instant withdraw for the other tranche (5000 + (10000 + interest))
    uint256 requestedBB = cdoEpoch.requestWithdraw(0, address(BBtranche));

    assertEq(IERC20Detailed(strategyToken).balanceOf(address(this)), requestedAA1 + requestedAA2 + requestedBB, 'strategyToken bal is wrong for user');
    // tot requested is 25000 + interest
    assertEq(_strategy.instantWithdrawsRequests(address(this)), requestedAA1 + requestedAA2 + requestedBB, 'instantWithdrawsRequests for user is wrong');

    // start epoch
    _startEpochAndCheckPrices(1);

    uint256 balPre = IERC20Detailed(defaultUnderlying).balanceOf(address(this));

    // can redeem right away because new deposits are enough to cover all instant withdraws
    cdoEpoch.claimInstantWithdrawRequest();

    assertEq(IERC20Detailed(strategyToken).balanceOf(address(this)), 0, 'user has no strategy tokens');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(this)) - balPre, requestedAA1 + requestedAA2 + requestedBB, 'claimInstantWithdrawRequest is wrong');
    assertEq(_strategy.instantWithdrawsRequests(address(this)), 0, 'instantWithdrawsRequests after claim is wrong');

    // we start a new epoch with less apr so instant withdrawal are available
    _stopEpochAndCheckPrices(1, initialProvidedApr / 4, _expectedFundsEndEpoch());
    // make instant redeem request for user1
    vm.startPrank(user1);
    uint256 requestedAAUser1 = cdoEpoch.requestWithdraw(0, address(BBtranche));
    vm.stopPrank();

    _startEpochAndCheckPrices(2);

    // user cannot claim right away because there are no underlyings available and funds must be 
    // requested from the borrower
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.claimInstantWithdrawRequest();

    // skip to instant withdraw deadline
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    // get pending instant withdraw funds from borrower
    _getInstantFunds();

    uint256 balUser1Pre = IERC20Detailed(defaultUnderlying).balanceOf(user1);

    // user can now claim
    vm.prank(user1);
    cdoEpoch.claimInstantWithdrawRequest();

    assertEq(IERC20Detailed(strategyToken).balanceOf(user1), 0, 'user1 has no strategy tokens');
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(user1) - balUser1Pre, requestedAAUser1, 'claimInstantWithdrawRequest for user1 is wrong');
    assertEq(_strategy.instantWithdrawsRequests(address(this)), 0, 'instantWithdrawsRequests after claim of user1 is wrong');
  }

  function testClaimInstantWithdrawRequestAfterAnEpoch() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    
    // run epoch 0
    _startEpochAndCheckPrices(0);
    _stopEpochAndCheckPrices(0, initialProvidedApr / 2, _expectedFundsEndEpoch());

    // request instant withdraw (5000)
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // run epoch 1 (same apr for the next one)
    _startEpochAndCheckPrices(1);
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    _getInstantFunds();
    // Here we could have claimed but we did not
    _stopEpochAndCheckPrices(1, initialProvidedApr / 2, _expectedFundsEndEpoch());

    // run epoch 2
    _startEpochAndCheckPrices(2);

    // claim right away as it was an old withdraw request
    uint256 balPre = IERC20Detailed(defaultUnderlying).balanceOf(address(this));
    cdoEpoch.claimInstantWithdrawRequest();
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(this)) - balPre, requestedAA1, 'claimInstantWithdrawRequest is wrong');
  }

  function testClaimInstantWithdrawRequestAfterAnEpochWithInstantWithdraw() external {
    vm.prank(owner);
    cdoEpoch.setFee(10000); // 10%

    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;

    // AARatio 50%
    uint256 mintedAA = idleCDO.depositAA(amountWei);
    
    // run epoch 0
    _startEpochAndCheckPrices(0);
    _stopEpochAndCheckPrices(0, initialProvidedApr / 2, _expectedFundsEndEpoch());

    // request instant withdraw (5000)
    uint256 requestedAA1 = cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // run epoch 1 (lower apr for the next one)
    _startEpochAndCheckPrices(1);
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    _getInstantFunds();
    // Here we could have claimed but we did not
    _stopEpochAndCheckPrices(1, initialProvidedApr / 4, _expectedFundsEndEpoch());

    // request another instant withdraw
    uint256 requestedAA2 = cdoEpoch.requestWithdraw(0, address(AAtranche));

    // run epoch 2
    _startEpochAndCheckPrices(2);
    // if we claim right away it reverts as there are pending instant not fulfilled
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.claimInstantWithdrawRequest();

    // we still need to wait the instant withdraw delay
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    _getInstantFunds();
    // claim right away as it was an old withdraw request
    uint256 balPre = IERC20Detailed(defaultUnderlying).balanceOf(address(this));
    cdoEpoch.claimInstantWithdrawRequest();
    assertEq(IERC20Detailed(defaultUnderlying).balanceOf(address(this)) - balPre, requestedAA1 + requestedAA2, 'claimInstantWithdrawRequest is wrong');
  }

  /// Tests inherited from TestIdleCDOBase/TestIdleCDOLossMgmt
  function _doDepositsWithInterest(uint256 aa, uint256 bb) 
    internal override
    returns (uint256 priceAA, uint256 priceBB) {
    idleCDO.depositAA(aa);
    idleCDO.depositBB(bb);

    _startEpochAndCheckPrices(0);
    _stopEpochAndCheckPrices(0, IdleCreditVault(address(strategy)).getApr(), _expectedFundsEndEpoch());

    priceAA = idleCDO.virtualPrice(address(AAtranche));
    priceBB = idleCDO.virtualPrice(address(BBtranche));
    assertGe(priceAA, ONE_SCALE - 1, 'AA price is >= 1');
    assertGe(priceBB, ONE_SCALE - 1, 'BB price is >= 1');
  }

  function testOnlyIdleCDO() public override {
    IdleCreditVault _strategy = IdleCreditVault(address(strategy));
    
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.requestWithdraw(1, address(1), 1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.claimWithdrawRequest(address(1));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.requestInstantWithdraw(1, address(1));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.claimInstantWithdrawRequest(address(1));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.collectInstantWithdrawFunds(1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.collectWithdrawFunds(1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.sendInterestAndDeposits(1);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _strategy.deposit(1);
  }

  function testAPRSplitRatioRedeems(
    uint16 _ratio,
    uint16 _redeemRatioAA,
    uint16 _redeemRatioBB
  ) external virtual override {
    vm.assume(_ratio <= 1000 && _ratio > 0);
    // > 0 because it's a requirement of the withdraw
    vm.assume(_redeemRatioAA <= 1000 && _redeemRatioAA > 0);
    vm.assume(_redeemRatioBB <= 1000 && _redeemRatioBB > 0);

    uint256 amount = 1000 * ONE_SCALE;
    // to have the same scale as FULL_ALLOC and avoid 
    // `Too many global rejects` error in forge
    uint256 ratio = uint256(_ratio) * 100; 
    uint256 amountAA = amount * ratio / FULL_ALLOC;
    uint256 amountBB = amount - amountAA;
    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);

    // Set new block.height to avoid reentrancy check on deposit/withdraw
    vm.roll(block.number + 1);

    uint256 ratioRedeemAA = uint256(_redeemRatioAA) * 100; 
    uint256 ratioRedeemBB = uint256(_redeemRatioBB) * 100; 
    amountAA = AAtranche.balanceOf(address(this)) * ratioRedeemAA / FULL_ALLOC;
    amountBB = BBtranche.balanceOf(address(this)) * ratioRedeemBB / FULL_ALLOC;
    if (amountAA > 0) {
      cdoEpoch.requestWithdraw(amountAA, address(AAtranche));
    }
    if (amountBB > 0) {
      cdoEpoch.requestWithdraw(amountBB, address(BBtranche));
    }
    
    assertApproxEqAbs(
      idleCDO.trancheAPRSplitRatio(), 
      _calcNewAPRSplit(idleCDO.getCurrentAARatio()), 
      2,
      "split ratio on redeem"
    );
  }

  function testRestoreOperations() external override {
    uint256 amount = 1000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // call with non owner
    vm.expectRevert(bytes("6"));
    vm.prank(address(0xbabe));
    idleCDO.restoreOperations();

    // call with owner
    vm.startPrank(owner);
    idleCDO.emergencyShutdown();
    idleCDO.restoreOperations();
    vm.stopPrank();

    vm.roll(block.number + 1);

    cdoEpoch.requestWithdraw(0, address(AAtranche));
    cdoEpoch.requestWithdraw(0, address(BBtranche));
    idleCDO.depositAA(0);
    idleCDO.depositBB(0);
  }

  function testEmergencyShutdown() external override {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // call with non owner
    vm.expectRevert(bytes("6"));
    vm.prank(address(0xbabe));
    idleCDO.emergencyShutdown();

    // call with owner
    vm.prank(owner);
    idleCDO.emergencyShutdown();

    vm.expectRevert(bytes("Pausable: paused")); // default
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("Pausable: paused")); // default
    idleCDO.depositBB(amount);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(amount, address(AAtranche));
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(amount, address(BBtranche));
  }

  function testCheckMaxDecreaseDefault() external override {
    uint256 amount = 10000 * ONE_SCALE;

    // AA Ratio 98%
    uint256 amountAA = amount - amount / 50;
    uint256 amountBB = amount - amountAA;
    _doDepositsWithInterest(amountAA, amountBB);
    uint256 newTVL = (
        IdleCDOTranche(address(AAtranche)).totalSupply() * idleCDO.virtualPrice(address(AAtranche)) / ONE_TRANCHE_TOKEN +
        IdleCDOTranche(address(BBtranche)).totalSupply() * idleCDO.virtualPrice(address(BBtranche)) / ONE_TRANCHE_TOKEN
    );
    uint256 interest = newTVL > amount ? newTVL - amountAA - amountBB : 0;

    // now let's simulate a loss by decreasing strategy price
    // curr price - 10%, this will trigger a default
    uint256 lossBps = IdleCDO(address(idleCDO)).maxDecreaseDefault() * 2;
    uint256 totLoss = (amount + interest) * lossBps / FULL_ALLOC;
    _createLoss(lossBps);

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost 100% as they need to cover seniors
    assertEq(0, postBBPrice, 'Full loss for junior tranche');
    // seniors are covered
    assertApproxEqAbs(
      (amountAA + amountBB + interest - totLoss) * ONE_SCALE / amountAA,
      postAAPrice,
      2,
      'AA price lost about 8% (2% covered by junior)'
    );

    // deposits/redeems are disabled
    vm.expectRevert(bytes("4"));
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.depositBB(amount);
    vm.expectRevert(bytes("4"));
    cdoEpoch.requestWithdraw(amount, address(AAtranche));
    vm.expectRevert(bytes("4"));
    cdoEpoch.requestWithdraw(amount, address(BBtranche));

    // distribute loss, as non owner
    vm.startPrank(makeAddr('nonOwner'));
    vm.expectRevert(bytes("6"));
    IdleCDO(address(idleCDO)).updateAccounting();
    vm.stopPrank();

    // effectively distribute loss
    vm.prank(idleCDO.owner());
    IdleCDO(address(idleCDO)).updateAccounting();

    assertEq(idleCDO.priceAA(), postAAPrice, 'AA saved price updated');
    assertEq(idleCDO.priceBB(), 0, 'BB saved price updated');
  }

  // @dev Loss is > maxDecreaseDefault and is absorbed by junior holders if possible
  function testDepositRedeemWithLossShutdown() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // AA Ratio is 98%
    idleCDO.depositAA(amount - amount / 50);
    idleCDO.depositBB(amount / 50);
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    _cdoHarvest(true);

    uint256 unclaimedFees = idleCDO.unclaimedFees();
    // now let's simulate a loss by decreasing strategy price
    // curr price - 5% + 1, this will trigger a default because the loss is >= junior tvl

    _createLoss(idleCDO.maxDecreaseDefault() + 1);

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));

    address newUser = address(0xcafe);
    _donateToken(newUser, amount * 2);
    // do another interaction to effectively update prices and trigger default
    vm.startPrank(newUser);
    // both deposits will revert as loss will accrue and leave 0 to juniors
    underlying.approve(address(idleCDO), amount * 2);
    vm.expectRevert(bytes("4"));
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.depositBB(amount);
    vm.expectRevert(bytes("4"));
    cdoEpoch.requestWithdraw(amount, address(AAtranche));
    vm.expectRevert(bytes("4"));
    cdoEpoch.requestWithdraw(amount, address(BBtranche));
    vm.stopPrank();

    vm.prank(idleCDO.owner());
    // This will set also allowAAWithdraw to true
    IdleCDO(address(idleCDO)).updateAccounting();
    // loss is now distributed and shutdown triggered
    uint256 postDepositAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postDepositBBPrice = idleCDO.virtualPrice(address(BBtranche));

    assertEq(postDepositAAPrice, postAAPrice, "AA price did not change after updateAccounting");
    assertEq(postDepositBBPrice, postBBPrice, "BB price did not change after updateAccounting");
    assertEq(idleCDO.priceAA(), postDepositAAPrice, "AA saved price updated");
    assertEq(idleCDO.priceBB(), postDepositBBPrice, "BB saved price updated");
    assertEq(idleCDO.unclaimedFees(), unclaimedFees, "Fees did not increase");
    assertEq(cdoEpoch.allowAAWithdrawRequest(), false, "allowAAWithdrawRequest set to true");
    assertEq(cdoEpoch.allowBBWithdrawRequest(), false, "allowBBWithdrawRequest set to true");
    assertEq(idleCDO.lastNAVBB(), 0, "Last junior TVL should be 0");

    // AA loss is 5% but 2% is covedered by junior (maxDelta 0.1% -> 1e15)
    assertApproxEqRel(postDepositAAPrice, preAAPrice - (preAAPrice * 3000 / FULL_ALLOC), 1e15, "AA price is equal after loss");
    // BB loss is 100% as they were only 2% of the total TVL
    assertApproxEqAbs(postDepositBBPrice, 0, 0, "BB price after loss");

    // deposits/redeems are disabled
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositAA(1);
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositBB(1);
    // expect revert NotAllowed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(0, address(BBtranche));
    // expect revert NotAllowed
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(0, address(AAtranche));
  }

  function testDepositWithLossSocialized(uint256 depositAmountAARatio) external override {
    vm.assume(depositAmountAARatio >= 0);
    vm.assume(depositAmountAARatio <= FULL_ALLOC);

    vm.prank(idleCDO.owner());
    idleCDO.setLossToleranceBps(500);

    uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
    uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);

    uint256 unclaimedFees = idleCDO.unclaimedFees();

    // deposit underlying to the strategy
    _cdoHarvest(true);
    uint256 lossPerc = idleCDO.lossToleranceBps() / 2;
    // now let's simulate a loss by decreasing strategy price
    // curr price - about 0.25%
    _createLoss(lossPerc);

    uint256 priceDelta = (lossPerc * ONE_SCALE) / FULL_ALLOC;
    uint256 lastNAVAA = idleCDO.lastNAVAA();
    uint256 currentAARatioScaled = lastNAVAA * ONE_SCALE / (idleCDO.lastNAVBB() + lastNAVAA);
    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));

    // Both junior and senior lost
    if (currentAARatioScaled > 0) {
      assertApproxEqAbs(postAAPrice, (preAAPrice * (ONE_SCALE - priceDelta)) / ONE_SCALE, 100, "AA price after loss");
    } else {
      assertApproxEqAbs(postAAPrice, preAAPrice, 1, "AA price not changed");
    }
    if (currentAARatioScaled < ONE_SCALE) {
      assertApproxEqAbs(postBBPrice, (preBBPrice * (ONE_SCALE - priceDelta)) / ONE_SCALE, 100, "BB price after loss");
    } else {
      assertApproxEqAbs(postBBPrice, preBBPrice, 1, "BB price not changed");
    }

    // seniors lost
    assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 0, "AA price not updated until new interaction");
    assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 0, "BB price not updated until new interaction");
    assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 0, "Fees did not increase");
  }

  function testDepositWithLossCovered() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // fee is set to 10% and release block period to 0
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 maxDecrease = idleCDO.maxDecreaseDefault();
    uint256 unclaimedFees = idleCDO.unclaimedFees();

    // now let's simulate a loss by decreasing strategy price
    // curr price - about 10%
    _createLoss(maxDecrease * 2);

    uint256 priceDelta = ((maxDecrease * 2) * 1e18) / FULL_ALLOC;
    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost about 20%(~= 2x priceDelta) as there were seniors to cover
    assertApproxEqAbs(postBBPrice, (preBBPrice * (1e18 - 2 * priceDelta)) / 1e18, 100, "BB price after loss");
    // seniors are covered
    assertApproxEqAbs(preAAPrice, postAAPrice, 1, "AA price unaffected");
    assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 1, "AA price not updated until new interaction");
    assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 1, "BB price not updated until new interaction");
    assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 1, "Fees did not increase");
  }

  function testRedeemWithLossCovered() external override {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    vm.prank(manager);
    IdleCreditVault(address(strategy)).setApr(0);

    // NOTE: forcely decrease the vault price
    // curr price - 10%
    _createLoss(idleCDO.maxDecreaseDefault() * 2);

    // redeem all
    uint256 resAA = cdoEpoch.requestWithdraw(0, address(AAtranche));
    uint256 resBB = cdoEpoch.requestWithdraw(0, address(BBtranche));

    assertApproxEqRel(resAA, amount, 0.0001 * 1e18, "AA request after loss is wrong"); // 1e18 == 100%
    // juniors lost about 5% as there were seniors to cover
    assertApproxEqRel(resBB, (amount * 80_000) / 100_000, 0.0001 * 1e18, "BB request after loss is wrong"); // 1e18 == 100%

    assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
    assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
    assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }
    // @dev Loss is between 0% and lossToleranceBps and is socialized
  function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external override {
    vm.assume(depositAmountAARatio >= 0);
    vm.assume(depositAmountAARatio <= FULL_ALLOC);

    vm.prank(idleCDO.owner());
    idleCDO.setLossToleranceBps(500);
    vm.prank(manager);
    IdleCreditVault(address(strategy)).setApr(0);

    uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
    uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;

    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);

    // now let's simulate a loss by decreasing strategy price
    // curr price - about 0.25%
    _createLoss(idleCDO.lossToleranceBps() / 2);

    uint256 priceDelta = ((idleCDO.lossToleranceBps() / 2) * ONE_SCALE) / FULL_ALLOC;
    uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));
    uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));

    // redeem all
    uint256 resAA;
    if (depositAmountAARatio > 0) {
      resAA = cdoEpoch.requestWithdraw(0, address(AAtranche));
    }

    uint256 resBB;
    if (depositAmountAARatio < FULL_ALLOC) {
      resBB = cdoEpoch.requestWithdraw(0, address(BBtranche));
    }

    if (depositAmountAARatio > 0) {
      assertApproxEqRel(
        resAA,
        amountAA * (ONE_SCALE - priceDelta) / ONE_SCALE, 
        10**14, 
        "AA amount after loss"
      );
      // Abs = 11 because min deposit for AA is 0.1 underlying (with depositAmountAARatio = 1)
      // and this can cause a price diff of up to 11 wei
      assertApproxEqAbs(priceAA, ONE_SCALE - priceDelta, 11, "AA price after loss");
    } else {
      assertApproxEqRel(resAA, amountAA, 1, "AA amount not changed");
    }

    if (depositAmountAARatio < FULL_ALLOC) {
      assertApproxEqRel(
        resBB, 
        (amountBB * (ONE_SCALE - priceDelta)) / ONE_SCALE, 
        10**14, 
        "BB amount after loss"
      );
      assertApproxEqAbs(priceBB, ONE_SCALE - priceDelta, 11, "BB price after loss");
    } else {
      assertApproxEqRel(resBB, amountBB, 1, "BB amount not changed");
    }

    assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
    assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
    assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  function testOnlyKeyringUsersCanInteract() external {
    address keyring = address(1);

    vm.prank(owner);
    cdoEpoch.setKeyringParams(keyring, 1, false);

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    idleCDO.depositAA(1e18);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    idleCDO.depositBB(1e18);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    vm.prank(owner);
    // allow request redeem even if checkCredential is false
    cdoEpoch.setKeyringParams(keyring, 1, true);
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    vm.clearMockedCalls();

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );

    idleCDO.depositAA(1);
    idleCDO.depositBB(1);
    cdoEpoch.requestWithdraw(0, address(AAtranche));

    vm.clearMockedCalls();
  }

  function testRequestOnlyInterest() external {
    uint256 amount = 100 * ONE_SCALE;
    uint256 trancheTokens = idleCDO.depositAA(amount);

    vm.startPrank(owner);
    cdoEpoch.setFee(10000); // 10%
    vm.stopPrank();

    // Set new block.height to avoid reentrancy check on deposit/withdraw
    vm.roll(block.number + 1);

    // calculate how much tranches tokens should be redeemed to 
    // get only *net* interest of principal deposited for next epoch
    uint256 currPrice = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 maxWithdrawable = cdoEpoch.maxWithdrawable(address(this), address(AAtranche));
    uint256 newPrice = maxWithdrawable * ONE_TRANCHE_TOKEN / trancheTokens;
    uint256 trancheTokensRequested = (newPrice - currPrice) * trancheTokens / newPrice;

    // calculate *net* interest for pending withdraw
    (uint256 interestPendingWithdraw,) = _calcInterestForTranche(address(AAtranche), trancheTokensRequested);
    
    uint256 interest = (newPrice - currPrice) * trancheTokens / ONE_TRANCHE_TOKEN;
    uint256 requested = cdoEpoch.requestWithdraw(trancheTokensRequested, address(AAtranche));
    assertApproxEqAbs(requested, interest, 1, "interest request is wrong");

    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch.
    _stopEpochAndCheckPrices(0, initialProvidedApr, _expectedFundsEndEpoch());

    uint256 balPre = underlying.balanceOf(address(this));
    cdoEpoch.claimWithdrawRequest();
    assertEq(underlying.balanceOf(address(this)) - balPre, requested, 'interest redeemed is wrong');

    // contract value will be eq to 
    // initial amount - requested amount + interest for the epoch + interest for pending withdraw
    assertEq(cdoEpoch.getContractValue(), amount - interest + cdoEpoch.lastEpochInterest() + interestPendingWithdraw, 'contract value is wrong');
  }

  function testClosePool() external {
    vm.startPrank(owner);
    cdoEpoch.setFee(10000); // 10%
    vm.stopPrank();

    IdleCDOEpochVariant _vault = IdleCDOEpochVariant(address(idleCDO));

    // deposit 10000 with this contract
    uint256 balThisPre = underlying.balanceOf(address(this));
    uint256 amountWei = 10000 * ONE_SCALE;
    uint256 mintedAA = idleCDO.depositAA(amountWei);

    // deposit 10000 with user1
    address user1 = makeAddr('user1');
    uint256 balUser1Pre = underlying.balanceOf(user1);
    _depositWithUser(user1, amountWei, true);

    // request a normal withdraw before starting epoch with this contract
    cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // start epoch
    _startEpochAndCheckPrices(0);
    // stop epoch
    _stopEpochAndCheckPrices(0, initialProvidedApr / 2, _expectedFundsEndEpoch());

    // request an instant withdraw to check that this also work
    vm.prank(user1);
    cdoEpoch.requestWithdraw(mintedAA / 2, address(AAtranche));

    // start epoch 1
    _startEpochAndCheckPrices(1);

    // borrower wants to close the pool so manager will set newApr = 0 and interest = 1 (special case indicating
    // that all funds should be paid back at stop epoch)
    address _manager = IdleCreditVault(_vault.strategy()).manager();
    uint256 totFunds = _expectedFundsEndEpoch() + _vault.getContractValue();
    uint256 _expectedInterest = cdoEpoch.expectedEpochInterest();
    uint256 fees = _expectedInterest * cdoEpoch.fee() / FULL_ALLOC;
    uint256 strategyTokensBalPre = IERC20Detailed(address(strategy)).balanceOf(address(_vault));
    uint256 AAPricePre = cdoEpoch.virtualPrice(address(AAtranche));

    // skip to instant withdraw deadline
    vm.warp(block.timestamp + cdoEpoch.instantWithdrawDelay() + 1);
    // get pending instant withdraw funds from borrower
    _getInstantFunds();

    // stop epoch
    deal(defaultUnderlying, borrower, totFunds);
    vm.startPrank(_manager);
    vm.warp(_vault.epochEndDate() + 1);
    _vault.stopEpoch(0, 1);
    vm.stopPrank();

    uint256 AAPricePos = cdoEpoch.virtualPrice(address(AAtranche));
    uint256 strategyTokensBalPost = IERC20Detailed(address(strategy)).balanceOf(address(_vault));
    assertApproxEqAbs(strategyTokensBalPost, strategyTokensBalPre + _expectedInterest - fees, 1, 'IdleCDO has wrong amount of strategyTokens');
    assertGt(AAPricePos, AAPricePre, 'AA price did not increase');
    assertApproxEqAbs(AAPricePos, 1.02e6, 0.01e6, 'AA price is wrong after stop epoch');

    assertApproxEqAbs(_vault.lastEpochInterest(), _expectedInterest - fees, 1, 'lastEpochInterest is wrong');
    assertEq(_vault.epochEndDate(), 0, 'epochEndDate is wrong');
    assertEq(_vault.allowInstantWithdraw(), true, 'allowInstantWithdraw is wrong');
    assertEq(_vault.epochDuration(), 0, 'epochDuration is wrong');
    assertEq(_vault.disableInstantWithdraw(), true, 'disableInstantWithdraw is wrong');

    // new epochs cannot be started
    vm.startPrank(_manager);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    _vault.startEpoch();
    vm.stopPrank();

    // request and claim with user1
    vm.startPrank(user1);
    cdoEpoch.requestWithdraw(0, address(AAtranche));
    cdoEpoch.claimWithdrawRequest();
    // claim also the prev instant request
    cdoEpoch.claimInstantWithdrawRequest();
    vm.stopPrank();
    assertGt(underlying.balanceOf(user1), balUser1Pre, 'Bal for user1 did not increase');

    // request and claim with this contract
    cdoEpoch.requestWithdraw(0, address(AAtranche));
    cdoEpoch.claimWithdrawRequest();
    assertGt(underlying.balanceOf(address(this)), balThisPre, 'Bal for this contract did not increase');
  }

  function testClosePoolWithUnderlyingInContract() external {
    vm.startPrank(owner);
    cdoEpoch.setFee(10000); // 10%
    vm.stopPrank();

    IdleCDOEpochVariant _vault = IdleCDOEpochVariant(address(idleCDO));
    address _manager = IdleCreditVault(_vault.strategy()).manager();

    // deposit 10000 with this contract
    idleCDO.depositAA(10000 * ONE_SCALE);

    // start epoch
    _startEpochAndCheckPrices(0);

    // calc the exact amount the borrower should pay when closing the epoch
    uint256 totFunds = _expectedFundsEndEpoch() + _vault.getContractValue();
    deal(defaultUnderlying, borrower, totFunds + 1);

    // 'maliciously' send underlyings to the contract to default the borrower
    deal(defaultUnderlying, address(_vault), 100);

    // stop epoch
    vm.startPrank(_manager);
    vm.warp(_vault.epochEndDate() + 1);
    _vault.stopEpoch(0, 1);
    vm.stopPrank();

    assertEq(_vault.defaulted(), false, 'borrower defaulted');
  }

  function testStopEpochWithDuration() external {
    vm.startPrank(owner);
    cdoEpoch.setFee(10000); // 10%
    vm.stopPrank();

    IdleCDOEpochVariant _vault = IdleCDOEpochVariant(address(idleCDO));
    address _manager = IdleCreditVault(_vault.strategy()).manager();
    uint256 bufferPeriodPre = _vault.bufferPeriod();

    // deposit 10000 with this contract
    idleCDO.depositAA(10000 * ONE_SCALE);

    // start epoch
    _startEpochAndCheckPrices(0);
    // give funds to borrower for repaying
    uint256 totFunds = _expectedFundsEndEpoch();
    deal(defaultUnderlying, borrower, totFunds);

    // stop epoch with new duration
    vm.startPrank(_manager);
    vm.warp(_vault.epochEndDate() + 1);
    _vault.stopEpochWithDuration(initialProvidedApr, 0, 3 days);
    vm.stopPrank();

    // check some params done in stopEpoch to see if called properly
    assertEq(IdleCreditVault(address(strategy)).getApr(), _scaleAprWithBuffer(initialProvidedApr), 'apr is wrong');
    assertEq(IdleCreditVault(address(strategy)).epochNumber(), 1, 'epochNumber is wrong');
    assertEq(_vault.isEpochRunning(), false, 'isEpochRunning is wrong');
    assertEq(_vault.expectedEpochInterest(), 0, 'expectedEpochInterest is wrong');
    assertEq(_vault.defaulted(), false, 'borrower defaulted');
    // check that epoch duration is updated
    assertEq(_vault.epochDuration(), 3 days, 'epoch duration is wrong');
    // check that bufferPeriod did not change
    assertEq(bufferPeriodPre, _vault.bufferPeriod(), 'buffer period changed');
  }

  function testSetAprs() external {
    IdleCreditVault cv = IdleCreditVault(address(strategy));

    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    cv.setAprs(1, 2);

    vm.prank(manager);
    cv.setAprs(3, 4);

    assertEq(cv.getApr(), 4, 'apr is wrong');
    assertEq(cv.unscaledApr(), 3, 'unscaledApr is wrong');
  }
}
