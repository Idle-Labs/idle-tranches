// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";

import "../../contracts/strategies/euler/IdleEulerStrategy.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/TrancheWrapper.sol";

contract TestERC4626TrancheWrapper is ERC4626Test {
    using stdStorage for StdStorage;

    uint256 internal decimals;
    uint256 internal ONE_SCALE;

    address public owner;
    IdleCDO internal idleCDO;
    IERC20Detailed internal underlying;
    IERC20Detailed internal strategyToken;
    IdleCDOTranche internal AAtranche;
    IdleCDOTranche internal BBtranche;
    IIdleCDOStrategy internal strategy;
    bytes internal extraData;
    bytes internal extraDataSell;

    TrancheWrapper internal trancheWrapper;

    function setUp() public override {
        setUpIdleCDO();

        // deploy trancheWrapper
        address tranche = idleCDO.AATranche();
        trancheWrapper = new TrancheWrapper(idleCDO, tranche);

        __underlying__ = address(underlying);
        __vault__ = address(trancheWrapper);
        __delta__ = 0;

        // fund
        uint256 initialBal = 1e10 * ONE_SCALE;
        deal(address(underlying), address(this), initialBal, true);

        // label
        vm.label(address(idleCDO), "idleCDO");
        vm.label(address(AAtranche), "AAtranche");
        vm.label(address(BBtranche), "BBtranche");
        vm.label(address(strategy), "strategy");
        vm.label(address(underlying), "underlying");
        vm.label(address(strategyToken), "strategyToken");
    }

    function setUpIdleCDO() public {
        owner = address(2);
        address _rebalancer = address(3);
        address[] memory _incentiveTokens = new address[](0);

        (address _strategy, address _underlying) = _deployStrategy(owner);
        idleCDO = _deployIdleCDO();

        stdstore.target(address(idleCDO)).sig(idleCDO.token.selector).checked_write(address(0));
        idleCDO.initialize(
            0,
            _underlying,
            address(this), // governanceFund,
            owner, // owner,
            _rebalancer, // rebalancer,
            _strategy, // strategyToken
            20000, // apr split: 100000 is 100% to AA
            50000, // ideal value: 50% AA and 50% BB tranches
            _incentiveTokens
        );

        underlying = IERC20Detailed(idleCDO.token());
        decimals = underlying.decimals();
        ONE_SCALE = 10**decimals;
        strategy = IIdleCDOStrategy(idleCDO.strategy());
        strategyToken = IERC20Detailed(strategy.strategyToken());
        AAtranche = IdleCDOTranche(idleCDO.AATranche());
        BBtranche = IdleCDOTranche(idleCDO.BBTranche());

        vm.startPrank(owner);
        idleCDO.setIsAYSActive(true);
        idleCDO.setUnlentPerc(0);
        idleCDO.setFee(0);

        IdleEulerStrategy(address(strategy)).setWhitelistedCDO(address(idleCDO));
        vm.stopPrank();
    }

    function _deployStrategy(address _owner) internal returns (address _strategy, address _underlying) {
        address eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
        address lendingToken = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716; // eUSDC
        _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        _strategy = address(new IdleEulerStrategy());
        stdstore.target(_strategy).sig(IIdleCDOStrategy.token.selector).checked_write(address(0));
        IdleEulerStrategy(_strategy).initialize(lendingToken, _underlying, eulerMain, _owner);
    }

    function _deployIdleCDO() internal returns (IdleCDO _cdo) {
        _cdo = new IdleCDO();
    }

    function setupVault(Init memory init) public override {
        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));

            // shares
            uint256 shares = init.share[i];
            try IERC20(__underlying__).transfer(user, shares) {} catch { vm.assume(false); } // prettier-ignore
            _approve(__underlying__, user, __vault__, shares);
            vm.prank(user);
            try IERC4626(__vault__).deposit(shares, user) {} catch { vm.assume(false); } // prettier-ignore
            vm.roll(block.number + 1); // avoid the same tx from the same tx.origin and same block.number

            // assets
            uint256 assets = init.asset[i];
            try IERC20(__underlying__).transfer(user, assets) {} catch {
                vm.assume(false);
            }
        }

        // setup initial yield for vault
        setupYield(init);
    }

    function setupYield(Init memory init) public override {
        if (init.yield >= 0) {
            // gain
            uint256 gain = uint256(init.yield);
            try IERC20(__underlying__).transfer(__vault__, gain) {} catch { vm.assume(false); } // prettier-ignore
        } else {
            vm.assume(false); // no loss
        }
    }
}
