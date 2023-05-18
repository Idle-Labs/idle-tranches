// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./TestIdleCDOBase.sol";

import {InstadappLiteETHV2Strategy} from "../../contracts/strategies/instadapp/InstadappLiteETHV2Strategy.sol";
import {IdleCDOInstadappLiteVariant} from "../../contracts/IdleCDOInstadappLiteVariant.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

interface IETHV2Vault {
    function withdrawalFeePercentage() external returns (uint256);
}

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

    function _pokeLendingProtocol() internal override {
        vm.prank(0x10F37Ceb965B477bA09d23FF725E0a0f1cdb83a5);
        (bool success, ) = ETHV2Vault.call(abi.encodeWithSignature("updateExchangePrice()"));
        require(success, "updateExchangePrice failed");
    }

    function _donateToken(address to, uint256 amount) internal {
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

    // @dev Loss is between lossToleranceBps and maxDecreaseDefault and is covered by junior holders
    function testDepositWithLossCovered() external {
        uint256 amount = 10000 * ONE_SCALE;
        // fee is set to 10% and release block period to 0
        uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 prePrice = strategy.price();
        uint256 maxDecrease = idleCDO.maxDecreaseDefault();
        uint256 unclaimedFees = idleCDO.unclaimedFees();

        // deposit underlying to the strategy
        _cdoHarvest(true);
        // now let's simulate a loss by decreasing strategy price
        // curr price - about 2.5%
        _createLoss(maxDecrease / 2);

        uint256 priceDelta = ((prePrice - strategy.price()) * 1e18) / prePrice;
        uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));
        // juniors lost about 5%(~= 2x priceDelta) as there were seniors to cover
        assertApproxEqAbs(postBBPrice, (preBBPrice * (1e18 - 2 * priceDelta)) / 1e18, 100, "BB price after loss");
        // seniors are covered
        assertApproxEqAbs(preAAPrice, postAAPrice, 1, "AA price unaffected");
        assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 1, "AA price not updated until new interaction");
        assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 1, "BB price not updated until new interaction");
        assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 1, "Fees did not increase");
    }

    // @dev Loss is between 0% and lossToleranceBps and is socialized
    function testDepositWithLossSocialized(uint256 depositAmountAARatio) external {
        vm.assume(depositAmountAARatio >= 0);
        vm.assume(depositAmountAARatio <= FULL_ALLOC);

        uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
        uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;
        uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

        idleCDO.depositAA(amountAA);
        idleCDO.depositBB(amountBB);

        uint256 prePrice = strategy.price();
        uint256 unclaimedFees = idleCDO.unclaimedFees();

        // deposit underlying to the strategy
        _cdoHarvest(true);
        // now let's simulate a loss by decreasing strategy price
        // curr price - about 0.25%
        _createLoss(idleCDO.lossToleranceBps() / 2);

        uint256 priceDelta = ((prePrice - strategy.price()) * 1e18) / prePrice;
        uint256 lastNAVAA = idleCDO.lastNAVAA();
        uint256 currentAARatioScaled = lastNAVAA * ONE_SCALE / (idleCDO.lastNAVBB() + lastNAVAA);
        uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));

        // Both junior and senior lost
        if (currentAARatioScaled > 0) {
            assertApproxEqAbs(postAAPrice, (preAAPrice * (1e18 - priceDelta)) / 1e18, 100, "AA price after loss");
        } else {
            assertApproxEqAbs(postAAPrice, preAAPrice, 1, "AA price not changed");
        }
        if (currentAARatioScaled < ONE_SCALE) {
            assertApproxEqAbs(postBBPrice, (preBBPrice * (1e18 - priceDelta)) / 1e18, 100, "BB price after loss");
        } else {
            assertApproxEqAbs(postBBPrice, preBBPrice, 1, "BB price not changed");
        }

        // seniors lost
        assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 0, "AA price not updated until new interaction");
        assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 0, "BB price not updated until new interaction");
        assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 0, "Fees did not increase");
    }

    // @dev Loss is > maxDecreaseDefault and is absorbed by junior holders if possible
    function testDepositRedeemWithLossShutdown() external {
        uint256 amount = 10000 * ONE_SCALE;
        // TODO test also with loss < junior -> add fuzzing


        // AA Ratio is 98%
        idleCDO.depositAA(amount - amount / 50);
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
        IdleCDO(address(idleCDO)).updateAccounting();
        // loss is now distributed and shutdown triggered
        uint256 postDepositAAPrice = idleCDO.virtualPrice(address(AAtranche));
        uint256 postDepositBBPrice = idleCDO.virtualPrice(address(BBtranche));

        assertEq(postDepositAAPrice, postAAPrice, "AA price did not change after updateAccounting");
        assertEq(postDepositBBPrice, postBBPrice, "BB price did not change after updateAccounting");
        assertEq(idleCDO.priceAA(), postDepositAAPrice, "AA saved price updated");
        assertEq(idleCDO.priceBB(), postDepositBBPrice, "BB saved price updated");
        assertEq(idleCDO.unclaimedFees(), unclaimedFees, "Fees did not increase");
        assertEq(idleCDO.allowAAWithdraw(), false, "Default flag for senior set");
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
        idleCDO.withdrawAA(0);
        vm.expectRevert(bytes("3"));
        idleCDO.withdrawBB(0);
    }

    // price increases highly enough to cover withdrawal fees
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

    // price decreases
    function testRedeemWithLossCovered() external {
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

    // Test socialized loss on redeem
    function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external {
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
}