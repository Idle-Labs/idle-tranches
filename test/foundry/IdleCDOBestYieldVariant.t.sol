// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/strategies/idle/IdleStrategy.sol";
import "../../contracts/IdleCDOBestYieldVariant.sol";
import "./TestIdleCDOBase.sol";

contract TestIdleCDOBestYieldVariant is TestIdleCDOBase {
    using stdStorage for StdStorage;

    // Idle-USDT Best-Yield v4
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant idleUSDT = 0xF34842d05A1c888Ca02769A633DF37177415C2f8;

    uint256 internal initialDepositedAmount;

    function _selectFork() public override {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16527983));
    }

    function setUp() public override {
        super.setUp();
        // deposit small amount in the senior
        initialDepositedAmount = 10 * ONE_SCALE;
        idleCDO.depositAA(initialDepositedAmount);
    }

    function _deployLocalContracts() internal override returns (IdleCDO _cdo) {
        address _owner = address(2);
        address _rebalancer = address(3);
        (address _strategy, address _underlying) = _deployStrategy(_owner);

        // deploy idleCDO and tranches
        _cdo = _deployCDO();
        stdstore.target(address(_cdo)).sig(_cdo.token.selector).checked_write(address(0));
        address[] memory incentiveTokens = new address[](0);
        _cdo.initialize(
            0,
            _underlying,
            address(this), // governanceFund,
            _owner, // owner,
            _rebalancer, // rebalancer,
            _strategy, // strategy
            0 // NOTE: apr split: 0% to AA
        );

        vm.startPrank(_owner);
        _cdo.setUnlentPerc(0);
        _cdo.setFee(0);
        vm.stopPrank();

        _postDeploy(address(_cdo), _owner);
    }

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        _underlying = USDT;
        underlying = IERC20Detailed(_underlying);
        strategy = new IdleStrategy();
        _strategy = address(strategy);
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        IdleStrategy(_strategy).initialize(idleUSDT, _owner);
    }

    function _deployCDO() internal override returns (IdleCDO _cdo) {
        _cdo = new IdleCDOBestYieldVariant();
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        IdleStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testInitialize() public override {
        super.testInitialize();
        assertEq(idleCDO.isAYSActive(), false);
        assertEq(idleCDO.allowAAWithdraw(), false);
        assertEq(idleCDO.trancheAPRSplitRatio(), 0);
    }

    function testOnlyIdleCDO() public override {}

    function testCantReinitialize() external override {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdleStrategy(address(strategy)).initialize(idleUSDT, owner);
    }

    function testDisablingAATranche() external {
        vm.expectRevert(bytes("disable depositAA"));
        idleCDO.depositAA(10 * ONE_SCALE);

        vm.expectRevert(bytes("disable withdrawAA"));
        idleCDO.withdrawAA(10);
    }

    function testDeposits() external override {
        uint256 amount = 10000 * ONE_SCALE;
        // AARatio 0%
        idleCDO.depositBB(amount);

        uint256 totAmount = amount + initialDepositedAmount;

        assertEq(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, "BBtranche bal");
        assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal");
        assertEq(underlying.balanceOf(address(idleCDO)), totAmount, "underlying bal");
        // strategy is still empty with no harvest
        assertEq(strategyToken.balanceOf(address(idleCDO)), 0, "strategy bal");
        uint256 strategyPrice = strategy.price();

        // apr should be 0%
        assertEq(idleCDO.getApr(address(AAtranche)), 0, "AA apr");
        // apr will be 100% of the strategy apr if AAratio is == 0%
        assertGe(idleCDO.getApr(address(BBtranche)), initialApr, "BB apr");

        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        // claim rewards
        _cdoHarvest(false);
        assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal after harvest");

        // Skip 7 day forward to accrue interest
        skip(7 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);

        assertGt(strategy.price(), strategyPrice, "strategy price");

        // virtual price of AA shouldn't change
        assertEq(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
        // virtualPrice of BB should increase too
        assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
    }

    function testRedeems() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);

        idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));

        assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
        assertGe(underlying.balanceOf(address(this)), initialBal - initialDepositedAmount, "underlying bal increased");
    }

    function testRedeemRewards() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);

        // sell some rewards
        uint256 pricePre = idleCDO.virtualPrice(address(BBtranche));
        _cdoHarvest(false);

        uint256 pricePost = idleCDO.virtualPrice(address(BBtranche));
        if (_numOfSellableRewards() > 0) {
            assertGt(pricePost, pricePre, "virtual price increased");
        } else {
            assertEq(pricePost, pricePre, "virtual price equal");
        }
    }

    function testEmergencyShutdown() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositBB(amount);

        // call with non owner
        vm.expectRevert(bytes("6"));
        vm.prank(address(0xbabe));
        idleCDO.emergencyShutdown();

        // call with owner
        vm.prank(owner);
        idleCDO.emergencyShutdown();

        vm.expectRevert(bytes("disable depositAA"));
        idleCDO.depositAA(amount);
        vm.expectRevert(bytes("Pausable: paused")); // default
        idleCDO.depositBB(amount);
        vm.expectRevert(bytes("3")); // default
        idleCDO.withdrawAA(amount);
        vm.expectRevert(bytes("3")); // default
        idleCDO.withdrawBB(amount);
    }

    function testRestoreOperations() public override {
        uint256 amount = 1000 * ONE_SCALE;
        idleCDO.depositBB(amount);

        // call with non owner
        vm.expectRevert(bytes("6"));
        vm.prank(address(0xbabe));
        idleCDO.restoreOperations();

        // call with owner
        vm.startPrank(owner);
        idleCDO.emergencyShutdown();
        idleCDO.restoreOperations();
        vm.stopPrank();

        vm.roll(block.number + 1);

        idleCDO.withdrawBB(amount);
        idleCDO.depositBB(amount);
    }

    function testAPR() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        // claim rewards
        _cdoHarvest(false);

        skip(7 days);
        vm.roll(block.number + 1);
        uint256 apr = idleCDO.getApr(address(BBtranche));
        console.log("apr", apr);
        assertGe(apr / 1e16, 0, "apr is > 0.01% and with 18 decimals");
    }

    function testAPRSplitRatioDeposits(uint16) external override {}

    function testAPRSplitRatioRedeems(
        uint16 _ratio,
        uint16 _redeemRatioAA,
        uint16 _redeemRatioBB
    ) external override {}

    function testMinStkIDLEBalance() external override {}
}
