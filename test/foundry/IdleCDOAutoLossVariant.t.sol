// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/ICToken.sol";
import "../../contracts/strategies/idle/IdleStrategy.sol";
import "../../contracts/IdleCDOAutoLossVariant.sol";
import "./TestIdleCDOBase.sol";

// NOTE: IMPORTANT tests are made at block 16368877 where idleUSDC had all deposited in compound
// this is crucial for the test as to mock a default we decrease `exchangeRateStored` of the corresponding
// cToken associated with the idleToken. If another block is used make sure to mock the correct call.
// It's not enough to mock strategy.price() otherwise on redeems the wrong number of strategyTokens will be burned

contract TestIdleCDOAutoLossVariant is TestIdleCDOBase {
  using stdStorage for StdStorage;
  using SafeERC20Upgradeable for IERC20Detailed;

  // Idle-USDC Best-Yield v4
  address internal constant UNDERLYING = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant idleToken = 0x5274891bEC421B39D23760c04A6755eCB444797C;
  // NOTE check *NOTE* at beginning of the contract
  address internal constant cToken = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;

  function _selectFork() public override {
    // IdleUSDC deposited all in compund
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16368877));
  }

  function _deployLocalContracts() internal override returns (IdleCDO _cdo) {
    address _owner = address(0xdeadbad);
    address _rebalancer = address(0xbaddead);
    (address _strategy, address _underlying) = _deployStrategy(_owner);

    // deploy idleCDO and tranches
    _cdo = _deployCDO();
    stdstore.target(address(_cdo)).sig(_cdo.token.selector).checked_write(address(0));
    address[] memory incentiveTokens = new address[](0);
    _cdo.initialize(
      0,
      _underlying,
      address(this), // governanceFund,
      _owner, // owner,
      _rebalancer, // rebalancer,
      _strategy, // strategy
      20000, // apr split
      0, // deprecated
      incentiveTokens
    );

    vm.startPrank(_owner);
    _cdo.setUnlentPerc(0);
    _cdo.setFee(0);
    _cdo.setIsAYSActive(true);
    vm.stopPrank();

    _postDeploy(address(_cdo), _owner);
  }

  function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
    _underlying = UNDERLYING;
    underlying = IERC20Detailed(_underlying);
    strategy = new IdleStrategy();
    _strategy = address(strategy);
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    IdleStrategy(_strategy).initialize(idleToken, _owner);
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOAutoLossVariant();
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function _pokeLendingProtocol() internal override {
    ICToken(cToken).accrueInterest();
  }

  // ###################################
  // ############ TESTS ################
  // ###################################

  function testInitialize() public override {
    super.testInitialize();
    assertEq(IdleCDOAutoLossVariant(address(idleCDO)).maxDecreaseDefault(), 5000);
  }

  function testOnlyIdleCDO() public override runOnForkingNetwork(MAINNET_CHIANID) {}

  function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
      vm.expectRevert(bytes("Initializable: contract is already initialized"));
      IdleStrategy(address(strategy)).initialize(idleToken, owner);
  }

  function testDepositWithLossCovered() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    // fee is set to 10% and release block period to 0
    (uint256 preAAPrice, uint256 preBBPrice) = _doDepositsWithInterest(amount, amount);

    uint256 currPrice = strategy.price();
    uint256 maxDecrease = IdleCDOAutoLossVariant(address(idleCDO)).maxDecreaseDefault();
    uint256 unclaimedFees = idleCDO.unclaimedFees();
    // now let's simulate a loss by decreasing strategy price
    // curr price - 5%
    vm.mockCall(
      address(strategy),
      abi.encodeWithSelector(IIdleCDOStrategy.price.selector),
      abi.encode(currPrice * (FULL_ALLOC - maxDecrease) / FULL_ALLOC)
    );

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost about 10% as there were seniors to cover
    assertApproxEqAbs(
      preBBPrice * 90000/100000,
      postBBPrice, 
      200 // 200 wei to account for interest accrued
    );
    // seniors are covered
    assertEq(preAAPrice, postAAPrice, 'AA price unaffected');
    assertEq(idleCDO.priceAA(), preAAPrice, 'AA price not updated until new interaction');
    assertEq(idleCDO.priceBB(), preBBPrice, 'BB price not updated until new interaction');

    _depositWithUser(idleCDO.rebalancer(), amount, true);
    _depositWithUser(idleCDO.rebalancer(), amount, false);

    uint256 postDepositAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postDepositBBPrice = idleCDO.virtualPrice(address(BBtranche));

    assertEq(postDepositAAPrice, postAAPrice, 'AA price did not change after deposit');
    assertEq(postDepositBBPrice, postBBPrice, 'BB price did not change after deposit');
    assertEq(idleCDO.priceAA(), postDepositAAPrice, 'AA saved price updated');
    assertEq(idleCDO.priceBB(), postDepositBBPrice, 'BB saved price updated');

    assertEq(idleCDO.unclaimedFees(), unclaimedFees, 'Fees did not increase');
    vm.clearMockedCalls();
  }

  function testRedeemWithLossCovered() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 maxDecrease = IdleCDOAutoLossVariant(address(idleCDO)).maxDecreaseDefault();
    uint256 amount = 10000 * ONE_SCALE;
    // fee is set to 10% and release block period to 0, AARatio 66%
    (uint256 preAAPrice, uint256 preBBPrice) = _doDepositsWithInterest(amount * 2, amount);

    // now let's simulate a loss by decreasing cToken price (so to decrease strategy.price), curr price - 5%
    vm.mockCall(
      address(cToken),
      abi.encodeWithSelector(ICToken.exchangeRateStored.selector),
      abi.encode(ICToken(cToken).exchangeRateStored() * (FULL_ALLOC - maxDecrease) / FULL_ALLOC)
    );

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost about 15% as there were 2x seniors to cover
    assertApproxEqAbs(
      postBBPrice, 
      preBBPrice * 85000/100000,
      1000, // 1000 wei to account for interest accrued
      'BB price decreased'
    );
    // seniors are covered
    assertEq(preAAPrice, postAAPrice, 'AA price unaffected');
    uint256 balPre = underlying.balanceOf(address(this));
    // we redeem half of the balance to avoid having only feeReceiver as AA holders
    // otherwise any leftover will easily push AA price up
    idleCDO.withdrawAA(AAtranche.balanceOf(address(this)) / 2);
    uint256 balPost = underlying.balanceOf(address(this));
    assertGt(balPost - balPre, amount, 'AA gained something as loss was totally covered');

    // senior v price should be equal to the one before or at most 1 wei greater due to rounding
    assertApproxEqAbs(
      idleCDO.virtualPrice(address(AAtranche)), postAAPrice, 1, 
      'AA price after withdraw did not change or increased'
    );
    assertGe(idleCDO.virtualPrice(address(AAtranche)), postAAPrice, 'AA price after withdraw did not change or increased');
    // junior v price should be unchanged
    assertEq(idleCDO.virtualPrice(address(BBtranche)), postBBPrice, 'BB price after withdraw did not change');

    // junior lost about 15%
    idleCDO.withdrawBB(BBtranche.balanceOf(address(this)));
    uint256 balPostPost = underlying.balanceOf(address(this));
    assertApproxEqRel(
      balPostPost - balPost, 
      amount * 85000/100000, // lost 15% - interest accrued (about 0.2%)
      3e15, // 0.3% tolerance
      'BB lost 10% (minus interest accrued)'
    );

    vm.clearMockedCalls();
  }

  function testDepositRedeemWithLossShutdown() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    // fee is set to 10% and release block period to 0

    // AA Ratio 98%
    (uint256 preAAPrice, uint256 preBBPrice) = _doDepositsWithInterest(amount - amount / 50, amount / 50);

    uint256 currPrice = strategy.price();
    uint256 maxDecrease = IdleCDOAutoLossVariant(address(idleCDO)).maxDecreaseDefault();
    uint256 unclaimedFees = idleCDO.unclaimedFees();
    // now let's simulate a loss by decreasing strategy price
    // curr price - 5%, this will trigger a default because the loss is >= junior tvl
    vm.mockCall(
      address(strategy),
      abi.encodeWithSelector(IIdleCDOStrategy.price.selector),
      abi.encode(currPrice * (FULL_ALLOC - maxDecrease) / FULL_ALLOC)
    );

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost 100% as they need to cover seniors
    assertEq(0, postBBPrice, 'Full loss for junior tranche');
    // seniors are covered
    assertApproxEqAbs(
      preAAPrice * 97000/100000,
      postAAPrice, 
      1000, // 1000 wei to account for interest accrued
      'AA price lost about 3% (2% covered by junior)'
    );
    assertEq(idleCDO.priceAA(), preAAPrice, 'AA price not updated until new interaction');
    assertEq(idleCDO.priceBB(), preBBPrice, 'BB price not updated until new interaction');

    address newUser = address(123456);
    deal(address(underlying), newUser, amount * 2);
    // do another interaction to effectively update prices and trigger default
    vm.startPrank(newUser);
    // both deposits will revert as loss will accrue and leave 0 to juniors
    underlying.approve(address(idleCDO), amount * 2);
    vm.expectRevert(bytes("4"));
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.depositBB(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.withdrawAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.withdrawBB(amount);
    vm.stopPrank();

    vm.prank(idleCDO.owner());
    IdleCDOAutoLossVariant(address(idleCDO)).updateAccounting();
    // loss is now distributed and shutdown triggered

    uint256 postDepositAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postDepositBBPrice = idleCDO.virtualPrice(address(BBtranche));

    assertEq(postDepositAAPrice, postAAPrice, 'AA price did not change after deposit');
    assertEq(postDepositBBPrice, postBBPrice, 'BB price did not change after deposit');
    assertEq(idleCDO.priceAA(), postDepositAAPrice, 'AA saved price updated');
    assertEq(idleCDO.priceBB(), postDepositBBPrice, 'BB saved price updated');
    assertEq(idleCDO.unclaimedFees(), unclaimedFees, 'Fees did not increase');
    assertEq(idleCDO.allowAAWithdraw(), false, 'Default flag for senior set');
    assertEq(idleCDO.allowBBWithdraw(), false, 'Default flag for senior set');
    assertEq(idleCDO.lastNAVBB(), IERC20Detailed(address(BBtranche)).totalSupply() / 1e18, 'Default flag for senior set');

    // deposits/redeems are disabled
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositBB(amount);
    vm.expectRevert(bytes("3"));
    idleCDO.withdrawAA(amount);
    vm.expectRevert(bytes("3"));
    idleCDO.withdrawBB(amount);

    vm.clearMockedCalls();
  }

  function testCheckMaxDecreaseDefault() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    // fee is set to 10% and release block period to 0

    // AA Ratio 98%
    (uint256 preAAPrice, ) = _doDepositsWithInterest(amount - amount / 50, amount / 50);

    uint256 currPrice = strategy.price();
    uint256 maxDecrease = IdleCDOAutoLossVariant(address(idleCDO)).maxDecreaseDefault();
    // now let's simulate a loss by decreasing strategy price
    // curr price - 10%, this will trigger a default
    vm.mockCall(
      address(strategy),
      abi.encodeWithSelector(IIdleCDOStrategy.price.selector),
      abi.encode(currPrice * (FULL_ALLOC - maxDecrease * 2) / FULL_ALLOC)
    );

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost 100% as they need to cover seniors
    assertEq(0, postBBPrice, 'Full loss for junior tranche');
    // seniors are covered
    assertApproxEqAbs(
      preAAPrice * 92000/100000,
      postAAPrice, 
      2000, // 2000 wei to account for interest accrued
      'AA price lost about 8% (2% covered by junior)'
    );

    // deposits/redeems are disabled
    vm.expectRevert(bytes("4"));
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.depositBB(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.withdrawAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.withdrawBB(amount);

    // distribute loss, as non owner
    vm.startPrank(address(232323));
    vm.expectRevert(bytes("6"));
    IdleCDOAutoLossVariant(address(idleCDO)).updateAccounting();
    vm.stopPrank();
  
    // effectively distribute loss
    vm.prank(idleCDO.owner());
    IdleCDOAutoLossVariant(address(idleCDO)).updateAccounting();

    assertEq(idleCDO.priceAA(), postAAPrice, 'AA saved price updated');
    assertEq(idleCDO.priceBB(), 0, 'BB saved price updated');

    vm.clearMockedCalls();
  }

  function _depositWithUser(address _user, uint256 _amount, bool _isAA) internal {
    deal(address(underlying), _user, _amount * 2);
    // do another interaction to effectively update prices
    vm.startPrank(_user);
    underlying.safeIncreaseAllowance(address(idleCDO), _amount);
    if (_isAA) {
      idleCDO.depositAA(_amount);
    } else {
      idleCDO.depositBB(_amount);
    }
    vm.stopPrank();
    vm.roll(block.number + 1);
  }

  function _doDepositsWithInterest(uint256 aa, uint256 bb) 
    internal 
    returns (uint256 priceAA, uint256 priceBB) {
    vm.startPrank(owner);
    idleCDO.setReleaseBlocksPeriod(0);
    idleCDO.setFee(10000);
    vm.stopPrank();

    idleCDO.depositAA(aa);
    idleCDO.depositBB(bb);

    // deposit underlyings to the strategy
    _cdoHarvest(true);
    // accrue some interest 
    skip(30 days);
    vm.roll(block.number + 30 * 7200); // 7 days in blocks, needed for compound
    // claim and sell rewards
    _cdoHarvest(false);
    vm.roll(block.number + 1); // 7 days in blocks

    priceAA = idleCDO.virtualPrice(address(AAtranche));
    priceBB = idleCDO.virtualPrice(address(BBtranche));
    assertGt(priceAA, ONE_SCALE, 'AA price is > 1');
    assertGt(priceBB, ONE_SCALE, 'BB price is > 1');
  }
}
