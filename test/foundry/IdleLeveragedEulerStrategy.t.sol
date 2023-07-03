// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../contracts/strategies/euler/IdleLeveragedEulerStrategy.sol";

import "forge-std/Test.sol";

import "./TestIdleCDOBase.sol";
import "../../contracts/IdleCDOLeveregedEulerVariant.sol";

contract TestIdleEulerLeveragedStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    uint256 internal constant EXP_SCALE = 1e18;

    uint256 internal constant ONE_FACTOR_SCALE = 1_000_000_000;

    uint256 internal constant CONFIG_FACTOR_SCALE = 4_000_000_000;

    uint256 internal constant SELF_COLLATERAL_FACTOR = 0.95 * 4_000_000_000;

    /// @notice Euler markets contract address
    IMarkets internal constant EULER_MARKETS = IMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);

    /// @notice Euler general view contract address
    IEulerGeneralView internal constant EULER_GENERAL_VIEW =
        IEulerGeneralView(0xACC25c4d40651676FEEd43a3467F3169e3E68e42);

    IExec internal constant EULER_EXEC = IExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

    address internal constant EUL = 0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant INITIAL_TARGET_HEALTH = 1.2 * 1e18;

    ISwapRouter internal router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    IEulDistributor public eulDistributor;

    address internal eulerMain;

    IEToken internal eToken;

    IDToken internal dToken;

    bytes internal path;

    function _updateClaimable(uint256 _new) internal {
        extraData = abi.encode(uint256(_new), new bytes32[](0), uint256(0));
    }

    function _selectFork() public override {
        vm.createSelectFork("mainnet", 15576018);
    }

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
        eToken = IEToken(0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716); // eUSDC
        dToken = IDToken(0x84721A3dB22EB852233AEAE74f9bC8477F8bcc42); // dUSDC
        bytes[] memory _extraPath = new bytes[](1);
        _extraPath[0] = abi.encodePacked(EUL, uint24(10000), USDC);
        extraDataSell = abi.encode(_extraPath);
        _underlying = USDC;

        strategy = new IdleLeveragedEulerStrategy();
        _strategy = address(strategy);

        eulDistributor = new EulDistributorMock();
        deal(EUL, address(eulDistributor), 1e23, true);
        deal(_underlying, address(1), 1e23, true);
        deal(_underlying, address(2), 1e23, true);

        // claim data
        _updateClaimable(1000e18);
        extraRewards = 1;
        // v3 router path
        path = abi.encodePacked(EUL, uint24(10000), WETH9, uint24(3000), _underlying);
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        IdleLeveragedEulerStrategy(_strategy).initialize(
            eulerMain,
            address(eToken),
            address(dToken),
            _underlying,
            _owner,
            address(eulDistributor),
            address(router),
            path,
            INITIAL_TARGET_HEALTH
        );

        vm.label(eulerMain, "euler");
        vm.label(address(eToken), "eToken");
        vm.label(address(dToken), "dToken");
        vm.label(WETH9, "WETH9");
        vm.label(address(eulDistributor), "eulDist");
        vm.label(address(router), "router");
    }

    function _deployCDO() internal override returns (IdleCDO _cdo) {
        _cdo = new IdleCDOLeveregedEulerVariant();
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.startPrank(_owner);
        IdleLeveragedEulerStrategy(address(strategy)).setWhitelistedCDO(_cdo);
        IdleCDOLeveregedEulerVariant(_cdo).setMaxDecreaseDefault(1000); // 1%
        vm.stopPrank();

        vm.prank(address(1));
        IERC20Detailed(USDC).approve(_cdo, type(uint256).max);
        vm.prank(address(2));
        IERC20Detailed(USDC).approve(_cdo, type(uint256).max);
    }

    function testInitialize() public override {
        assertEq(idleCDO.token(), address(underlying));
        assertGe(strategy.price(), ONE_SCALE);
        assertEq(idleCDO.tranchePrice(address(AAtranche)), ONE_SCALE);
        assertEq(idleCDO.tranchePrice(address(BBtranche)), ONE_SCALE);
        assertEq(initialAAApr, 0);
        assertEq(initialBBApr, initialApr);
        assertEq(idleCDO.maxDecreaseDefault(), 1000);
    }

    function testMultipleRedeemsWithRewards() external {
        uint256 amount = 10000 * ONE_SCALE;
        uint256 balBefore = underlying.balanceOf(address(this));
        uint256 balBefor1 = underlying.balanceOf(address(1));
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);
        uint256 aaBal = IERC20Detailed(address(AAtranche)).balanceOf(address(this));
        uint256 bbBal = IERC20Detailed(address(BBtranche)).balanceOf(address(this));
        uint256 pricePre = strategy.price();
        // funds in lending
        _cdoHarvest(true, true);
        // accrue some loss
        skip(7 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() / 2);
        
        uint256 pricePost = strategy.price();
        // here we didn't harvested any rewards and 
        // borrow apy > supply apr so the strategy price decreases
        assertLt(pricePost, pricePre, 'Strategy price did not decrease, loss not reported');
        
        // deposit with another user, price for mint is still oneToken
        vm.startPrank(address(1));
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);
        vm.stopPrank();
        // put new fund in lending
        _cdoHarvest(true, true);

        uint256 aaBal1 = IERC20Detailed(address(AAtranche)).balanceOf(address(1));
        uint256 bbBal1 = IERC20Detailed(address(BBtranche)).balanceOf(address(1));
        assertEq(aaBal1, aaBal, 'AA balance minted is != than before');
        assertEq(bbBal1, bbBal, 'BB balance minted is != than before');
        // accrue some more loss
        skip(7 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() / 2);

        // claim accrued euler tokens but do not release rewards
        _cdoHarvest(false, true);

        skip(7 days);
        // release half rewards
        vm.roll(block.number + _strategyReleaseBlocksPeriod() / 2);

        vm.startPrank(address(1));
        idleCDO.withdrawAA(aaBal1);
        idleCDO.withdrawBB(bbBal1);
        vm.stopPrank();

        idleCDO.withdrawAA(aaBal);
        idleCDO.withdrawBB(bbBal);

        uint256 balAfter = underlying.balanceOf(address(this));
        uint256 balAfter1 = underlying.balanceOf(address(1));
        assertLt(balBefore, balAfter, 'underlying balance for address(this) is < than before');
        assertLt(balBefor1, balAfter1, 'underlying balance for address(1) is < than before');
        uint256 increaseThis = balAfter - balBefore;
        uint256 increase1 = balAfter1 - balBefor1;
        assertGe(increaseThis, increase1, "gain for address this is < than gain of addr(1)");
    }

    function testLeverageManually() external {
        // set targetHealthScore
        vm.prank(owner);
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(0); // no lev

        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        // funds in lending
        _cdoHarvest(true, true);
        assertEq(_getCurrentLeverage(), 0, 'Not levereged');
        assertEq(dToken.balanceOf(address(strategy)), 0, 'Current strategy has no debt');

        uint256 targetHealth = 110 * EXP_SCALE / 100;
        vm.prank(owner);
        // deleverege all and set target health to special value 0 ie no leverage
        IdleLeveragedEulerStrategy(address(strategy)).leverageManually(targetHealth);

        assertApproxEqRel(
            _getCurrentLeverage(),
            6 * ONE_SCALE,
            2e16, // 0.2
            'Current target health does not match expected one'
        );
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealth,
            1e15, // 0.1%
            'Current target health does not match expected one'
        );
        assertGt(dToken.balanceOf(address(strategy)), 0, 'Current strategy has debt');

        idleCDO.depositAA(amount);

        assertApproxEqRel(
            _getCurrentLeverage(),
            6 * ONE_SCALE,
            2e16, // 0.2
            'Current target health does not match expected one after deposit'
        );
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealth,
            1e15, // 0.1%
            'Current target health does not match expected one after deposit'
        );
        assertGt(dToken.balanceOf(address(strategy)), 0, 'Current strategy has debt after another deposit');
    }

    function testDeleverageAllManually() external {
        // set targetHealthScore
        vm.prank(owner);
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(105 * EXP_SCALE / 100); // 1.05

        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        // funds in lending
        _cdoHarvest(true, true);
        assertGt(_getCurrentLeverage(), ONE_SCALE, 'Not levereged');
        assertGt(dToken.balanceOf(address(strategy)), 0, 'Current strategy has no debt');

        vm.prank(owner);
        // deleverege all and set target health to special value 0 ie no leverage
        IdleLeveragedEulerStrategy(address(strategy)).deleverageManually(0);

        assertEq(_getCurrentLeverage(), 0, 'Still levereged');
        assertEq(_getCurrentHealthScore(), 0, 'Current target health is not 0');
        assertEq(dToken.balanceOf(address(strategy)), 0, 'Current strategy has debt');

        idleCDO.depositAA(amount);

        assertEq(_getCurrentLeverage(), 0, 'Still levereged');
        assertEq(_getCurrentHealthScore(), 0, 'Current target health is not 0 after another deposit');
        assertEq(dToken.balanceOf(address(strategy)), 0, 'Current strategy has debt after another deposit');
    }

    function testDeleverageManually() external {
        // set targetHealthScore
        vm.prank(owner);
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(105 * EXP_SCALE / 100); // 1.05

        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        // funds in lending
        _cdoHarvest(true, true);
        uint256 initialLev = _getCurrentLeverage();
        assertGt(initialLev, ONE_SCALE, 'Not levereged');
        assertGt(dToken.balanceOf(address(strategy)), 0, 'Current strategy has no debt');

        uint256 _targetHealthScore = 2 * EXP_SCALE; // 1.1
        // uint256 _targetHealthScore = 110 * EXP_SCALE / 100; // 1.1
        vm.prank(owner);
        // half leverage
        IdleLeveragedEulerStrategy(address(strategy)).deleverageManually(_targetHealthScore);
        
        assertEq(_getTargetHealthScore(), _targetHealthScore, 'target health score not updated');
        assertApproxEqRel(
            _getCurrentHealthScore(),
            _targetHealthScore,
            1e15, // 0.1%
            'Current health does not match expected one'
        );
        assertGt(dToken.balanceOf(address(strategy)), 0, 'Current strategy has debt');

        idleCDO.depositAA(amount);

        assertApproxEqRel(
            _getCurrentHealthScore(),
            _targetHealthScore,
            1e15, // 0.1%
            'Current target health does not match expected one after deposit'
        );
        assertGt(dToken.balanceOf(address(strategy)), 0, 'Current strategy has debt after another deposit');
    }

    function testRedeemsWithRewards() external {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);
        uint256 pricePre = strategy.price();
        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);
        uint256 pricePost = strategy.price();
        // here we didn't harvested any rewards and 
        // borrow apy > supply apr so the strategy price decreases
        assertLt(pricePost, pricePre, 'Strategy price correctly decreased');
 
        // claim accrued euler tokens
        _cdoHarvest(false);
        skip(7 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);

        idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
        idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));

        assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
        assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
        assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    function testRedeems() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);
        uint256 pricePre = strategy.price();
        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);
        uint256 pricePost = strategy.price();
        // here we didn't harvested any rewards and 
        // borrow apy > supply apr so the strategy price decreases
        assertLt(pricePost, pricePre, 'Strategy price correctly decreased');
 
        idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
        idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));

        assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
        assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
        // balance should be less than the initial if no rewards are sold
        assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    function testGetSelfAmountToMint(uint32 target, uint32 unit) external {
        vm.assume(target > 1 && target <= 20);
        vm.assume(unit > 100 && unit <= 10000);

        uint256 amount = unit * ONE_SCALE;
        uint256 targetHealthScore = target * EXP_SCALE;

        _strategyDeposit(targetHealthScore, amount);

        assertLe(underlying.balanceOf(address(strategy)), 10);

        // maxPercentDelta 1e18 == 100%
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealthScore,
            1e15, // 0.1%
            "!target health score before"
        );

        _strategyDeposit(targetHealthScore, amount);

        assertLe(underlying.balanceOf(address(strategy)), 10);

        // maxPercentDelta 1e18 == 100%
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealthScore,
            1e15, // 0.1%
            "!target health score after"
        );
    }

    function testLeverageAndDeleverageWithMint(uint256 target) external {
        vm.assume(target > 1 && target < 20);

        uint256 amount = 10000 * ONE_SCALE;
        uint256 initialTargetHealth = 20 * EXP_SCALE;
        uint256 targetHealthScore = target * EXP_SCALE;

        // first deposit
        _strategyDeposit(initialTargetHealth, amount);

        assertLe(underlying.balanceOf(address(strategy)), 10);

        // maxPercentDelta 1e18 == 100%
        assertApproxEqRel(
            _getCurrentHealthScore(),
            initialTargetHealth,
            1e15, // 0.1%
            "!target health score"
        );

        // leverage
        _strategyDeposit(targetHealthScore, amount / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertLe(_getCurrentHealthScore(), initialTargetHealth, "hs < initial hs");

        // deleverage
        _strategyDeposit(initialTargetHealth, amount / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertGe(_getCurrentHealthScore(), targetHealthScore, "hs > initial hs");
    }

    function testGetSelfAmountToBurn(uint32 target, uint32 unit) external {
        vm.assume(target > 1 && target <= 20);
        vm.assume(unit > 100 && unit <= 10000);

        uint256 amount = unit * ONE_SCALE;
        uint256 targetHealthScore = target * EXP_SCALE;

        _strategyDeposit(targetHealthScore, amount);

        uint256 amountAA = IERC20(AAtranche).balanceOf(address(this));
        _strategyWithdraw(targetHealthScore, amountAA / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealthScore,
            1e15, // 0.1%
            "!target health score before"
        );

        _strategyWithdraw(targetHealthScore, amountAA / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealthScore,
            1e15, // 0.1%
            "!target health score after"
        );
    }

    function testLeverageAndDeleverageWithBurn(uint256 target) external {
        vm.assume(target > 1 && target < 20);

        uint256 amount = 10000 * ONE_SCALE;
        uint256 initialTargetHealth = 20 * EXP_SCALE;
        uint256 targetHealthScore = target * EXP_SCALE;

        // first deposit
        _strategyDeposit(initialTargetHealth, amount);

        // leverage
        uint256 amountAA = IERC20(AAtranche).balanceOf(address(this));
        _strategyWithdraw(targetHealthScore, amountAA / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertLe(_getCurrentHealthScore(), initialTargetHealth, "hs < initial hs");

        // deleverage
        _strategyWithdraw(initialTargetHealth, amountAA / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertGe(_getCurrentHealthScore(), targetHealthScore, "hs > initial hs");
    }

    function testDefaultCheck() external {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        // accrue some debt as no rewards are harvested
        skip(365 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);
        // try to exit the position but it will fail with status reason "4" (defaulted)
        uint256 balAA = IERC20Detailed(address(AAtranche)).balanceOf(address(this));
        vm.expectRevert(bytes('4'));
        idleCDO.withdrawAA(balAA);

        uint256 balBB = IERC20Detailed(address(BBtranche)).balanceOf(address(this));
        vm.expectRevert(bytes('4'));
        idleCDO.withdrawBB(balBB);
    }

    function _strategyDeposit(uint256 targetHealthScore, uint256 amount) internal {
        // set targetHealthScore
        vm.prank(owner);
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(targetHealthScore);

        idleCDO.depositAA(amount);
        // deposit to Euler
        _cdoHarvest(true);
    }

    function _strategyWithdraw(uint256 targetHealthScore, uint256 amountAA) internal {
        // set targetHealthScore
        vm.prank(owner);
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(targetHealthScore);

        uint256 amount = (amountAA * idleCDO.virtualPrice(address(AAtranche))) / 1e18;
        uint256 amtToBurn = IdleLeveragedEulerStrategy(address(strategy)).getSelfAmountToBurn(
            targetHealthScore,
            amount
        );
        assertLe(amtToBurn, amount, "amtToBurn < amountAA");

        idleCDO.withdrawAA(amountAA);
    }

    function _getCurrentHealthScore() internal view returns (uint256) {
        return IdleLeveragedEulerStrategy(address(strategy)).getCurrentHealthScore();
    }
    function _getTargetHealthScore() internal view returns (uint256) {
        return IdleLeveragedEulerStrategy(address(strategy)).targetHealthScore();
    }

    function _getCurrentLeverage() internal view returns (uint256) {
        return IdleLeveragedEulerStrategy(address(strategy)).getCurrentLeverage();
    }

    function testSetInvalidTargetHealthScore() public {
        vm.prank(owner);
        vm.expectRevert(bytes("strat/invalid-target-hs"));
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(1e18);
    }

    function testOnlyOwner() public override {
        super.testOnlyOwner();

        IdleLeveragedEulerStrategy _strategy = IdleLeveragedEulerStrategy(address(strategy));
        vm.startPrank(address(0xbabe));
        vm.expectRevert(bytes("!AUTH"));
        _strategy.setTargetHealthScore(2e18);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setEulDistributor(address(0xabcd));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setSwapRouter(address(0xabcd));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setRebalancer(address(22));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setRouterPath(path);

        vm.expectRevert(bytes("!AUTH"));
        _strategy.deleverageManually(2e18);

        vm.expectRevert(bytes("!AUTH"));
        _strategy.leverageManually(2e18);
        vm.stopPrank();
    }

    function testOnlyRebalancer() public {
        IdleLeveragedEulerStrategy _strategy = IdleLeveragedEulerStrategy(address(strategy));
        vm.prank(owner);
        _strategy.setRebalancer(address(0xdead));
        
        vm.startPrank(address(0xbabe));
        vm.expectRevert(bytes("!AUTH"));
        _strategy.setTargetHealthScore(2e18);

        vm.expectRevert(bytes("!AUTH"));
        _strategy.deleverageManually(2e18);
        vm.stopPrank();

        idleCDO.depositAA(1000 * ONE_SCALE);
        _cdoHarvest(true, true);

        vm.startPrank(address(0xdead));
        _strategy.setTargetHealthScore(2e18);
        _strategy.leverageManually(2e18);
        _strategy.deleverageManually(0);
        vm.stopPrank();
    }

    function testCantReinitialize() external override {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdleLeveragedEulerStrategy(address(strategy)).initialize(
            address(0xbabe),
            address(eToken),
            address(dToken),
            address(underlying),
            owner,
            address(eulDistributor),
            address(router),
            hex"",
            INITIAL_TARGET_HEALTH
        );
    }

    function _cdoHarvest(bool _skipRewards, bool _skipRelease) internal {
        uint256 numOfRewards = rewards.length;
        bool[] memory _skipFlags = new bool[](4);
        bool[] memory _skipReward = new bool[](numOfRewards);
        uint256[] memory _minAmount = new uint256[](numOfRewards);
        uint256[] memory _sellAmounts = new uint256[](numOfRewards);
        bytes[] memory _extraData = new bytes[](2);
        // bytes memory _extraData = abi.encode(uint256(0), uint256(0), uint256(0));
        if(!_skipRewards){
            _extraData[0] = extraData;
            _extraData[1] = extraDataSell;
        }
        // skip fees distribution
        _skipFlags[3] = _skipRewards;

        vm.prank(idleCDO.rebalancer());
        idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

        // linearly release all sold rewards
        if (!_skipRelease) {
            vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1); 
        }
    }
}

contract EulDistributorMock is IEulDistributor {
    /// @notice Claim distributed tokens
    /// @param account Address that should receive tokens
    /// @param token Address of token being claimed (ie EUL)
    /// @param - Merkle proof that validates this claim
    /// @param - If non-zero, then the address of a token to auto-stake to, instead of claiming
    function claim(
        address account,
        address token,
        uint256 claimable,
        bytes32[] calldata,
        address
    ) external {
        IERC20Detailed(token).transfer(account, claimable);
    }
    function claimed(address, address) external view returns (uint256) {}
}
