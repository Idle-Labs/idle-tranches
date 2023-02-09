// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../contracts/interfaces/IIdleTokenFungible.sol";
import "../../contracts/IdleTokenFungible.sol";
import "../../contracts/IdleTokenWrapper.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract TestIdleTokenWrapper is Test {
    using stdStorage for StdStorage;
    using SafeERC20Upgradeable for IERC20Detailed;

    uint256 internal constant BLOCK_FOR_TEST = 16590720;
    uint256 internal constant ONE_18 = 1e18;
    // // IdleTokenFungible: IdleUSDC Junior tranches (idleUSDCBB)
    // address internal constant IDLE_TOKEN = 0xF6954B03d6a94Ba9e8C80CBE5824f22a401EE5D2;
    // IdleTokenFungible: IdleUSDT Junior tranches (idleUSDTBB)
    address internal constant IDLE_TOKEN = 0xfa3AfC9a194BaBD56e743fA3b7aA2CcbED3eAaad;

    address internal rebalancer;
    address internal owner;
    address[] internal allAvailableTokens;
    IIdleTokenFungible internal idleToken;
    IERC20Detailed internal underlying;
    uint256 internal decimals;
    uint256 internal ONE_TOKEN;

    uint256 internal initialBal;

    IdleTokenWrapper internal idleTokenWrapper;

    function setUp() public virtual {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), BLOCK_FOR_TEST));

        idleToken = IIdleTokenFungible(IDLE_TOKEN);

        allAvailableTokens = idleToken.getAllAvailableTokens();
        rebalancer = idleToken.rebalancer();
        owner = idleToken.owner();
        underlying = IERC20Detailed(idleToken.token());
        decimals = underlying.decimals();
        ONE_TOKEN = 10**decimals;

        _deployLocalContracts();

        // fund
        initialBal = 1000000 * ONE_TOKEN;
        deal(address(underlying), address(this), initialBal, true);
        underlying.safeApprove(address(idleTokenWrapper), type(uint256).max);

        // remove fees and unlent perc for easy testing
        vm.startPrank(idleToken.owner());
        IdleTokenFungible(address(idleToken)).setMaxUnlentPerc(0);
        IdleTokenFungible(address(idleToken)).setFee(0);
        vm.stopPrank();

        // label
        vm.label(address(idleToken), "idleToken");
        vm.label(address(underlying), "underlying");
        vm.label(address(idleTokenWrapper), "idleTokenWrapper");
    }

    function _deployLocalContracts() internal virtual {
        // deploy idleTokenWrapper
        idleTokenWrapper = new IdleTokenWrapper();
        idleTokenWrapper.initialize(idleToken);
    }

    function testSetupOk() public {
        assertEq(address(idleTokenWrapper.idleToken()), address(idleToken));
        assertEq(address(idleToken.token()), address(underlying));
        assertEq(idleTokenWrapper.totalSupply(), 0);
    }

    function testConversion() public {
        uint256 assets = idleTokenWrapper.convertToAssets(ONE_18);
        assertEq(assets, idleToken.tokenPrice());
        assertEq(idleTokenWrapper.convertToShares(assets), ONE_18);
    }

    function testPreview() public {
        uint256 amount = 1e18;
        uint256 assets = (amount * idleToken.tokenPrice()) / ONE_18;
        uint256 shares = (amount * ONE_18) / idleToken.tokenPrice();

        assertEq(idleTokenWrapper.previewDeposit(amount), shares);
        assertApproxEqAbs(idleTokenWrapper.previewMint(ONE_18), assets, 1);
        assertEq(idleTokenWrapper.previewWithdraw(amount), shares);
        assertEq(idleTokenWrapper.previewRedeem(ONE_18), assets);
    }

    function testMaxDeposit() public {
        assertEq(idleTokenWrapper.maxDeposit(address(this)), type(uint256).max);
        assertEq(idleTokenWrapper.maxMint(address(this)), type(uint256).max);
    }

    function testMaxDepositWhenPaused() public {
        // function sig paused() == 0x5c975abb
        vm.mockCall(address(idleToken), abi.encodeWithSelector(0x5c975abb), abi.encode(true));
        assertEq(idleTokenWrapper.maxDeposit(address(this)), 0);
        assertEq(idleTokenWrapper.maxMint(address(this)), 0);
        vm.clearMockedCalls();
    }

    function testMaxWithdraw() public {
        uint256 amount = 10000 * ONE_TOKEN;
        uint256 mintedShares = idleTokenWrapper.deposit(amount, address(this));

        uint256 assets = idleTokenWrapper.maxWithdraw(address(this));
        uint256 shares = idleTokenWrapper.maxRedeem(address(this));
        assertApproxEqAbs(assets, amount, 1, "withdrawable aseets");
        assertEq(shares, mintedShares, "withdrawabl shares");

        // prevent withdraws
        vm.prank(owner);
        IdleTokenFungible(address(idleToken)).pause();

        assertEq(idleTokenWrapper.maxWithdraw(address(this)), 0, "cannot withdraw when paused");
        assertEq(idleTokenWrapper.maxRedeem(address(this)), 0, "cannot redeem when paused");
    }

    function testDeposit() public {
        uint256 amount = 10000 * ONE_TOKEN;

        uint256 mintedShares = idleTokenWrapper.deposit(amount, address(this));

        assertEq(idleToken.balanceOf(address(idleTokenWrapper)), mintedShares, "idleToken bal");
        assertEq(underlying.balanceOf(address(this)), initialBal - amount, "underlying bal");

        assertEq(idleTokenWrapper.balanceOf(address(this)), mintedShares, "wrapper bal");
        assertEq(idleTokenWrapper.totalSupply(), mintedShares, "wrapper totalSupply");
    }

    function testMint() public {
        uint256 amount = 10000 * ONE_TOKEN;

        uint256 shares = (amount * ONE_18) / idleToken.tokenPrice();
        uint256 assetsUsed = idleTokenWrapper.mint(shares, address(this));

        assertApproxEqAbs(assetsUsed, amount, 1, "assets used");
        assertEq(underlying.balanceOf(address(this)), initialBal - assetsUsed, "underlying bal");
        assertApproxEqAbs(idleToken.balanceOf(address(idleTokenWrapper)), shares, 1, "idleToken bal");
        assertApproxEqAbs(idleTokenWrapper.balanceOf(address(this)), shares, 1, "wrapper bal");
        assertApproxEqAbs(idleTokenWrapper.totalSupply(), shares, 1, "wrapper totalSupply");
    }

    function testRedeem() public {
        uint256 amount = 10000 * ONE_TOKEN;

        uint256 mintedShares = idleTokenWrapper.deposit(amount, address(this));

        vm.roll(block.number + 1);
        _rebalance(70000, 30000);

        vm.roll(block.number + 1);
        idleTokenWrapper.redeem(mintedShares, address(this), address(this));

        assertApproxEqAbs(idleToken.balanceOf(address(idleTokenWrapper)), 0, 1, "idleToken bal");
        assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal");
        assertApproxEqAbs(idleTokenWrapper.balanceOf(address(this)), 0, 1, "wrapper bal");
        assertApproxEqAbs(idleTokenWrapper.totalSupply(), 0, 1, "wrapper totalSupply");
    }

    function testWithdraw() public {
        uint256 amount = 10000 * ONE_TOKEN;

        uint256 shares = (amount * ONE_18) / idleToken.tokenPrice();
        uint256 assetsUsed = idleTokenWrapper.mint(shares, address(this));

        vm.roll(block.number + 1);
        _rebalance(70000, 30000);

        vm.roll(block.number + 1);
        uint256 burntShares = idleTokenWrapper.withdraw(assetsUsed, address(this), address(this));

        assertApproxEqAbs(idleToken.balanceOf(address(idleTokenWrapper)), shares - burntShares, 1, "idleToken bal");
        assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal");

        assertApproxEqAbs(idleTokenWrapper.balanceOf(address(this)), shares - burntShares, 1, "wrapper bal");
        assertApproxEqAbs(idleTokenWrapper.totalSupply(), shares - burntShares, 1, "wrapper totalSupply");
    }

    function testRedeemAll() public {
        uint256 amount = 10000 * ONE_TOKEN;
        idleTokenWrapper.deposit(amount, address(this));
        vm.roll(block.number + 1);

        idleTokenWrapper.redeem(type(uint256).max, address(this), address(this));
        assertEq(idleTokenWrapper.balanceOf(address(this)), 0, "all shares should be burned");
    }

    function testWithdrawAll() public {
        uint256 amount = 10000 * ONE_TOKEN;
        idleTokenWrapper.deposit(amount, address(this));
        vm.roll(block.number + 1);

        idleTokenWrapper.withdraw(type(uint256).max, address(this), address(this));
        assertEq(idleTokenWrapper.balanceOf(address(this)), 0, "all shares should be burned");
    }

    function testRevertWithAllowanceError() external {
        idleTokenWrapper.deposit(1000 * ONE_TOKEN, address(this));

        vm.startPrank(address(0xbabe), address(0xbabe));

        vm.expectRevert(IdleTokenWrapper.InsufficientAllowance.selector);
        idleTokenWrapper.redeem(10, address(0xbabe), address(this));

        vm.roll(block.number + 1);

        vm.expectRevert(IdleTokenWrapper.InsufficientAllowance.selector);
        idleTokenWrapper.withdraw(10, address(0xbabe), address(this));

        vm.stopPrank();
    }

    function testRedeemInsteadOfOwner() external {
        uint256 amount = 10000 * ONE_TOKEN;
        uint256 mintedShares = idleTokenWrapper.deposit(amount, address(this));

        idleTokenWrapper.approve(address(0xbabe), type(uint256).max);

        // redeem 1000 shares
        vm.prank(address(0xbabe), address(0xbabe)); // Sets the *next* call's msg.sender and tx.origin
        uint256 withdrawAmount = idleTokenWrapper.redeem(1000, address(0xbabe), address(this));
        assertApproxEqAbs(idleTokenWrapper.balanceOf(address(this)), mintedShares - 1000, 1, "wrapper bal");
        assertApproxEqAbs(underlying.balanceOf(address(0xbabe)), withdrawAmount, 1, "underlying bal");
    }

    function testWithdrawInsteadOfOwner() external {
        uint256 amount = 10000 * ONE_TOKEN;
        uint256 mintedShares = idleTokenWrapper.deposit(amount, address(this));

        idleTokenWrapper.approve(address(0xbabe), type(uint256).max);

        // withdraw 100 amount of underlying
        vm.prank(address(0xbabe), address(0xbabe));
        uint256 burntShares = idleTokenWrapper.withdraw(100, address(0xbabe), address(this));
        assertApproxEqAbs(idleTokenWrapper.balanceOf(address(this)), mintedShares - burntShares, 1, "wrapper bal");
        assertApproxEqAbs(underlying.balanceOf(address(0xbabe)), 100, 1, "underlying bal");
    }

    function testRevertIfReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        idleTokenWrapper.initialize(idleToken);
    }

    function tesClone() public {}

    function _rebalance(uint256 alloc1, uint256 alloc2) public {
        uint256[] memory allocations = new uint256[](allAvailableTokens.length);
        (allocations[0], allocations[1]) = (alloc1, alloc2);
        vm.startPrank(rebalancer);
        idleToken.setAllocations(allocations);
        idleToken.rebalance();
        vm.stopPrank();
    }
}
