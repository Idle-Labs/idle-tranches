// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {ERC4626Test, IERC4626} from "erc4626-tests/ERC4626.test.sol";

import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockIdleToken.sol";
import "../../contracts/IdleTokenWrapper.sol";

import "forge-std/Test.sol";

contract TestERC4626IdleTokenWrapper is ERC4626Test {
    using stdStorage for StdStorage;

    uint256 internal decimals;
    uint256 internal ONE_TOKEN;

    address public owner;
    address internal idleToken;
    IERC20Detailed internal underlying;
    IdleTokenWrapper internal idleTokenWrapper;

    function setUp() public override {
        setUpIdleToken();

        idleTokenWrapper = new IdleTokenWrapper();
        idleTokenWrapper.initialize(IIdleTokenFungible(idleToken));

        _underlying_ = address(underlying);
        _vault_ = address(idleTokenWrapper);
        _delta_ = 10;

        // fund
        uint256 initialBal = 1e10 * ONE_TOKEN;
        deal(address(underlying), address(this), initialBal, true);

        // label
        vm.label(address(idleTokenWrapper), "wrapper");
        vm.label(address(idleToken), "idleToken");
        vm.label(address(underlying), "underlying");
    }

    function setUpIdleToken() public {
        owner = address(2);

        address _underlying = address(new MockERC20("Underlying", "UNDERLYING"));
        idleToken = address(new MockIdleToken(_underlying));
        MockIdleToken(idleToken).setTokenPriceWithFee(1.2 * 10**18);

        underlying = IERC20Detailed(_underlying);
        decimals = underlying.decimals();
        ONE_TOKEN = 10**decimals;
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