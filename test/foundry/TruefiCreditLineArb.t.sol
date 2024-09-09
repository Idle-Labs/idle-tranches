// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {TruefiCreditLineStrategy} from "../../contracts/arbitrum/strategies/truefi/TruefiCreditLineStrategy.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";
import {IdleCDOTruefiCreditVariant} from "../../contracts/arbitrum/IdleCDOTruefiCreditVariant.sol";
import {ITruefiCreditLine} from "../../contracts/arbitrum/interfaces/truefi/ITruefiCreditLine.sol";
import {IWETH} from "../../contracts/interfaces/IWETH.sol";
import {IIdleCDO} from "../../contracts/interfaces/IIdleCDO.sol";
import {IIdleCDOStrategy} from "../../contracts/interfaces/IIdleCDOStrategy.sol";

contract TestTruefiCreditLineArb is TestIdleCDOLossMgmt {
  using stdStorage for StdStorage;

  uint256 internal constant ONE_TRANCHE = 1e18;
  address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  address internal constant tfWIN_USDC = 0xA909a4AA2A6DB0C1A3617A5Cf763ae0d780E5C64;

  address internal defaultUnderlying = USDC;
  IERC4626Upgradeable internal defaultVault = IERC4626Upgradeable(tfWIN_USDC);

  function _selectFork() public override {
    vm.createSelectFork("arbitrum", 238377606);
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOTruefiCreditVariant();
  }

  function _deployStrategy(address _owner)
    internal
    override
    returns (address _strategy, address _underlying)
  {
    _underlying = defaultUnderlying;
    strategyToken = IERC20Detailed(address(defaultVault));
    strategy = new TruefiCreditLineStrategy();

    _strategy = address(strategy);

    // initialize
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    TruefiCreditLineStrategy(_strategy).initialize(address(defaultVault), defaultUnderlying, _owner);
  }

  function _pokeLendingProtocol() internal override {
    // do a deposit to update lastQuotaRevenueUpdate and lastBaseInterestUpdate
    ITruefiCreditLine tf = ITruefiCreditLine(address(defaultVault));
    address user = makeAddr('rando');
    uint256 amount = 10 ** (IERC20Detailed(defaultUnderlying).decimals());
    deal(defaultUnderlying, user, amount, true);

    vm.startPrank(user);
    IERC20Detailed(defaultUnderlying).approve(address(defaultVault), amount);
    IERC4626Upgradeable(address(tf)).deposit(amount, user);
    vm.stopPrank();
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    TruefiCreditLineStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    // set directDeposit to false to avoid small differences in apr
    stdstore.target(address(_cdo)).sig(IIdleCDO(address(_cdo)).directDeposit.selector).checked_write(false);

    _pokeLendingProtocol();
  }

  function _donateToken(address to, uint256 amount) internal override {
    if (defaultUnderlying == WETH) {
      address maker = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
      uint256 bal = underlying.balanceOf(maker);
      require(bal > amount, "doesn't have enough tokens");
      vm.prank(maker);
      underlying.transfer(to, amount);
    } else {
      deal(defaultUnderlying, to, amount);
    }
  }

  function _createLoss(uint256 _loss) internal override {
    // set fees to 0 to ease calculations
    uint256 fee = 0;
    ITruefiCreditLine tf = ITruefiCreditLine(address(defaultVault));
    stdstore.target(address(tf)).sig(tf.lastProtocolFeeRate.selector).checked_write(fee);
    stdstore.target(address(tf)).sig(tf.unpaidFee.selector).checked_write(fee);

    // vault is using virtualTokenBalance so we need to update that for a loss
    uint256 totalAssets = defaultVault.totalAssets();
    uint256 loss = totalAssets * _loss / FULL_ALLOC;
    // Set virtualTokenBalance storage variable to simulate a loss
    uint256 currVirtual = tf.virtualTokenBalance();
    require(currVirtual >= loss, "test: loss is too large");
    stdstore.target(address(tf)).sig(tf.virtualTokenBalance.selector).checked_write(currVirtual - loss);
  }

  function testCantReinitialize() external override {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    TruefiCreditLineStrategy(address(strategy)).initialize(address(1), address(2), owner);
  }

  function testMultipleDeposits() external {
    uint256 _val = 100 * ONE_SCALE;
    uint256 scaledVal = _val * 10**(18 - decimals);
    deal(address(underlying), address(this), _val * 100_000_000);

    uint256 priceAAPre = idleCDO.virtualPrice(address(AAtranche));
    // try to deposit the correct bal
    idleCDO.depositAA(_val);
    assertApproxEqAbs(
      IERC20Detailed(address(AAtranche)).balanceOf(address(this)), 
      scaledVal, 
      // 1 wei less for each unit of underlying, scaled to 18 decimals
      100 * 10**(18 - decimals) + 1, 
      'AA Deposit 1 is not correct'
    );
    uint256 priceAAPost = idleCDO.virtualPrice(address(AAtranche));
    _cdoHarvest(true);
    uint256 priceAAPostHarvest = idleCDO.virtualPrice(address(AAtranche));

    // now deposit again
    address user1 = makeAddr('user1');
    _depositWithUser(user1, _val, true);
    uint256 priceAAPost2 = idleCDO.virtualPrice(address(AAtranche));

    if (decimals < 18) {
      assertApproxEqAbs(
        IERC20Detailed(address(AAtranche)).balanceOf(user1), 
        // This is used to better account for slight differences in prices when using low decimals
        scaledVal * ONE_SCALE / priceAAPostHarvest, 
        1,
        'AA Deposit 2 is not correct'
      );
    } else {
      assertApproxEqAbs(
        IERC20Detailed(address(AAtranche)).balanceOf(user1), 
        scaledVal, 
        // 1 wei less for each unit of underlying, scaled to 18 decimals
        // check _mintShares for more info
        100 * 10**(18 - decimals) + 1, 
        'AA Deposit 2 is not correct'
      );
    }

    assertApproxEqAbs(priceAAPost, priceAAPre, 1, 'AA price is not the same after deposit 1');
    assertApproxEqAbs(priceAAPost, priceAAPostHarvest, 1, 'AA price is not the same after harvest');
    assertApproxEqAbs(priceAAPost2, priceAAPost, 1, 'AA price is not the same after deposit 2');
  }

  /// @notice not used in arbitrum
  function testMinStkIDLEBalance() external override {
  }

  function _testCheckMaxDecreaseDefault(uint256) internal override {
    // we need to increase the amount of underlying to make the test pass
    super._testCheckMaxDecreaseDefault(100000 * ONE_SCALE);
  }

  function testDepositRedeemWithLossShutdown() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // AA Ratio is 98%
    uint256 amountAA = amount - amount / 50;
    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amount / 50);
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    // uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));
    _cdoHarvest(true);

    uint256 unclaimedFees = idleCDO.unclaimedFees();
    // now let's simulate a loss by decreasing strategy price
    // curr price - 5%, this will trigger a default because the loss is >= junior tvl
    _createLoss(idleCDO.maxDecreaseDefault());

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

    // 0 means redeem all
    uint256 aaToWithdraw = 0;
    ITruefiCreditLine tf = ITruefiCreditLine(address(defaultVault));
    if (amountAA > tf.virtualTokenBalance()) {
      aaToWithdraw = tf.virtualTokenBalance();
    }
    // AA withdraw is allowed
    idleCDO.withdrawAA(aaToWithdraw);
  }

  // @dev Loss is between 0% and lossToleranceBps and is socialized
  function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external override {
    vm.assume(depositAmountAARatio >= 0);
    vm.assume(depositAmountAARatio <= FULL_ALLOC);

    vm.prank(idleCDO.owner());
    idleCDO.setLossToleranceBps(500); // 0.5%

    uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
    uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;
    
    uint256 depositedAA = idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);
    uint256 prePrice = strategy.price();

    // deposit underlying to the strategy
    _cdoHarvest(true);

    _createLoss(idleCDO.lossToleranceBps() / 2);

    uint256 priceDelta = ((prePrice - strategy.price()) * ONE_SCALE) / prePrice;
    uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));
    uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));

    if (depositAmountAARatio > 0) {
      assertApproxEqAbs(priceAA, ONE_SCALE - priceDelta, 101, "AA price after loss");
    }
    if (depositAmountAARatio < FULL_ALLOC) {
      assertApproxEqAbs(priceBB, ONE_SCALE - priceDelta, 101, "BB price after loss");
    }

    // redeem half of the deposits (if we redeem all the leftovers will cause 
    // BB price to increase)
    uint256 resAA;
    if (depositAmountAARatio > 0) {
      resAA = idleCDO.withdrawAA(depositedAA / 2);
    }

    if (depositAmountAARatio > 0) {
      assertApproxEqRel(
        resAA,
        amountAA * (ONE_SCALE - priceDelta) / ONE_SCALE / 2, 
        10**14, // 0.01% max delta
        "AA amount after loss"
      );
    } else {
      assertApproxEqRel(resAA, amountAA / 2, 1, "AA amount not changed");
    }

    uint256 resBB;
    if (depositAmountAARatio < FULL_ALLOC) {
      resBB = idleCDO.withdrawBB(0);
    }

    if (depositAmountAARatio < FULL_ALLOC) {
      assertApproxEqRel(
        resBB, 
        (amountBB * (ONE_SCALE - priceDelta)) / ONE_SCALE, 
        5*10**14,
        "BB amount after loss"
      );
    } else {
      assertApproxEqRel(resBB, amountBB, 1, "BB amount not changed");
    }
  }
}
