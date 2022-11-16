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
            0, // NOTE: apr split: 0% to AA
            0, // deprecated
            incentiveTokens
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
        // // deposit small amount in the senior
        // deal(address(underlying), address(2), 10 * ONE_SCALE, true);
        // idleCDO.depositAA(10 * ONE_SCALE);
    }

    function testInitialize() external override {
        this.testInitialize();
        assertEq(idleCDO.isAYSActive(), false);
        assertEq(idleCDO.trancheAPRSplitRatio(), 0);
    }

    function testOnlyIdleCDO() public override runOnForkingNetwork(MAINNET_CHIANID) {}

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdleStrategy(address(strategy)).initialize(idleUSDT, owner);
    }
}
