// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./TestIdleCDOBase.sol";

import "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

abstract contract TestIdleCDOLossMgmt is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address public vault; // used to simulate price increase via _donateToken
    uint256 public increaseAmount;

    // Used to trasfer underlying to `vault` and simulate a price increase
    function _donateToken(address to, uint256 amount) internal virtual {}

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

    // @dev Loss is between lossToleranceBps and maxDecreaseDefault and is covered by junior holders
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

    // @dev Loss is between 0% and lossToleranceBps and is socialized
    function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external virtual {
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

        if (depositAmountAARatio > 0) {
            assertApproxEqRel(resAA, (amountAA * (postAAPrice) / 1e18) * (FULL_ALLOC / 10) / FULL_ALLOC, 10**13, "AA amount after loss");
        } else {
            assertApproxEqRel(resAA, amountAA, 1, "AA amount not changed");
        }

        if (depositAmountAARatio < FULL_ALLOC) {
            assertApproxEqRel(resBB, (amountBB * (postBBPrice) / 1e18) * (FULL_ALLOC / 10) / FULL_ALLOC, 10**13, "BB amount after loss");
        } else {
            assertApproxEqRel(resBB, amountBB, 1, "BB amount not changed");
        }

        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
        assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    function testAPRSplitRatioRedeems(
        uint16 _ratio,
        uint16 _redeemRatioAA,
        uint16 _redeemRatioBB
    ) external override {
        vm.assume(_ratio <= 1000 && _ratio > 0);
        // > 0 because it's a requirement of the withdraw
        vm.assume(_redeemRatioAA <= 1000 && _redeemRatioAA > 0);
        vm.assume(_redeemRatioBB <= 1000 && _redeemRatioBB > 0);

        // uint16 _ratio = 1;
        // uint16 _redeemRatioAA = 1;
        // uint16 _redeemRatioBB = 910;

        uint256 amount = 1000 * ONE_SCALE;
        // to have the same scale as FULL_ALLOC and avoid 
        // `Too many global rejects` error in forge
        uint256 ratio = uint256(_ratio) * 100; 
        uint256 amountAA = amount * ratio / FULL_ALLOC;
        uint256 amountBB = amount - amountAA;
        // funds are in the contract but not yet in the lending protocol
        // as no harvest has been made
        idleCDO.depositAA(amountAA);
        idleCDO.depositBB(amountBB);

        // funds in lending
        _cdoHarvest(true);

        // Set new block.height to avoid reentrancy check on deposit/withdraw
        vm.roll(block.number + 1);

        uint256 ratioRedeemAA = uint256(_redeemRatioAA) * 100; 
        uint256 ratioRedeemBB = uint256(_redeemRatioBB) * 100; 
        amountAA = AAtranche.balanceOf(address(this)) * ratioRedeemAA / FULL_ALLOC;
        amountBB = BBtranche.balanceOf(address(this)) * ratioRedeemBB / FULL_ALLOC;
        if (amountAA > 0) {
            idleCDO.withdrawAA(amountAA);
        }
        if (amountBB > 0) {
            idleCDO.withdrawBB(amountBB);
        }

        // both withdrawals are increasing the NAV and so the price of tranches 
        // is increasing too because the expectedFee gets added to the NAV
        uint256 AABal = AAtranche.totalSupply() * idleCDO.virtualPrice(address(AAtranche)) / ONE_SCALE;
        uint256 BBBal = BBtranche.totalSupply() * idleCDO.virtualPrice(address(BBtranche)) / ONE_SCALE;
        uint256 newAATVLRatio = AABal * FULL_ALLOC / (AABal + BBBal);
        assertApproxEqAbs(
            idleCDO.trancheAPRSplitRatio(), 
            _calcNewAPRSplit(newAATVLRatio), 
            2,
            "split ratio on redeem"
        );
    }
}
