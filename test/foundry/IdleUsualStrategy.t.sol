// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {IdleUsualStrategy} from "../../contracts/strategies/usual/IdleUsualStrategy.sol";
import {IdleCDOUsualVariant} from "../../contracts/IdleCDOUsualVariant.sol";

interface IUSD0pp {
  function getFloorPrice() external view returns (uint256);
}

contract TestIdleUsualStrategy is TestIdleCDOLossMgmt {
  using stdStorage for StdStorage;

  uint256 internal constant ONE_TRANCHE = 1e18;
  address internal constant USD0pp = 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0;
  address internal constant USUAL = 0xC4441c2BE5d8fA8126822B9929CA0b81Ea0DE38E;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address internal defaultUnderlying = USD0pp;
  uint256 internal initialPrice;

  function _selectFork() public override {
    vm.createSelectFork("mainnet", 21767467);
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOUsualVariant();
  }

  function _deployStrategy(address _owner)
    internal
    override
    returns (address _strategy, address _underlying)
  {
    _underlying = defaultUnderlying;
    // strategyToken here is the staked strategy token (sdToken)
    strategy = new IdleUsualStrategy();
    strategyToken = IERC20Detailed(address(strategy));

    _strategy = address(strategy);

    // initialize
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    IdleUsualStrategy(_strategy).initialize(defaultUnderlying, _owner);

    initialPrice = IdleUsualStrategy(_strategy).oraclePrice();
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleUsualStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));

    bytes[] memory _extraPath = new bytes[](1);
    // Path for selling USUAL for USD0++ on univ3
    _extraPath[0] = abi.encodePacked(
      USUAL, uint24(10000), WETH, uint24(500), USDT, uint24(500), USD0pp
    );
    extraDataSell = abi.encode(_extraPath);
    extraData = '0x';
  }

  function _createLoss(uint256 _loss) internal override {
    // we simulate the loss by transferring out strategyTokens from the CDO
    uint256 strategyBal = strategyToken.balanceOf(address(idleCDO));
    uint256 lossUnderlyings = _loss * idleCDO.getContractValue() / FULL_ALLOC;
    vm.startPrank(address(idleCDO));
    if (strategyBal > 0) {
      strategyToken.transfer(address(1), lossUnderlyings);
    } else {
      underlying.transfer(address(1), lossUnderlyings);
    }
    vm.stopPrank();
  }

  function testCantReinitialize() external override {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    IdleUsualStrategy(address(strategy)).initialize(defaultUnderlying, owner);
  }

  function _cdoHarvest(bool _skipRewards) internal override {
    // Given that this CDO will get rewards only in the form of USUAL tokens
    // we send some USUAL tokens to the CDO at each harvest to simulate the tranche price increase
    deal(USUAL, address(idleCDO), 1e18);
    if (!IdleCDOUsualVariant(address(idleCDO)).isEpochRunning()) {
      return;
    }
    super._cdoHarvest(_skipRewards);
  }

  function _cdoHarvestRewards(uint256 _rewards) internal {
    // Given that this CDO will get rewards only in the form of USUAL tokens
    // we send some USUAL tokens to the CDO at each harvest to simulate the tranche price increase
    deal(USUAL, address(idleCDO), _rewards);
    super._cdoHarvest(false);
  }

  function testInitialize() public view override {
    IdleUsualStrategy _usualStrategy = IdleUsualStrategy(address(strategy));
    assertEq(idleCDO.token(), address(underlying));
    assertGe(strategy.price(), ONE_SCALE, 'strategy price is wrong');
    assertEq(idleCDO.tranchePrice(address(AAtranche)), ONE_SCALE, 'AA price is wrong');
    assertEq(idleCDO.tranchePrice(address(BBtranche)), ONE_SCALE, 'BB price is wrong');
    assertEq(initialAAApr, 0);
    assertEq(initialBBApr, initialApr);
    assertEq(idleCDO.unlentPerc(), 0, 'unlentPerc is wrong');
    assertEq(idleCDO.releaseBlocksPeriod(), 0, 'releaseBlocksPeriod is wrong');
    assertEq(idleCDO.maxDecreaseDefault(), 100_000, 'maxDecreaseDefault is wrong');
    assertEq(_usualStrategy.owner(), owner, 'owner is wrong');
    assertEq(_usualStrategy.decimals(), IERC20Detailed(USD0pp).decimals(), 'decimals are wrong');
    assertEq(_usualStrategy.symbol(), "idle_USD0++", 'symbol is wrong');
    assertEq(_usualStrategy.token(), USD0pp, 'token is wrong');

    assertEq(_usualStrategy.oraclePrice(), initialPrice, 'oraclePrice is wrong');
    address[] memory _rewards = strategy.getRewardTokens();
    assertEq(_rewards.length, 1, "rewards len");
    assertEq(_rewards[0], USUAL, "rewards[0] is USUAL");
  }

  function testSetOraclePrice() public {
    uint256 newPrice = 91e16; // 0.91$

    vm.startPrank(owner);
    IdleUsualStrategy(address(strategy)).setOraclePrice(newPrice);
    assertEq(IdleUsualStrategy(address(strategy)).oraclePrice(), newPrice);

    // if price is lt floorPrice, set it to floorPrice
    uint256 floorPrice = IUSD0pp(USD0pp).getFloorPrice();
    IdleUsualStrategy(address(strategy)).setOraclePrice(floorPrice - 1);
    assertEq(IdleUsualStrategy(address(strategy)).oraclePrice(), floorPrice);
    vm.stopPrank();
    
    // Non owner cannot set oraclePrice
    vm.expectRevert();
    IdleUsualStrategy(address(strategy)).setOraclePrice(newPrice);
  }

  function testDeposits() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    uint256 totAmount = amount * 2;

    assertEq(IERC20(AAtranche).balanceOf(address(this)), 10000 * 1e18, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, "BBtranche bal");
    assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal strategy");
    assertEq(underlying.balanceOf(address(idleCDO)), totAmount, "underlying bal cdo");
    // strategy is still empty with no harvest
    assertEq(strategyToken.balanceOf(address(idleCDO)), 0, "strategy bal cdo");

    uint256 strategyPrice = strategy.price();
    // check that trancheAPRSplitRatio and aprs are updated 
    assertApproxEqAbs(idleCDO.trancheAPRSplitRatio(), 25000, 1, "split ratio");

    // Strategy price will be the same until the end of the 'epoch'
    assertEq(strategy.price(), strategyPrice, "strategy price");

    // virtualPrice should be the same for AA tranche
    assertEq(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
    // virtualPrice should be the same for BB tranche
    assertEq(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");

    vm.prank(owner);
    IdleCDOUsualVariant(address(idleCDO)).startEpoch();

    // deposits are not allowed when epoch is running
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("Pausable: paused"));
    idleCDO.depositBB(amount);
  }

  function testStartEpoch() external {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    IdleCDOUsualVariant _idleCDO = IdleCDOUsualVariant(address(idleCDO));
    uint256 tvlPre = _idleCDO.getContractValue();
    uint256 oraclePrice = IdleUsualStrategy(address(strategy)).oraclePrice();

    vm.prank(makeAddr('nonOwner'));
    vm.expectRevert(bytes("6"));
    _idleCDO.startEpoch();

    // funds in lending
    vm.prank(owner);
    _idleCDO.startEpoch();

    // epoch is already running so cannot call startEpoch again
    vm.prank(owner);
    vm.expectRevert(bytes("9"));
    _idleCDO.startEpoch();

    assertEq(tvlPre, _idleCDO.getContractValue(), "tvl is the same");
    assertEq(_idleCDO.isEpochRunning(), true, "epoch is not running");
    assertEq(_idleCDO.paused(), true, "deposits paused");
    assertEq(_idleCDO.allowAAWithdraw(), false, "AA withdrawals paused");
    assertEq(_idleCDO.allowBBWithdraw(), false, "BB withdrawals paused");
    assertEq(_idleCDO.priceAtStartEpoch(), oraclePrice, 'price at start epoch is wrong');
    assertEq(IERC20Detailed(address(strategy)).balanceOf(address(_idleCDO)), tvlPre, 'strategyToken bal is wrong');

    vm.startPrank(owner);
    _idleCDO.stopEpoch();

    // epoch ended, cannot start a new epoch
    vm.expectRevert(bytes("9"));
    _idleCDO.startEpoch();
    vm.stopPrank();
  }

  function testStopEpoch() external {
    uint256 amount = 10000 * ONE_SCALE;
    uint256 mintedAA = idleCDO.depositAA(amount);
    uint256 mintedBB = idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    IdleCDOUsualVariant _idleCDO = IdleCDOUsualVariant(address(idleCDO));
    IdleUsualStrategy _strategy = IdleUsualStrategy(_idleCDO.strategy());
    uint256 tvlPre = _idleCDO.getContractValue();

    // check that lastNAVs are equal to the deposited amounts (strategy price is 1:1 with underlyings)
    uint256 navAA = _idleCDO.lastNAVAA();
    assertEq(navAA, amount, 'lastNAVAA is wrong');
    assertEq(_idleCDO.lastNAVBB(), amount, 'lastNAVBB is wrong');

    // epoch is not running so cannot stop an epoch
    vm.prank(owner);
    vm.expectRevert(bytes("9"));
    _idleCDO.stopEpoch();

    vm.prank(owner);
    _idleCDO.startEpoch();

    // harvest 10000 USUAL
    _cdoHarvestRewards(10000 * ONE_SCALE);
    // amount received after swap (logged) is 3216792005684096666858 -> 3216.79 usd0++
    uint256 usd0ppReceived = 3216792005684096666858;

    // check that tvl increased after harvest
    assertGt(_idleCDO.getContractValue(), tvlPre, "tvl did not increase");
    // AA price is unchanged
    assertEq(_idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price is wrong");
    assertEq(navAA, amount, 'lastNAVAA is wrong after harvest');
    // all yield goes to BB
    assertGt(_idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price is wrong");
    assertGt(_idleCDO.lastNAVBB(), amount, 'lastNAVBB is wrong after harvest');

    uint256 oraclePrice = IdleUsualStrategy(address(strategy)).oraclePrice();

    vm.prank(makeAddr('nonOwner'));
    vm.expectRevert(bytes("6"));
    _idleCDO.stopEpoch();

    vm.prank(owner);
    _idleCDO.stopEpoch();

    // cannot stop an epoch that is not running
    vm.prank(owner);
    vm.expectRevert(bytes("9"));
    _idleCDO.stopEpoch();

    // check that various parameters are set correctly
    assertEq(_strategy.oraclePrice(), oraclePrice, 'oraclePrice is wrong');
    assertEq(_idleCDO.isEpochRunning(), false, "epoch is running");
    assertEq(_idleCDO.paused(), true, "deposits not paused");
    assertEq(_idleCDO.allowAAWithdraw(), true, "AA withdrawals paused");
    assertEq(_idleCDO.allowBBWithdraw(), true, "BB withdrawals paused");

    // we now calculate what should be the amount of usd0++ that seniors should have in order
    // to have their initial deposits worth 1$ per usd0++
    uint256 targetTVLAA = navAA * ONE_SCALE / oraclePrice;
    assertEq(_idleCDO.lastNAVAA(), targetTVLAA, 'AA tvl after stopEpoch is wrong');
    assertEq(_idleCDO.virtualPrice(address(AAtranche)), targetTVLAA * ONE_SCALE / mintedAA, "AA virtual price is wrong after stopEpoch");

    // we now check junior tvl and price after the redistribution to seniors
    int256 juniorGain = int256(usd0ppReceived) - int256(targetTVLAA - navAA);
    assertGt(juniorGain, 0, 'Gain is not > 0');
    assertEq(_idleCDO.lastNAVBB(), uint256(int256(amount) + juniorGain), 'BB tvl after stopEpoch is wrong');
    assertEq(_idleCDO.virtualPrice(address(BBtranche)), uint256(int256(amount) + juniorGain) * ONE_SCALE / mintedBB, "BB virtual price is wrong after stopEpoch");
  }

  function testStopEpochWithFees() external {
    vm.prank(owner);
    idleCDO.setFee(10000); // 10%
    
    uint256 amount = 10000 * ONE_SCALE;
    uint256 mintedAA = idleCDO.depositAA(amount);
    uint256 mintedBB = idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    IdleCDOUsualVariant _idleCDO = IdleCDOUsualVariant(address(idleCDO));
    IdleUsualStrategy _strategy = IdleUsualStrategy(_idleCDO.strategy());
    uint256 tvlPre = _idleCDO.getContractValue();

    // check that lastNAVs are equal to the deposited amounts (strategy price is 1:1 with underlyings)
    uint256 navAA = _idleCDO.lastNAVAA();
    assertEq(navAA, amount, 'lastNAVAA is wrong');
    assertEq(_idleCDO.lastNAVBB(), amount, 'lastNAVBB is wrong');

    vm.prank(owner);
    _idleCDO.startEpoch();

    // harvest 10000 USUAL
    _cdoHarvestRewards(10000 * ONE_SCALE);
    // amount received after swap (logged) is 3216792005684096666858 -> 3216.79 usd0++
    uint256 usd0ppReceived = 3216792005684096666858;

    navAA += usd0ppReceived / 10;
    assertEq(IERC20Detailed(address(AAtranche)).balanceOf(idleCDO.feeReceiver()), usd0ppReceived / 10, "feeReceiver bal");

    // check that tvl increased after harvest
    assertGt(_idleCDO.getContractValue(), tvlPre, "tvl did not increase");
    // AA price is unchanged
    assertEq(_idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price is wrong");
    assertEq(_idleCDO.lastNAVAA(), navAA, 'lastNAVAA is wrong after harvest');
    // all yield goes to BB
    assertGt(_idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price is wrong");
    assertApproxEqAbs(_idleCDO.lastNAVBB(), amount + (usd0ppReceived * 9 / 10), 1, 'lastNAVBB is wrong after harvest');

    uint256 oraclePrice = IdleUsualStrategy(address(strategy)).oraclePrice();

    vm.prank(owner);
    _idleCDO.stopEpoch();

    // check that various parameters are set correctly
    assertEq(_strategy.oraclePrice(), oraclePrice, 'oraclePrice is wrong');
    assertEq(_idleCDO.isEpochRunning(), false, "epoch is running");
    assertEq(_idleCDO.paused(), true, "deposits not paused");
    assertEq(_idleCDO.allowAAWithdraw(), true, "AA withdrawals paused");
    assertEq(_idleCDO.allowBBWithdraw(), true, "BB withdrawals paused");

    // we now calculate what should be the amount of usd0++ that seniors should have in order
    // to have their initial deposits worth 1$ per usd0++
    uint256 targetTVLAA = navAA * ONE_SCALE / oraclePrice;
    assertEq(_idleCDO.lastNAVAA(), targetTVLAA, 'AA tvl after stopEpoch is wrong');
    assertEq(_idleCDO.virtualPrice(address(AAtranche)), targetTVLAA * ONE_SCALE / (mintedAA + usd0ppReceived / 10), "AA virtual price is wrong after stopEpoch");

    // we now check junior tvl and price after the redistribution to seniors
    int256 juniorGain = int256(usd0ppReceived * 9 / 10) - int256(targetTVLAA - navAA);
    assertGt(juniorGain, 0, 'Gain is not > 0');
    assertApproxEqAbs(_idleCDO.lastNAVBB(), uint256(int256(amount) + juniorGain), 1, 'BB tvl after stopEpoch is wrong');
    assertEq(_idleCDO.virtualPrice(address(BBtranche)), uint256(int256(amount) + juniorGain) * ONE_SCALE / mintedBB, "BB virtual price is wrong after stopEpoch");
  }

  function testStopEpochJuniorLoss() external {
    uint256 amount = 10000 * ONE_SCALE;
    uint256 mintedAA = idleCDO.depositAA(amount);
    uint256 mintedBB = idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    IdleCDOUsualVariant _idleCDO = IdleCDOUsualVariant(address(idleCDO));
    uint256 navAA = _idleCDO.lastNAVAA();

    vm.prank(owner);
    _idleCDO.startEpoch();

    // harvest 10 USUAL, not enough to cover seniors
    _cdoHarvestRewards(10 * ONE_SCALE);
    // // amount received after swap (logged) is 3226706373470944153 -> 3.22 usd0++
    uint256 usd0ppReceived = 3226706373470944153;

    // AA price is unchanged
    assertEq(_idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price is wrong");
    assertEq(navAA, amount, 'lastNAVAA is wrong after harvest');
    // all yield goes to BB
    assertGt(_idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price is wrong");
    assertGt(_idleCDO.lastNAVBB(), amount, 'lastNAVBB is wrong after harvest');

    uint256 oraclePrice = IdleUsualStrategy(address(strategy)).oraclePrice();

    vm.prank(owner);
    _idleCDO.stopEpoch();

    // we now calculate what should be the amount of usd0++ that seniors should have in order
    // to have their initial deposits worth 1$ per usd0++
    uint256 targetTVLAA = navAA * ONE_SCALE / oraclePrice;
    assertEq(_idleCDO.lastNAVAA(), targetTVLAA, 'AA tvl after stopEpoch is wrong');
    assertEq(_idleCDO.virtualPrice(address(AAtranche)), targetTVLAA * ONE_SCALE / mintedAA, "AA virtual price is wrong after stopEpoch");

    // we now check junior tvl and price after the redistribution to seniors
    int256 juniorGain = int256(usd0ppReceived) - int256(targetTVLAA - navAA);
    assertLt(juniorGain, 0, 'Loss is not > 0');
    assertEq(_idleCDO.lastNAVBB(), uint256(int256(amount) + juniorGain), 'BB tvl after stopEpoch is wrong');
    assertEq(_idleCDO.virtualPrice(address(BBtranche)), uint256(int256(amount) + juniorGain) * ONE_SCALE / mintedBB, "BB virtual price is wrong after stopEpoch");
  }

  function testRedeems() external override {
    IdleCDOUsualVariant _idleCDO = IdleCDOUsualVariant(address(idleCDO));

    uint256 amount = 10000 * ONE_SCALE;
    _idleCDO.depositAA(amount);
    _idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    vm.roll(block.number + 1);

    vm.prank(owner);
    _idleCDO.startEpoch();

    // cannot redeem during epoch
    vm.expectRevert(bytes("3"));
    _idleCDO.withdrawAA(0);
    vm.expectRevert(bytes("3"));
    _idleCDO.withdrawBB(0);
    
    uint256 oraclePrice = IdleUsualStrategy(address(strategy)).oraclePrice();

    vm.prank(owner);
    _idleCDO.stopEpoch();

    // there were no USUAL harvests so junior will be at a loss

    // redeem all AA
    uint256 targetTVLAA = amount * ONE_SCALE / oraclePrice;
    assertGt(targetTVLAA, amount, 'AA should redeem more than deposited');
    uint256 resAA = idleCDO.withdrawAA(0);
    assertApproxEqRel(
      resAA, 
      targetTVLAA, 
      0.0000000001e18,
      'AA did not redeemed all'
    );

    uint256 bbTvl = amount - (targetTVLAA - amount);
    uint256 resBB = idleCDO.withdrawBB(0);
    assertApproxEqRel(
      resBB, 
      bbTvl,
      0.0000000001e18,
      'BB did not redeem all'
    );
  }

  function testRedeemsWithJuniorGain() external {
    IdleCDOUsualVariant _idleCDO = IdleCDOUsualVariant(address(idleCDO));

    uint256 amount = 10000 * ONE_SCALE;
    _idleCDO.depositAA(amount);
    _idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    vm.roll(block.number + 1);

    vm.prank(owner);
    _idleCDO.startEpoch();

    _cdoHarvestRewards(10000 * ONE_SCALE);
    uint256 usd0ppReceived = 3216792005684096666858;


    uint256 oraclePrice = IdleUsualStrategy(address(strategy)).oraclePrice();

    vm.prank(owner);
    _idleCDO.stopEpoch();

    // redeem all AA
    uint256 targetTVLAA = amount * ONE_SCALE / oraclePrice;
    assertGt(targetTVLAA, amount, 'AA should redeem more than deposited');
    uint256 resAA = idleCDO.withdrawAA(0);
    assertApproxEqRel(
      resAA, 
      targetTVLAA, 
      0.0000000001e18,
      'AA did not redeemed all'
    );

    uint256 bbTvl = amount - (targetTVLAA - amount) + usd0ppReceived;
    uint256 resBB = idleCDO.withdrawBB(0);
    assertApproxEqRel(
      resBB, 
      bbTvl,
      0.0000000001e18,
      'BB did not redeem all'
    );
  }

  function testRedeemsWithoutWaiting() external {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    vm.roll(block.number + 1);

    // redeem all without waiting for the start epoch
    // no one should gain anything until epoch is started
    uint256 resAA = idleCDO.withdrawAA(0);
    assertEq(resAA, amount, 'AA gained something');

    uint256 resBB = idleCDO.withdrawBB(0);
    assertEq(resBB, amount, 'BB gained something');
  
    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
    assertEq(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  // @dev Loss is > maxDecreaseDefault and is absorbed by junior holders if possible
  function testDepositRedeemWithLossShutdown() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // AA Ratio is 98%
    idleCDO.depositAA(amount - amount / 50);
    idleCDO.depositBB(amount / 50);
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    // uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));
    _cdoHarvest(true);

    vm.roll(block.number + 1);

    uint256 unclaimedFees = idleCDO.unclaimedFees();
    // now let's simulate a loss by decreasing strategy price
    // curr price - 5%, this will trigger a default because the loss is >= junior tvl
    _createLoss(5000);

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
    idleCDO.withdrawAA(amount);
    vm.expectRevert(bytes("4"));
    idleCDO.withdrawBB(amount);
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
    assertEq(idleCDO.allowAAWithdraw(), true, "Default flag for senior set to true regardless");
    assertEq(idleCDO.allowBBWithdraw(), false, "Default flag for senior set");
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
    vm.expectRevert(bytes("3"));
    idleCDO.withdrawBB(0);

    // AA withdraw is allowed
    idleCDO.withdrawAA(0);
  }

  function testDepositWithLossCovered() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // fee is set to 10% and release block period to 0
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 unclaimedFees = idleCDO.unclaimedFees();

    // deposit underlying to the strategy
    _cdoHarvest(true);
    // now let's simulate a loss by decreasing strategy price
    // curr price - about 2.5%
    uint256 loss = 2500; // in % with 100_000 = 100%
    _createLoss(loss);

    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
    // juniors lost about 5%(~= 2x priceDelta) as there were seniors to cover
    assertApproxEqAbs(postBBPrice, 9.5e17, 100, "BB price after loss");
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
    _transferBurnedTrancheTokens(address(this), true);
    _transferBurnedTrancheTokens(address(this), false);

    // funds in lending
    _cdoHarvest(true);

    vm.roll(block.number + 1);

    // NOTE: forcely decrease the vault price
    // curr price - 2.5%
    uint256 loss = 2500; // in % with 100_000 = 100%
    _createLoss(loss);

    // redeem all
    uint256 resAA = idleCDO.withdrawAA(0);
    uint256 resBB = idleCDO.withdrawBB(0);

    assertApproxEqRel(resAA, amount, 0.0001 * 1e18, "AA price after loss"); // 1e18 == 100%
    // juniors lost about 5% as there were seniors to cover
    assertApproxEqRel(resBB, (amount * 95_000) / 100_000, 0.0001 * 1e18, "BB price after loss"); // 1e18 == 100%

    assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
    assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
    assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  function testCheckMaxDecreaseDefault() external override {
    // Overridden and not used
  }
  function testMinStkIDLEBalance() external override {
    // Overridden and not used
  }
  function testDepositWithLossSocialized(uint256 depositAmountAARatio) external override {
    // Overridden as loss is never socialized
  }
  function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external override {
    // Overridden as loss is never socialized
  }

  function _testRedeemRewardsInternal() internal override {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    // epoch not started
    vm.expectRevert(bytes("9"));
    _cdoHarvest(false);

    vm.prank(owner);
    IdleCDOUsualVariant(address(idleCDO)).startEpoch();

    // sell some rewards
    uint256 pricePre = idleCDO.virtualPrice(address(AAtranche));
    _cdoHarvestRewards(100 * ONE_SCALE);

    uint256 pricePost = idleCDO.virtualPrice(address(AAtranche));
    assertGt(pricePost, pricePre, "virtual price increased");
  }
}
