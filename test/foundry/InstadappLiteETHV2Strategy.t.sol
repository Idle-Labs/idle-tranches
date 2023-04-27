// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./TestIdleCDOBase.sol";

import {InstadappLiteETHV2Strategy} from "../../contracts/strategies/instadapp/InstadappLiteETHV2Strategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

contract TestInstadappLiteETHV2Strategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant ETHV2Vault = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16981000);
        super.setUp();
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
        // uint256 bal = underlying.balanceOf(whale);
        // initialBal = 10000 * ONE_SCALE;
        // require(bal >= initialBal, "whale doesn't have enough tokens");
        // vm.prank(0x41318419CFa25396b47A94896FfA2C77c6434040);
        // underlying.transfer(address(this), bal);
        initialBal = underlying.balanceOf(whale);
        require(initialBal > 20000 * ONE_SCALE, "whale doesn't have enough tokens");
        vm.prank(0x41318419CFa25396b47A94896FfA2C77c6434040);
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
        assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal - totAmount, 1, "underlying bal");
        assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), totAmount, 1, "underlying bal");
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

        uint256 releasePeriod = _strategyReleaseBlocksPeriod();
        _donateToken(ETHV2Vault, 10000 * ONE_SCALE);
        // vm.mockCall(
        //     ETHV2Vault,
        //     abi.encodeWithSelector(IERC4626Upgradeable.convertToAssets.selector),
        //     abi.encode((IERC4626Upgradeable(ETHV2Vault).convertToAssets(ONE_SCALE) * 110) / 100)
        // );

        // Skip 7 day forward to accrue interest
        skip(7 days);
        if (releasePeriod == 0) {
            // 7 days in blocks
            vm.roll(block.number + 7 * 7200);
        } else {
            vm.roll(block.number + releasePeriod + 1);
        }

        _pokeLendingProtocol();

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

        // uint256 currPrice = strategy.price();
        uint256 maxDecrease = idleCDO.maxDecreaseDefault();
        uint256 unclaimedFees = idleCDO.unclaimedFees();
        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 10000 * 1e18, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, 1, "BBtranche bal");
        assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal - totAmount, 1, "underlying bal");
        assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), totAmount, 1, "underlying bal");
        // strategy is still empty with no harvest
        assertApproxEqAbs(strategyToken.balanceOf(address(idleCDO)), 0, 1, "strategy bal");

        // now let's simulate a loss by decreasing strategy price
        // curr price - 5%
        // vm.mockCall(
        //     address(strategy),
        //     abi.encodeWithSelector(IIdleCDOStrategy.price.selector),
        //     abi.encode((currPrice * (FULL_ALLOC - maxDecrease)) / FULL_ALLOC)
        // );
        uint256 totalAssets = IERC4626Upgradeable(ETHV2Vault).totalAssets();
        uint256 amountRemoved = (totalAssets * (FULL_ALLOC - maxDecrease)) / FULL_ALLOC;
        uint256 bal = underlying.balanceOf(ETHV2Vault);
        require(bal > amountRemoved, "loss is too large");
        vm.prank(ETHV2Vault);
        underlying.transfer(address(0x07), amountRemoved);

        _pokeLendingProtocol();

        uint256 releasePeriod = _strategyReleaseBlocksPeriod();

        // Skip 7 day forward to accrue interest
        skip(7 days);
        if (releasePeriod == 0) {
            // 7 days in blocks
            vm.roll(block.number + 7 * 7200);
        } else {
            vm.roll(block.number + releasePeriod + 1);
        }
        uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
        // juniors lost about 10% as there were seniors to cover
        assertApproxEqAbs(
            (preBBPrice * 90000) / 100000,
            postBBPrice,
            200 // 200 wei to account for interest accrued
        );
        // seniors are covered
        assertEq(preAAPrice, postAAPrice, "AA price unaffected");
        assertEq(idleCDO.priceAA(), preAAPrice, "AA price not updated until new interaction");
        assertEq(idleCDO.priceBB(), preBBPrice, "BB price not updated until new interaction");

        // _depositWithUser(idleCDO.rebalancer(), amount, true);
        // _depositWithUser(idleCDO.rebalancer(), amount, false);

        // uint256 postDepositAAPrice = idleCDO.virtualPrice(address(AAtranche));
        // uint256 postDepositBBPrice = idleCDO.virtualPrice(address(BBtranche));

        // assertEq(postDepositAAPrice, postAAPrice, "AA price did not change after deposit");
        // assertEq(postDepositBBPrice, postBBPrice, "BB price did not change after deposit");
        // assertEq(idleCDO.priceAA(), postDepositAAPrice, "AA saved price updated");
        // assertEq(idleCDO.priceBB(), postDepositBBPrice, "BB saved price updated");

        assertEq(idleCDO.unclaimedFees(), unclaimedFees, "Fees did not increase");
    }

    function _doDepositsWithInterest(uint256 aa, uint256 bb) internal returns (uint256 priceAA, uint256 priceBB) {
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
        assertGt(priceAA, ONE_SCALE, "AA price is > 1");
        assertGt(priceBB, ONE_SCALE, "BB price is > 1");
    }
}
