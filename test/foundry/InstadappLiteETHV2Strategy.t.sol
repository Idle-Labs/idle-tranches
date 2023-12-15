// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./TestIdleCDOLossMgmt.sol";

import {InstadappLiteETHV2Strategy} from "../../contracts/strategies/instadapp/InstadappLiteETHV2Strategy.sol";
import {IdleCDOInstadappLiteVariant} from "../../contracts/IdleCDOInstadappLiteVariant.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

interface IETHV2Vault {
    function withdrawalFeePercentage() external returns (uint256);
}

contract TestInstadappLiteETHV2Strategy is TestIdleCDOLossMgmt {
    using stdStorage for StdStorage;

    address internal constant ETHV2Vault = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function setUp() public override {
        vm.createSelectFork("mainnet", 17138692);
        super.setUp();
    }

    function _deployCDO() internal override returns (IdleCDO _cdo) {
        _cdo = new IdleCDOInstadappLiteVariant();
    }

    function _deployStrategy(address _owner)
        internal
        override
        returns (address _strategy, address _underlying)
    {
        _underlying = STETH;
        strategyToken = IERC20Detailed(ETHV2Vault);
        strategy = new InstadappLiteETHV2Strategy();

        _strategy = address(strategy);
        vault = address(ETHV2Vault);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        InstadappLiteETHV2Strategy(_strategy).initialize(_owner);
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        InstadappLiteETHV2Strategy(address(strategy)).setWhitelistedCDO(address(_cdo));

        // sync all prev gain/losses of the underlying protocol
        _pokeLendingProtocol();
    }

    /// override to fund the strategy with tokens
    /// `deal` doesn't work as expected for some reason
    function _fundTokens() internal override {
        // https://etherscan.io/address/0x41318419CFa25396b47A94896FfA2C77c6434040
        address whale = 0x41318419CFa25396b47A94896FfA2C77c6434040;
        initialBal = underlying.balanceOf(whale);
        require(initialBal > 20000 * ONE_SCALE, "whale doesn't have enough tokens");
        vm.prank(whale);
        underlying.transfer(address(this), initialBal);
    }

    function _pokeLendingProtocol() internal override {
        vm.prank(0x10F37Ceb965B477bA09d23FF725E0a0f1cdb83a5);
        // vm.prank(0xf9ec23c0387b2780c3761c2c5cfc6c92bfd49f90);
        (bool success, ) = ETHV2Vault.call(abi.encodeWithSignature("updateExchangePrice()"));
        require(success, "updateExchangePrice failed");
    }

    function _donateToken(address to, uint256 amount) internal override {
        address farmingPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        uint256 bal = underlying.balanceOf(farmingPool);
        require(bal > amount, "doesn't have enough tokens");
        vm.prank(farmingPool);
        underlying.transfer(to, amount);
    }

    function _createLoss(uint256 _loss) internal override {
        uint256 totalAssets = IERC4626Upgradeable(ETHV2Vault).totalAssets();
        uint256 loss = totalAssets * _loss / FULL_ALLOC;
        uint256 bal = underlying.balanceOf(ETHV2Vault);
        require(bal >= loss, "test: loss is too large");
        vm.prank(ETHV2Vault);
        underlying.transfer(address(0xdead), loss);
        // update vault price
        _pokeLendingProtocol();
    }

    function testCantReinitialize() external override {}

    function testAPR() external override {
        uint256 amount = 10000 * ONE_SCALE;
        
        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        _cdoHarvest(true);
        
        uint256 lastPrice = strategy.price();
        uint256 lastPriceTimestamp = block.timestamp;

        // NOTE: forcely increase the vault price
        _donateToken(ETHV2Vault, 40 * ONE_SCALE);

        // update the vault price
        _pokeLendingProtocol();

        // Skip 1 block
        skip(1 days);
        vm.roll(block.number + 1 * 7200);

        // Check strategy APR after 1 day
        assertApproxEqAbs(strategy.getApr(), 0, 0, "APR is always 0");

        // 7 days in blocks
        skip(1 days);
        vm.roll(block.number + 1 * 7200);

        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        _cdoHarvest(true);

        lastPrice = strategy.price();
        lastPriceTimestamp = block.timestamp;

        // NOTE: forcely increase the vault price
        _donateToken(ETHV2Vault, 40 * ONE_SCALE);

        // update the vault price
        _pokeLendingProtocol();

        // 1 days in blocks
        skip(1 days);
        vm.roll(block.number + 1 * 7200);

        // Check strategy APR after 1 more deposit and 1 more day
        assertApproxEqAbs(strategy.getApr(), 0, 0, "APR is always 0 as is calculated on the client");

        // NOTE: forcely increase the vault price
        _donateToken(ETHV2Vault, 40 * ONE_SCALE);

        // update the vault price
        _pokeLendingProtocol();

        // 7 days in blocks
        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        // Check APR after 7 days (no deposits)
        assertApproxEqAbs(strategy.getApr(), 0, 0, "Check strategy APR (still 0)");
    }

    // @dev there are gains for the strategy
    function testDeposits() external override {
        uint256 amount = 10000 * ONE_SCALE;
        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 totAmount = amount * 2;

        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 10000 * 1e18, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, 1, "BBtranche bal");
        assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal - totAmount, 1, "underlying bal depositor");
        assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), totAmount, 2, "underlying bal cdo");
        // strategy is still empty with no harvest
        assertApproxEqAbs(strategyToken.balanceOf(address(idleCDO)), 0, 1, "strategy bal");
        uint256 strategyPrice = strategy.price();

        // check that trancheAPRSplitRatio and aprs are updated
        assertApproxEqAbs(idleCDO.trancheAPRSplitRatio(), 25000, 1, "split ratio");
        // limit is 50% of the strategy apr if AAratio is <= 50%
        assertApproxEqAbs(idleCDO.getApr(address(AAtranche)), initialApr / 2, 1, "AA apr");
        // apr will be 150% of the strategy apr if AAratio is == 50%
        assertApproxEqAbs(idleCDO.getApr(address(BBtranche)), (initialApr * 3) / 2, 1, "BB apr");

        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), 0, 1, "underlying bal after harvest");

        // NOTE: forcely increase the vault price
        _donateToken(ETHV2Vault, 40 * ONE_SCALE);

        // Skip 7 day forward to accrue interest
        // 7 days in blocks
        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        // update the vault price
        _pokeLendingProtocol();

        assertGt(strategy.price(), strategyPrice, "strategy price");

        // virtualPrice should increase too
        assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
        assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
    }

    // @dev price increases highly enough to cover withdrawal fees
    function testRedeems() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);

        // NOTE: forcely increase the vault price
        _donateToken(ETHV2Vault, 100 * ONE_SCALE);

        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        _pokeLendingProtocol();
        // redeem all
        uint256 resAA = idleCDO.withdrawAA(0);
        assertGt(resAA, amount, "AA gained something");
        uint256 resBB = idleCDO.withdrawBB(0);
        assertGt(resBB, amount, "BB gained something");

        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
        assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    // @dev Loss is between 0% and lossToleranceBps and is socialized
    function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external override {
        vm.assume(depositAmountAARatio >= 0);
        vm.assume(depositAmountAARatio <= FULL_ALLOC);

        uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
        uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;

        idleCDO.depositAA(amountAA);
        idleCDO.depositBB(amountBB);

        // deposit underlying to the strategy
        _cdoHarvest(true);

        // now let's simulate a loss by decreasing strategy price
        // curr price - about 0.25%
        _createLoss(idleCDO.lossToleranceBps() / 2);

        // Get AA tranche price
        uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));

        // redeem all
        uint256 resAA;
        if (depositAmountAARatio > 0) {
            resAA = idleCDO.withdrawAA(0);
        }

        // Get BB tranche price after the AA redeem
        uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));

        uint256 resBB;
        if (depositAmountAARatio < FULL_ALLOC) {
            resBB = idleCDO.withdrawBB(0);
        }

        // Get Instadapp withdrawal fee
        uint256 withdrawalFeePercentage = IETHV2Vault(ETHV2Vault).withdrawalFeePercentage();

        // withdrawal fee of instadapp vault is deducted from the amount
        if (depositAmountAARatio > 0) {
            assertApproxEqRel(resAA, (amountAA * (postAAPrice) / 1e18) * (FULL_ALLOC - withdrawalFeePercentage / 10) / FULL_ALLOC, 10**13, "AA amount after loss");
        } else {
            assertApproxEqRel(resAA, amountAA, 1, "AA amount not changed");
        }

        if (depositAmountAARatio < FULL_ALLOC) {
            assertApproxEqRel(resBB, (amountBB * (postBBPrice) / 1e18) * (FULL_ALLOC - withdrawalFeePercentage / 10) / FULL_ALLOC, 10**13, "BB amount after loss");
        } else {
            assertApproxEqRel(resBB, amountBB, 1, "BB amount not changed");
        }

        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
        assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    // @dev redeem reverts due to withdraw fee or slippage
    function testRedeemWithLiquidation() external {
        uint256 amount = 10000 * ONE_SCALE;

        idleCDO.depositAA(amount);
        // deposit underlying to the strategy
        _cdoHarvest(true);

        // set liquidationToleranceBps = 0
        vm.prank(idleCDO.owner());
        IdleCDOInstadappLiteVariant(address(idleCDO)).setLiquidationToleranceBps(0);

        // redeem and expect revert
        vm.expectRevert(bytes("5"));
        idleCDO.withdrawAA(0);

        // increase liq tolerance to allow withdraw fee
        uint256 liquidationToleranceBps = 500;
        vm.prank(idleCDO.owner());
        IdleCDOInstadappLiteVariant(address(idleCDO)).setLiquidationToleranceBps(liquidationToleranceBps);

        // redeem and expect an amount
        uint256 resAA = idleCDO.withdrawAA(0);
        assertApproxEqAbs(resAA, amount, (amount * liquidationToleranceBps) / FULL_ALLOC, "AA amount not correct");
    }

    // @dev Fee is correctly accounted when there is unlent amount
    function testRedeemWithFeesAsGain() external {
        vm.prank(owner);
        idleCDO.setUnlentPerc(10000); // 10%

        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);
        // funds in lending
        _cdoHarvest(true);

        // strategy token have the same price as before
        uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));

        assertApproxEqAbs(priceBB, ONE_SCALE, 1, "BB > 1");
        assertApproxEqAbs(priceAA, ONE_SCALE, 1, "AA > 1");

        // redeem 1/2 of AA (which is more of the unlent amount)
        uint256 resAA = idleCDO.withdrawAA(AAtranche.balanceOf(address(this)) / 2);
        // prices of both tranches should be increasing because
        // there is 20000 of total tvl and 2000 of unlent
        // user is redeeming 5000 and fee paid should be in total 2.5 stETH of which 
        // 2000 * 0.05% = 1 stETH is the gain for the pool as it's taken from unlent
        // fee is amount/2 * 0.0005 -> amount/2 * 1/2000 -> amount / 4000
        // 5000 wei tolerance ie 1 wei for each stETH
        assertApproxEqAbs(resAA, amount/2 - (amount/4000), 5000, 'AA redeem amount is wrong');

        uint256 priceBBAfter = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAAAfter = idleCDO.virtualPrice(address(AAtranche));
        // assert that both prices are still increasing. APR split ratio is 16666
        // so gain is 0.83334 for BB and 0.16666 for AA
        // so price increase is 0.83334 / 10000 -> 0.000083334 for BB and 
        // so price increase is 0.16666 / 5000 -> 0.000016666 for AA and 
        assertEq(priceBBAfter, priceBB + 8.3334 * 1e17 / 10000, "BB price not increased");
        assertEq(priceAAAfter, priceAA + 1.6666 * 1e17 / 5000, "AA price not increased");

        // redeem 1/2 of BB, there is 1 stETH as unlent (the gain from last withdraw)
        uint256 resBB = idleCDO.withdrawBB(BBtranche.balanceOf(address(this)) / 2);
        uint256 expected = amount/2 * priceBBAfter / 1e18;
        uint256 expectedFee = expected * 5 / 10000; // 0.05% fee
        assertApproxEqAbs(resBB, expected - expectedFee, 2, 'BB redeem amount is wrong');

        // APR split is 24999 (it consider the gain from last withdraw as TVL ratio is 49998)
        // gain for the pool is 1 stETH * 0.05% = 0.0005 stETH
        // 0.0005 -> 5 / 10000
        // so price increase is (0.0005 * (100000 - 24999) / 100000) / 5000 for BB 
        // -> (5 * 75001 / 1e9) / 5000 -> transform in wei -> (5 * 75001 * 1e18 / 1e9) / 5000
        // so price increase is (0.0005 * 24999) / 100000) / 5000 for AA and 
        // -> (5 * 24999 / 1e9) / 5000 -> transform in wei -> (5 * 24999 * 1e18 / 1e9) / 5000
        uint256 priceBBAfter2 = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAAAfter2 = idleCDO.virtualPrice(address(AAtranche));
        assertApproxEqAbs(priceBBAfter2, priceBBAfter + (5 * 75001 * 1e18 / 1e9) / 5000, 1, "BB price not increased correctly");
        assertApproxEqAbs(priceAAAfter2, priceAAAfter + (5 * 24999 * 1e18 / 1e9) / 5000, 1, "AA price not increased correctly");
    }

    // @dev Fee is correctly accounted
    function testRedeemWithFees() external {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        // NOTE: forcely increase the vault price
        _donateToken(vault, ONE_SCALE); // 1 underlying
        _pokeLendingProtocol();

        uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));

        assertGt(priceBB, ONE_SCALE, "BB > 1");
        assertGt(priceAA, ONE_SCALE, "AA > 1");

        // redeem half of AA
        idleCDO.withdrawAA(AAtranche.balanceOf(address(this)) / 2);
        uint256 priceBBAfter = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAAAfter = idleCDO.virtualPrice(address(AAtranche));
        // assert that both prices are still increasing
        assertGe(priceBBAfter, priceBB, "BB price not increased");
        assertGe(priceAAAfter, priceAA, "AA price not increased");

        // redeem half of BB
        idleCDO.withdrawBB(BBtranche.balanceOf(address(this)) / 2);
        uint256 priceBBAfter2 = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAAAfter2 = idleCDO.virtualPrice(address(AAtranche));

        // assert that both prices are still increasing
        assertGe(priceBBAfter2, priceBBAfter, "BB price 2 not increased");
        assertGe(priceAAAfter2, priceAAAfter, "AA price 2 not increased");
    }

    // @dev Fee is correctly accounted when there is unlent amount
    function testRedeemWithFeesAndUnlent() external {
        vm.prank(owner);
        idleCDO.setUnlentPerc(20000); // 20%

        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);

        // NOTE: forcely increase the vault price
        uint256 increase = ONE_SCALE / 100;
        _donateToken(vault, increase);
        _pokeLendingProtocol();

        uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));

        assertGt(priceBB, ONE_SCALE, "BB > 1");
        assertGt(priceAA, ONE_SCALE, "AA > 1");

        // redeem 1/20 of AA (which is less of the unlent amount), pool is gaining the fee here
        uint256 resAA = idleCDO.withdrawAA(AAtranche.balanceOf(address(this)) / 20);
        uint256 priceBBAfter = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAAAfter = idleCDO.virtualPrice(address(AAtranche));
        // assert that both prices are still increasing
        assertGe(priceBBAfter, priceBB, "BB price not increased");
        assertGe(priceAAAfter, priceAA, "AA price not increased");

        // the increase is for the whole vault, we deposited 20000 underlyings in total so we are not the whole pool
        uint256 expectedRedeemNoFeeAA = amount/20 + increase/4;
        // 0.05% fee, maxDelta 0.001% for the price increase
        assertApproxEqRel(resAA, expectedRedeemNoFeeAA - (expectedRedeemNoFeeAA * 5 / 10000), 0.00001e18, 'AA redeem wrong');

        // redeem half of BB (which is more than the unlent amount)
        uint256 resBB = idleCDO.withdrawBB(BBtranche.balanceOf(address(this)) / 2);
        uint256 priceBBAfter2 = idleCDO.virtualPrice(address(BBtranche));
        uint256 priceAAAfter2 = idleCDO.virtualPrice(address(AAtranche));
        uint256 expectedRedeemNoFeeBB = amount/2 + increase/4;

        assertApproxEqRel(resBB, expectedRedeemNoFeeBB - (expectedRedeemNoFeeBB * 5 / 10000), 0.00002e18, 'BB redeem wrong');

        // assert that both prices are still increasing
        assertGe(priceBBAfter2, priceBBAfter, "BB price 2 not increased");
        assertGe(priceAAAfter2, priceAAAfter, "AA price 2 not increased");
    }

    function testCheckMaxDecreaseDefault() external override {
        vm.prank(owner);
        idleCDO.setUnlentPerc(0); // 10%

        uint256 amount = 10000 * ONE_SCALE;
        uint256 amountAA = amount - amount / 50;
        uint256 amountBB = amount / 50;

        idleCDO.depositAA(amountAA);
        idleCDO.depositBB(amountBB);
        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        // now let's simulate a loss by decreasing strategy price
        // curr price - 10%, this will trigger a default
        uint256 lossBps = IdleCDO(address(idleCDO)).maxDecreaseDefault() * 2;
        _createLoss(lossBps);

        uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
        // juniors lost 100% as they need to cover seniors
        assertEq(0, postBBPrice, 'Full loss for junior tranche');
        // seniors are covered
        assertApproxEqRel(
            (amount * (FULL_ALLOC - lossBps) / FULL_ALLOC) * 1e18 / amountAA,
            postAAPrice, 
            1e15, // 0.2%
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

    function testRedeemWithLossCovered() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);

        // NOTE: forcely decrease the vault price
        // curr price - 2.5%
        _createLoss(idleCDO.maxDecreaseDefault() / 2);

        // redeem all
        uint256 resAA = idleCDO.withdrawAA(0);
        uint256 resBB = idleCDO.withdrawBB(0);

        // withdrawal fee of instadapp vault is deducted from the amount
        assertApproxEqRel(resAA, (amount * 995) / 1000, 0.01 * 1e18, "BB price after loss"); // 1e18 == 100%
        // juniors lost about 5% as there were seniors to cover + withdarawal fee
        assertApproxEqRel(resBB, (((amount * 95_000) / 100_000) * 995) / 1000, 0.005 * 1e18, "BB price after loss"); // 1e18 == 100%

        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
        assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }
}
