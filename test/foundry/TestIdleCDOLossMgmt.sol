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
    uint256 public ONE_TRANCHE_TOKEN = 1e18;

    // Used to trasfer underlying to `vault` and simulate a price increase
    function _donateToken(address to, uint256 amount) internal virtual {}

    // @dev Loss is between lossToleranceBps and maxDecreaseDefault and is covered by junior holders
    function testDepositWithLossCovered() external virtual {
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
    function testDepositWithLossSocialized(uint256 depositAmountAARatio) external virtual {
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

        uint256 prePrice = strategy.price();
        uint256 unclaimedFees = idleCDO.unclaimedFees();

        // deposit underlying to the strategy
        _cdoHarvest(true);
        // now let's simulate a loss by decreasing strategy price
        // curr price - about 0.25%
        _createLoss(idleCDO.lossToleranceBps() / 2);

        uint256 priceDelta = ((prePrice - strategy.price()) * ONE_SCALE) / prePrice;
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

    // @dev Loss is > maxDecreaseDefault and is absorbed by junior holders if possible
    function testDepositRedeemWithLossShutdown() external virtual {
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

    // @dev Loss is between lossToleranceBps and maxDecreaseDefault and is covered by junior holders
    function testRedeemWithLossCovered() external virtual {
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

        assertApproxEqRel(resAA, amount, 0.0001 * 1e18, "AA price after loss"); // 1e18 == 100%
        // juniors lost about 5% as there were seniors to cover
        assertApproxEqRel(resBB, (amount * 95_000) / 100_000, 0.0001 * 1e18, "BB price after loss"); // 1e18 == 100%

        assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
        assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
        assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    // @dev Loss is between 0% and lossToleranceBps and is socialized
    function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external virtual {
        vm.assume(depositAmountAARatio >= 0);
        vm.assume(depositAmountAARatio <= FULL_ALLOC);
    
        vm.prank(idleCDO.owner());
        idleCDO.setLossToleranceBps(500);

        uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
        uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;

        idleCDO.depositAA(amountAA);
        idleCDO.depositBB(amountBB);
        uint256 prePrice = strategy.price();

        // deposit underlying to the strategy
        _cdoHarvest(true);

        // now let's simulate a loss by decreasing strategy price
        // curr price - about 0.25%
        _createLoss(idleCDO.lossToleranceBps() / 2);

        uint256 priceDelta = ((prePrice - strategy.price()) * ONE_SCALE) / prePrice;
        uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));
        uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));

        // redeem all
        uint256 resAA;
        if (depositAmountAARatio > 0) {
            resAA = idleCDO.withdrawAA(0);
        }

        uint256 resBB;
        if (depositAmountAARatio < FULL_ALLOC) {
            resBB = idleCDO.withdrawBB(0);
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
        assertApproxEqAbs(
            idleCDO.trancheAPRSplitRatio(), 
            _calcNewAPRSplit(idleCDO.getCurrentAARatio()), 
            25,
            "split ratio on redeem"
        );
    }

    function testCheckMaxDecreaseDefault() external virtual {
        _testCheckMaxDecreaseDefault(10000 * ONE_SCALE);
    }

    function _testCheckMaxDecreaseDefault(uint256 amount) internal virtual {
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

    function _doDepositsWithInterest(uint256 aa, uint256 bb) 
        internal virtual
        returns (uint256 priceAA, uint256 priceBB) {
        vm.startPrank(owner);
        idleCDO.setReleaseBlocksPeriod(0);
        vm.stopPrank();

        _pokeLendingProtocol();

        idleCDO.depositAA(aa);
        idleCDO.depositBB(bb);

        // deposit underlyings to the strategy
        _cdoHarvest(true);
        // accrue 7 days of interest + rewards
        _accrueInterest();

        _pokeLendingProtocol();

        priceAA = idleCDO.virtualPrice(address(AAtranche));
        priceBB = idleCDO.virtualPrice(address(BBtranche));
        assertGe(priceAA, ONE_SCALE - 1, 'AA price is >= 1');
        assertGe(priceBB, ONE_SCALE - 1, 'BB price is >= 1');
    }

    function _accrueInterest() internal virtual {
        // accrue some interest 
        skip(7 days);
        vm.roll(block.number + 7 * 7200);
        // claim and sell rewards
        _cdoHarvest(false);
        vm.roll(block.number + 1);
    }
}
