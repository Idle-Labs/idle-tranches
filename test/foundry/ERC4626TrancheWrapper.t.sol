// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ERC4626Test, IERC4626} from "erc4626-tests/ERC4626.test.sol";

import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockIdleToken.sol";
import "../../contracts/strategies/idle/IdleStrategy.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/TrancheWrapper.sol";

import "forge-std/Test.sol";

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
        trancheWrapper = new TrancheWrapper();
        stdstore.target(address(trancheWrapper)).sig(trancheWrapper.token.selector).checked_write(address(0));

        trancheWrapper.initialize(idleCDO, tranche);

        _underlying_ = address(underlying);
        _vault_ = address(trancheWrapper);
        _delta_ = 10;

        // fund
        uint256 initialBal = 1e10 * ONE_SCALE;
        deal(address(underlying), address(this), initialBal, true);
        deal(address(underlying), address(strategy.strategyToken()), initialBal, true);

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
            20000 // apr split: 100000 is 100% to AA
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
        idleCDO._setLimit(0);

        IdleStrategy(address(strategy)).setWhitelistedCDO(address(idleCDO));
        vm.stopPrank();
    }

    function _deployStrategy(address _owner) internal returns (address _strategy, address _underlying) {
        _underlying = address(new MockERC20("MockDAI", "MockDAI"));
        MockIdleToken idleToken = new MockIdleToken(_underlying);
        idleToken.setTokenPriceWithFee(1.2 * 10**18);

        _strategy = address(new IdleStrategy());
        stdstore.target(_strategy).sig(IIdleCDOStrategy.token.selector).checked_write(address(0));
        IdleStrategy(_strategy).initialize(address(idleToken), _owner);
    }

    function _deployIdleCDO() internal returns (IdleCDO _cdo) {
        _cdo = new IdleCDO();
    }

    function setUpVault(Init memory init) public override {
        // used to avoid "The vm.assume cheatcode rejected too many inputs" error
        // see https://github.com/a16z/erc4626-tests/issues/3#issuecomment-1311218476
        init = clamp(init, type(uint120).max);

        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));

            // shares
            uint256 shares = init.share[i];
            try IERC20(_underlying_).transfer(user, shares) {} catch { vm.assume(false); } // prettier-ignore
            _approve(_underlying_, user, _vault_, shares);
            vm.prank(user);
            try IERC4626(_vault_).deposit(shares, user) {} catch { vm.assume(false); } // prettier-ignore
            vm.roll(block.number + 1); // avoid the same tx from the same tx.origin and same block.number

            // assets
            uint256 assets = init.asset[i];
            try IERC20(_underlying_).transfer(user, assets) {} catch {
                vm.assume(false);
            }
        }

        // setup initial yield for vault
        setUpYield(init);
    }

    function setUpYield(Init memory init) public override {
        if (init.yield >= 0) {
            // gain
            uint256 gain = uint256(init.yield);
            try IERC20(_underlying_).transfer(_vault_, gain) {} catch { vm.assume(false); } // prettier-ignore
        } else {
            vm.assume(false); // no loss
        }
    }

    function clamp(Init memory init, uint256 max) internal pure returns (Init memory) {
        for (uint256 i = 0; i < N; i++) {
            init.share[i] = init.share[i] % max;
            init.asset[i] = init.asset[i] % max;
        }
        init.yield = init.yield % int256(max);
        return init;
    }
}
