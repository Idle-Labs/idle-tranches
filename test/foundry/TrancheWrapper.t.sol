// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/TrancheWrapper.sol";

contract TestTrancheWrapper is Test {
    using stdStorage for StdStorage;

    uint256 internal constant MAINNET_CHIANID = 1;
    uint256 internal constant ONE_TRANCHE_TOKEN = 1e18;

    address internal constant IDLE_CDO_ADDRESS = 0xd0DbcD556cA22d3f3c142e9a3220053FD7a247BC;
    address internal constant IDLE_TRANCHE_ADDRESS = 0x730348a54bA58F64295154F0662A08Cbde1225c2;

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

    IERC20Detailed internal tranche;
    TrancheWrapper internal trancheWrapper;

    modifier runOnForkingNetwork(uint256 networkId) {
        // solhint-disable-next-line
        if (block.chainid == networkId) {
            _;
        }
    }

    function setUp() public virtual runOnForkingNetwork(MAINNET_CHIANID) {
        idleCDO = IdleCDO(IDLE_CDO_ADDRESS);
        tranche = IERC20Detailed(IDLE_TRANCHE_ADDRESS);

        owner = idleCDO.owner();
        underlying = IERC20Detailed(idleCDO.token());
        decimals = underlying.decimals();
        ONE_SCALE = 10**decimals;
        strategy = IIdleCDOStrategy(idleCDO.strategy());
        strategyToken = IERC20Detailed(strategy.strategyToken());
        AAtranche = IdleCDOTranche(idleCDO.AATranche());
        BBtranche = IdleCDOTranche(idleCDO.BBTranche());

        _deployLocalContracts();

        // fund
        initialBal = 1000000 * ONE_SCALE;
        deal(address(underlying), address(this), initialBal, true);
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
        tranche = IERC20Detailed(idleCDO.AATranche());
        trancheWrapper = new TrancheWrapper(idleCDO, address(tranche));

        vm.startPrank(owner);
        idleCDO.setIsAYSActive(true);
        idleCDO.setUnlentPerc(0);
        idleCDO.setFee(0);
        vm.stopPrank();
    }

    function testSetupOk() public {
        assertEq(address(trancheWrapper.idleCDO()), address(idleCDO));
        assertEq(trancheWrapper.tranche(), address(tranche));
        assertEq(address(idleCDO.token()), address(underlying));
        assertEq(trancheWrapper.totalSupply(), 0);
        assertEq(trancheWrapper.totalAssets(), idleCDO.getContractValue());
        assertEq(trancheWrapper.convertToAssets(ONE_TRANCHE_TOKEN), idleCDO.tranchePrice(address(tranche)));
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
        uint256 amount = 10000 * ONE_SCALE;
        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        uint256 assets = trancheWrapper.maxWithdraw(address(this));
        uint256 shares = trancheWrapper.maxRedeem(address(this));
        assertApproxEqAbs(assets, amount, 1, "withdrawable aseets");
        assertEq(shares, mintedShares, "withdrawabl shares");

        // prevent withdraws
        vm.prank(owner);
        idleCDO.emergencyShutdown();

        assertEq(trancheWrapper.maxWithdraw(address(this)), 0, "cannot withdraw when emergency shutdown");
        assertEq(trancheWrapper.maxRedeem(address(this)), 0, "cannot redeem when emergency shutdown");
    }

    function testDeposits() public {
        uint256 amount = 10000 * ONE_SCALE;

        uint256 expected = trancheWrapper.previewDeposit(amount);
        uint256 mintedShares = trancheWrapper.deposit(amount, address(this));

        assertEq(tranche.balanceOf(address(trancheWrapper)), mintedShares, "tranche bal");
        assertEq(underlying.balanceOf(address(this)), initialBal - amount, "underlying bal");

        assertEq(trancheWrapper.balanceOf(address(this)), mintedShares, "wrapper bal");
        assertEq(trancheWrapper.totalSupply(), mintedShares, "wrapper totalSupply");
        assertApproxEqAbs(trancheWrapper.convertToAssets(mintedShares), amount, 1, "conversion to assets");
        assertEq(mintedShares, expected, "minted shares");
    }
}
