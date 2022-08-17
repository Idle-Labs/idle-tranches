// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../contracts/strategies/euler/IdleLeveragedEulerStrategy.sol";

import "forge-std/Test.sol";

import "./TestIdleCDOBase.sol";

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

    address internal constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant INITIAL_TARGET_HEALTH = 1.2 * 1e18;

    ISwapRouter internal router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    IEulDistributor public eulDistributor;

    address internal eulerMain;

    IEToken internal eToken;

    IDToken internal dToken;

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
        eToken = IEToken(0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716); // eUSDC
        dToken = IDToken(0x84721A3dB22EB852233AEAE74f9bC8477F8bcc42); // dUSDC
        _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        eulDistributor = new EulDistributorMock();
        deal(EUL, address(eulDistributor), 1000e18, true);
        // claim data
        extraData = abi.encode(uint256(10e18), new bytes32[](0));

        strategy = new IdleLeveragedEulerStrategy();
        strategyToken = IERC20Detailed(_strategy); // strategy itself
        _strategy = address(strategy);
        //  The path is a sequence of tokenAddress Fee tokenAddress, encoded in reverse order
        bytes memory path = abi.encode(address(underlying), uint24(3000), WETH9, uint24(10000), EUL);

        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        IdleLeveragedEulerStrategy(_strategy).initialize(
            "LeverageEulerStrat",
            "LEVERAGE_EULER",
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
        vm.label(address(eulDistributor), "eulDist");
        vm.label(address(router), "router");
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        IdleLeveragedEulerStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testSwap() public {
        // swap EUL for underlying
        uint256 amountIn = 10e18;
        bytes memory path = abi.encode(address(underlying), uint24(3000), WETH9, uint24(10000), EUL);
        deal(EUL, address(this), amountIn, true);
        IERC20Detailed(EUL).approve(address(router), amountIn);
        router.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
    }

    function testGetSelfAmountToMint(uint256 target) external runOnForkingNetwork(MAINNET_CHIANID) {
        vm.assume(target > 1 && target <= 20);

        uint256 amount = 10000 * ONE_SCALE;
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

    function testLeverageAndDeleverageWithMint(uint256 target) external runOnForkingNetwork(MAINNET_CHIANID) {
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

    function testGetSelfAmountToBurn(uint256 target) external runOnForkingNetwork(MAINNET_CHIANID) {
        vm.assume(target > 1 && target <= 20);

        uint256 amount = 10000 * ONE_SCALE;
        uint256 targetHealthScore = target * EXP_SCALE;

        _strategyDeposit(targetHealthScore, amount);

        uint256 amountAA = IERC20(AAtranche).balanceOf(address(this));
        _strategyWithdraw(targetHealthScore, amountAA / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealthScore,
            1e15, // 0.1%
            "!target health score"
        );

        _strategyWithdraw(targetHealthScore, amountAA / 10);

        assertLe(underlying.balanceOf(address(strategy)), 10);
        assertApproxEqRel(
            _getCurrentHealthScore(),
            targetHealthScore,
            1e15, // 0.1%
            "!target health score"
        );
    }

    function testLeverageAndDeleverageWithBurn(uint256 target) external runOnForkingNetwork(MAINNET_CHIANID) {
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

    function testSetInvalidTargetHealthScore() public runOnForkingNetwork(MAINNET_CHIANID) {
        vm.prank(owner);
        vm.expectRevert(bytes("strat/invalid-target-hs"));
        IdleLeveragedEulerStrategy(address(strategy)).setTargetHealthScore(1e18);
    }

    function testOnlyOwner() public override runOnForkingNetwork(MAINNET_CHIANID) {
        super.testOnlyOwner();

        IdleLeveragedEulerStrategy _strategy = IdleLeveragedEulerStrategy(address(strategy));
        vm.startPrank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setTargetHealthScore(2e18);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setEulDistributor(address(0xabcd));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setSwapRouter(address(0xabcd));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.setRouterPath(abi.encode(address(underlying), 3000, WETH9, 10000, EUL));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        _strategy.deleverageMannualy(1000);
        vm.stopPrank();
    }

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdleLeveragedEulerStrategy(address(strategy)).initialize(
            "LeverageEulerStrat",
            "LEVERAGE_EULER",
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
}

contract EulDistributorMock is IEulDistributor {
    /// @notice Claim distributed tokens
    /// @param account Address that should receive tokens
    /// @param token Address of token being claimed (ie EUL)
    /// @param proof Merkle proof that validates this claim
    /// @param stake If non-zero, then the address of a token to auto-stake to, instead of claiming
    function claim(
        address account,
        address token,
        uint256 claimable,
        bytes32[] calldata proof,
        address stake
    ) external {
        IERC20Detailed(token).transfer(account, claimable);
    }
}
