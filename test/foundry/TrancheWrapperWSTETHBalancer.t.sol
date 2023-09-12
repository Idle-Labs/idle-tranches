// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/TrancheWrapperWSTETHBalancer.sol";
import "../../contracts/interfaces/IWstETH.sol";

contract TestTrancheWrapperWSTETHBalancer is Test {
    using stdStorage for StdStorage;

    uint256 internal constant BLOCK_FOR_TEST = 16_048_668;
    uint256 internal constant ONE_TRANCHE_TOKEN = 1e18;
    // lido cdo
    address internal constant IDLE_CDO_ADDRESS = 0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8;
    // bb tranche
    address internal constant IDLE_TRANCHE_ADDRESS = 0x3a52fa30c33cAF05fAeE0f9c5Dfe5fd5fe8B3978;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public owner;
    IdleCDO internal idleCDO;
    IERC20Detailed internal underlying;
    IERC20Detailed internal strategyToken;
    IdleCDOTranche internal AAtranche;
    IdleCDOTranche internal BBtranche;
    IIdleCDOStrategy internal strategy;

    uint256 internal decimals;
    uint256 internal ONE_SCALE;
    uint256 internal initialBal;
    bytes internal extraData;
    bytes internal extraDataSell;

    IERC20Detailed internal tranche;
    TrancheWrapper internal trancheWrapper;

    function setUp() public virtual {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), BLOCK_FOR_TEST));

        idleCDO = IdleCDO(IDLE_CDO_ADDRESS);
        tranche = IERC20Detailed(IDLE_TRANCHE_ADDRESS);

        owner = idleCDO.owner();
        underlying = IERC20Detailed(WSTETH);
        // underlying = IERC20Detailed(idleCDO.token());
        decimals = underlying.decimals();
        ONE_SCALE = 10**decimals;
        strategy = IIdleCDOStrategy(idleCDO.strategy());
        strategyToken = IERC20Detailed(strategy.strategyToken());
        AAtranche = IdleCDOTranche(idleCDO.AATranche());
        BBtranche = IdleCDOTranche(idleCDO.BBTranche());

        _deployLocalContracts();

        // fund
        initialBal = 100000 * ONE_SCALE;

        // deal wsteth to this contract
        deal(address(underlying), address(this), initialBal);
        underlying.approve(address(trancheWrapper), type(uint256).max);

        // label
        vm.label(address(idleCDO), "idleCDO");
        vm.label(address(AAtranche), "AAtranche");
        vm.label(address(BBtranche), "BBtranche");
        vm.label(address(strategy), "strategy");
        vm.label(address(underlying), "underlying");
        vm.label(address(strategyToken), "strategyToken");
        vm.label(address(tranche), "tranche");
        vm.label(address(trancheWrapper), "trancheWrapper");
    }

    function _deployLocalContracts() internal virtual {
        // deploy trancheWrapper
        tranche = IERC20Detailed(idleCDO.BBTranche());
        trancheWrapper = new TrancheWrapperWSTETHBalancer();
        stdstore.target(address(trancheWrapper)).sig(trancheWrapper.token.selector).checked_write(address(0));

        trancheWrapper.initialize(idleCDO, address(tranche));

        vm.startPrank(owner);
        idleCDO.setIsAYSActive(true);
        idleCDO.setUnlentPerc(0);
        idleCDO.setFee(0);
        vm.stopPrank();
    }

    function testSetupOk() public {
        assertEq(address(trancheWrapper.idleCDO()), address(idleCDO));
        assertEq(WSTETH, address(underlying));
        assertEq(trancheWrapper.totalSupply(), 0);
        assertEq(trancheWrapper.totalAssets(), idleCDO.getContractValue());
        if (address(tranche) == address(AAtranche)) {
            assertEq(trancheWrapper.tranche(), address(AAtranche));
        } else {
            assertEq(trancheWrapper.tranche(), address(BBtranche));
        }
    }

    function testConversion() public {
        // convertToAssets should return amount of underlyings, in this case wsteth
        uint256 trancheTokens = idleCDO.virtualPrice(address(tranche)) * ONE_TRANCHE_TOKEN / IWstETH(WSTETH).stEthPerToken();
        assertEq(trancheWrapper.convertToAssets(1e18), trancheTokens);
        
        // this is not used
        assertApproxEqAbs(
            trancheWrapper.convertToShares(trancheTokens), 1e18, 1);
    }

    function testPreview() public {
        uint256 assets = idleCDO.virtualPrice(address(tranche)) * ONE_TRANCHE_TOKEN / IWstETH(WSTETH).stEthPerToken();
        uint256 shares = (1e18 * IWstETH(WSTETH).stEthPerToken()) / idleCDO.virtualPrice(address(tranche));

        assertEq(trancheWrapper.previewDeposit(1e18), shares);
        assertEq(trancheWrapper.previewMint(ONE_TRANCHE_TOKEN), assets);
        assertEq(trancheWrapper.previewWithdraw(1e18), shares);
        assertEq(trancheWrapper.previewRedeem(ONE_TRANCHE_TOKEN), assets);
    }

    function testMaxDepositWhenLimitZero() public {
        /// set TVL limit to 0
        stdstore.target(address(idleCDO)).sig(idleCDO.limit.selector).checked_write(uint256(0));

        uint256 assets = trancheWrapper.maxDeposit(address(this));
        uint256 shares = trancheWrapper.maxMint(address(this));
        assertEq(assets, type(uint256).max);
        assertEq(shares, type(uint256).max);
    }

    function testMaxDepositWhenLimitNonZero() public {
        /// set TVL limit to 1000 assets
        /// mock `getContractValue` to return 100 assets
        stdstore.target(address(idleCDO)).sig(idleCDO.limit.selector).checked_write(1000 * ONE_SCALE);
        vm.mockCall(
            address(idleCDO),
            abi.encodeWithSelector(idleCDO.getContractValue.selector),
            abi.encode(100 * ONE_SCALE)
        );
        uint256 assets = trancheWrapper.maxDeposit(address(this));
        uint256 shares = trancheWrapper.maxMint(address(this));
        assertEq(assets, 900 * ONE_SCALE);
        assertEq(shares, trancheWrapper.convertToShares(assets));
        vm.clearMockedCalls();
    }

    function testMaxDepositWhenLimited() public {
        /// set TVL limit to 1000 assets
        /// mock `getContractValue` to return 1000 assets
        stdstore.target(address(idleCDO)).sig(idleCDO.limit.selector).checked_write(1000 * ONE_SCALE);
        vm.mockCall(
            address(idleCDO),
            abi.encodeWithSelector(idleCDO.getContractValue.selector),
            abi.encode(1000 * ONE_SCALE)
        );
        uint256 assets = trancheWrapper.maxDeposit(address(this));
        uint256 shares = trancheWrapper.maxMint(address(this));
        assertEq(assets, 0);
        assertEq(shares, 0);
        vm.clearMockedCalls();
    }

    function testMaxWithdraw() public {
        uint256 amount = 10 * ONE_SCALE;
        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        uint256 assets = trancheWrapper.maxWithdraw(address(this));
        uint256 shares = trancheWrapper.maxRedeem(address(this));
        assertApproxEqAbs(assets, amount, 1, "withdrawable assets");
        assertEq(shares, mintedShares, "withdrawabl shares");

        // prevent withdraws
        vm.prank(owner);
        idleCDO.emergencyShutdown();

        assertEq(trancheWrapper.maxWithdraw(address(this)), 0, "cannot withdraw when emergency shutdown");
        assertEq(trancheWrapper.maxRedeem(address(this)), 0, "cannot redeem when emergency shutdown");
    }

    function testDeposit() public {
        uint256 amount = 10000 * ONE_SCALE;

        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        assertEq(tranche.balanceOf(address(trancheWrapper)), mintedShares, "tranche bal");
        assertEq(underlying.balanceOf(address(this)), initialBal - amount, "underlying bal");

        assertEq(trancheWrapper.balanceOf(address(this)), mintedShares, "wrapper bal");
        assertEq(trancheWrapper.totalSupply(), mintedShares, "wrapper totalSupply");
    }

    function testMint() public {
        uint256 amount = 10 * ONE_SCALE;

        uint256 shares = (amount * IWstETH(WSTETH).stEthPerToken()) / idleCDO.virtualPrice(address(tranche));
        uint256 assetsUsed = trancheWrapper.mint(shares, address(this));

        assertApproxEqAbs(assetsUsed, amount, 1, "tranche bal");
        assertApproxEqAbs(tranche.balanceOf(address(trancheWrapper)), shares, 1, "tranche bal");
        assertEq(underlying.balanceOf(address(this)), initialBal - assetsUsed, "underlying bal");
        assertApproxEqAbs(trancheWrapper.balanceOf(address(this)), shares, 1, "wrapper bal");
        assertApproxEqAbs(trancheWrapper.totalSupply(), shares, 1, "wrapper totalSupply");
    }

    function testRedeem() public {
        uint256 amount = 10 * ONE_SCALE;

        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        trancheWrapper.redeem(mintedShares, address(this), address(this));

        assertApproxEqAbs(tranche.balanceOf(address(trancheWrapper)), 0, 1, "tranche bal");
        assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal, 10, "underlying bal");
        assertApproxEqAbs(trancheWrapper.balanceOf(address(this)), 0, 1, "wrapper bal");
        assertApproxEqAbs(trancheWrapper.totalSupply(), 0, 1, "wrapper totalSupply");
    }

    function testWithdraw() public {
        uint256 amount = 10 * ONE_SCALE;

        uint256 shares = (amount * IWstETH(WSTETH).stEthPerToken()) / idleCDO.virtualPrice(address(tranche));
        uint256 assetsUsed = trancheWrapper.mint(shares, address(this));

        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        uint256 burntShares = trancheWrapper.withdraw(assetsUsed, address(this), address(this));

        assertApproxEqAbs(tranche.balanceOf(address(trancheWrapper)), shares - burntShares, 1, "tranche bal");
        assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal, 10, "underlying bal");

        assertApproxEqAbs(trancheWrapper.balanceOf(address(this)), shares - burntShares, 1, "wrapper bal");
        assertApproxEqAbs(trancheWrapper.totalSupply(), shares - burntShares, 1, "wrapper totalSupply");
    }

    function testRedeemAll() public {
        uint256 amount = 10000 * ONE_SCALE;
        trancheWrapper.deposit(amount, address(this));
        vm.roll(block.number + 1);

        trancheWrapper.redeem(type(uint256).max, address(this), address(this));
        assertEq(trancheWrapper.balanceOf(address(this)), 0, "all shares should be burned");
    }

    function testWithdrawAll() public {
        uint256 amount = 10000 * ONE_SCALE;
        trancheWrapper.deposit(amount, address(this));
        vm.roll(block.number + 1);

        trancheWrapper.withdraw(type(uint256).max, address(this), address(this));
        assertEq(trancheWrapper.balanceOf(address(this)), 0, "all shares should be burned");
    }

    function testRevertWithAllowanceError() external {
        trancheWrapper.deposit(1000 * ONE_SCALE, address(this));

        vm.startPrank(address(0xbabe), address(0xbabe));

        vm.expectRevert("tw: burn amount exceeds allowance");
        trancheWrapper.redeem(10, address(0xbabe), address(this));

        vm.roll(block.number + 1);

        vm.expectRevert("tw: burn amount exceeds allowance");
        trancheWrapper.withdraw(10, address(0xbabe), address(this));

        vm.stopPrank();
    }

    function testRedeemInsteadOfOwner() external {
        uint256 amount = 10000 * ONE_SCALE;
        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        trancheWrapper.approve(address(0xbabe), type(uint256).max);

        // redeem 1000 shares
        vm.prank(address(0xbabe), address(0xbabe)); // Sets the *next* call's msg.sender and tx.origin
        uint256 withdrawAmount = trancheWrapper.redeem(1000, address(0xbabe), address(this));
        assertApproxEqAbs(trancheWrapper.balanceOf(address(this)), mintedShares - 1000, 1, "wrapper bal");
        assertApproxEqAbs(underlying.balanceOf(address(0xbabe)), withdrawAmount, 1, "underlying bal");
    }

    function testWithdrawInsteadOfOwner() external {
        uint256 amount = 100 * ONE_SCALE;
        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        trancheWrapper.approve(address(0xbabe), type(uint256).max);

        // withdraw 10 amount of underlying
        uint256 toWithdraw = 10*ONE_TRANCHE_TOKEN;
        vm.prank(address(0xbabe), address(0xbabe));
        uint256 burntShares = trancheWrapper.withdraw(toWithdraw, address(0xbabe), address(this));
        assertApproxEqAbs(trancheWrapper.balanceOf(address(this)), mintedShares - burntShares, 10, "wrapper bal");
        assertApproxEqAbs(underlying.balanceOf(address(0xbabe)), toWithdraw, 10, "underlying bal");
    }

    function testRevertIfReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        trancheWrapper.initialize(idleCDO, address(tranche));
    }

    function _cdoHarvest(bool _skipRewards) internal {
        address[] memory rewards = IIdleCDOStrategy(idleCDO.strategy()).getRewardTokens();
        uint256 numOfRewards = rewards.length;
        bool[] memory _skipFlags = new bool[](4);
        bool[] memory _skipReward = new bool[](numOfRewards);
        uint256[] memory _minAmount = new uint256[](numOfRewards);
        uint256[] memory _sellAmounts = new uint256[](numOfRewards);
        bytes memory _extraData = extraData;

        // skip fees distribution
        _skipFlags[3] = _skipRewards;

        vm.prank(idleCDO.rebalancer());
        (bool success, ) = address(idleCDO).call(
            abi.encodeWithSignature(
                "harvest(bool[],bool[],uint256[],uint256[],bytes)",
                _skipFlags,
                _skipReward,
                _minAmount,
                _sellAmounts,
                _extraData
            )
        );
        require(success, "harvest failed. this might be because the CDO is incomaptible with the old interface");

        // linearly release all sold rewards
        vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1);
    }
}
