// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./TestIdleCDOBase.sol";

import {InstadappLiteETHV2Strategy} from "../../contracts/strategies/instadapp/InstadappLiteETHV2Strategy.sol";
import {IdleCDOInstadappLiteVariant} from "../../contracts/IdleCDOInstadappLiteVariant.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

contract TestInstadappLiteETHV2Strategy is TestIdleCDOBase {
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
        runOnForkingNetwork(MAINNET_CHIANID)
        returns (address _strategy, address _underlying)
    {
        _underlying = STETH;
        strategyToken = IERC20Detailed(ETHV2Vault);
        strategy = new InstadappLiteETHV2Strategy();

        _strategy = address(strategy);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        InstadappLiteETHV2Strategy(_strategy).initialize(_owner);
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        InstadappLiteETHV2Strategy(address(strategy)).setWhitelistedCDO(address(_cdo));
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

    function testCantReinitialize() external override {}

    function _pokeLendingProtocol() internal override {
        vm.prank(0x10F37Ceb965B477bA09d23FF725E0a0f1cdb83a5);
        (bool success, ) = ETHV2Vault.call(abi.encodeWithSignature("updateExchangePrice()"));
        require(success, "updateExchangePrice failed");
    }

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

        // claim rewards
        _cdoHarvest(false);
        assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), 0, 1, "underlying bal after harvest");

        // NOTE: forcely increase the vault price
        _donateToken(ETHV2Vault, 40 * ONE_SCALE);

        // Skip 7 day forward to accrue interest
        // 7 days in blocks
        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        // update the vault price
        _pokeLendingProtocol();
        console.log("currPrice :>>", strategyPrice);
        console.log("strategy.price() :>>", strategy.price());

        assertGt(strategy.price(), strategyPrice, "strategy price");

        // virtualPrice should increase too
        assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
        assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
    }

    function _donateToken(address to, uint256 amount) internal {
        address farmingPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        uint256 bal = underlying.balanceOf(farmingPool);
        require(bal > amount, "doesn't have enough tokens");
        vm.prank(farmingPool);
        underlying.transfer(to, amount);
    }

    function testDepositWithLossCovered() external {
        uint256 amount = 10000 * ONE_SCALE;
        // fee is set to 10% and release block period to 0
        uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 totAmount = amount * 2;

        uint256 currPrice = strategy.price();
        console.log("currPrice :>>", currPrice);
        uint256 maxDecrease = idleCDO.maxDecreaseDefault();
        uint256 unclaimedFees = idleCDO.unclaimedFees();
        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 10000 * 1e18, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, 1, "BBtranche bal");
        assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal - totAmount, 1, "underlying bal");
        assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), totAmount, 2, "underlying bal");
        // strategy is still empty with no harvest
        assertApproxEqAbs(strategyToken.balanceOf(address(idleCDO)), 0, 1, "strategy bal");

        // now let's simulate a loss by decreasing strategy price
        // curr price - 5%
        uint256 totalAssets = IERC4626Upgradeable(ETHV2Vault).totalAssets();
        uint256 loss = (totalAssets * maxDecrease) / FULL_ALLOC;
        uint256 bal = underlying.balanceOf(ETHV2Vault);
        require(bal >= loss, "test: loss is too large");
        vm.prank(ETHV2Vault);
        underlying.transfer(address(0x07), loss);

        // Skip 7 day forward to accrue interest
        // 7 days in blocks
        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        _pokeLendingProtocol();
        uint256 price = strategy.price();
        console.log("price :>>", price);

        uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
        // juniors lost about 10% as there were seniors to cover
        // TODO:
        //   Expected: 999999999999999999
        //     Actual: 900000000000000000
        assertApproxEqAbs((preBBPrice * 90_000) / 100_000, postBBPrice, 1, "BB price after loss");
        // seniors are covered
        assertApproxEqAbs(preAAPrice, postAAPrice, 1, "AA price unaffected");
        assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 1, "AA price not updated until new interaction");
        assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 1, "BB price not updated until new interaction");

        assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 1, "Fees did not increase");
    }

    function testRedeems() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 currPrice = strategy.price();
        console.log("currPrice :>>", currPrice);
        // funds in lending
        _cdoHarvest(true);

        // NOTE: forcely increase the vault price
        // 20 steth : currP > price => assertion err
        // 50       : currP < price => assertion err
        // 100 steth: currP < price => assertion pass
        _donateToken(ETHV2Vault, 50 * ONE_SCALE);

        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        _pokeLendingProtocol();
        console.log("price :>>", strategy.price());
        // redeem all
        uint256 resAA = idleCDO.withdrawAA(0);
        assertGt(resAA, amount, "AA gained something");
        uint256 resBB = idleCDO.withdrawBB(0);
        assertGt(resBB, amount, "BB gained something");

        assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
        assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
        assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    function testRedeemWithLossCovered() external {}
}
