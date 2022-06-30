// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/BaseStrategy.sol";
import "../../contracts/mocks/MockStakingReward.sol";

import "../../contracts/interfaces/IERC20Detailed.sol";

contract TestStrategy is BaseStrategy {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _strategyToken,
        address _underlyingToken,
        address _owner
    ) public initializer {
        _initialize(_name, _symbol, _strategyToken, _underlyingToken, _owner);
    }

    /// @dev makes the actual deposit into the `strategy`
    /// @param _amount amount of tokens to deposit
    function _deposit(uint256 _amount) internal override returns (uint256) {
        underlyingToken.approve(strategyToken, _amount);
        MockStakingReward(strategyToken).stake(_amount);
        return _amount;
    }

    /// @dev makes the actual withdraw from the 'strategy'
    /// @return amountWithdrawn returns the amount withdrawn
    function _withdraw(uint256 _amountToWithdraw, address _destination)
        internal
        override
        returns (uint256)
    {
        MockStakingReward(strategyToken).unstake(_amountToWithdraw);
        underlyingToken.transfer(_destination, _amountToWithdraw);
        return _amountToWithdraw;
    }

    function _redeemRewards(bytes calldata)
        internal
        override
        returns (uint256 underlyingReward, uint256[] memory)
    {
        // uint256 _amountToWithdraw = abi.decode(data, (uint256));
        uint256 balBefore = underlyingToken.balanceOf(address(this));
        MockStakingReward(strategyToken).claimRewards();
        underlyingReward = underlyingToken.balanceOf(address(this)) - balBefore;
    }

    function getRewardTokens() external view returns (address[] memory) {}
}

contract TestBaseStrategy is Test {
    using stdStorage for StdStorage;

    uint256 internal constant FULL_ALLOC = 100000;
    uint256 internal constant ONE_SCALE = 1e6;
    uint256 internal constant MAINNET_CHIANID = 1;
    address private constant owner = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
    address private constant rebalancer =
        0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IERC20Detailed internal underlying;
    MockStakingReward internal strategyToken;
    TestStrategy internal strategy;

    modifier runOnForkingNetwork(uint256 networkId) {
        // solhint-disable-next-line
        if (block.chainid == networkId) {
            _;
        }
    }

    function setUp() public virtual runOnForkingNetwork(MAINNET_CHIANID) {
        underlying = IERC20Detailed(USDC);
        strategyToken = new MockStakingReward(underlying);
        strategyToken.setTestReward(1000 * ONE_SCALE);

        // deploy strategy
        // `token` is address(1) to prevent initialization of the implementation contract.
        // it need to be reset mannualy.
        strategy = new TestStrategy();
        stdstore
            .target(address(strategy))
            .sig(strategy.token.selector)
            .checked_write(address(0));
        strategy.initialize(
            "Idle TestStrategy USDC",
            "IdleTestStrategy[USDC]",
            address(strategyToken),
            address(underlying),
            owner // owner
        );

        vm.prank(owner);
        strategy.setWhitelistedCDO(address(this));

        // fund
        deal(address(underlying), address(strategyToken), 1000000 * ONE_SCALE, true); // prettier-ignore
        deal(address(underlying), address(this), 10000 * ONE_SCALE, true);
        underlying.approve(address(strategy), type(uint256).max);

        /// label
        vm.label(address(strategy), "strategy");
        vm.label(address(underlying), "underlying");
        vm.label(USDC, "USDC");
    }

    function testInitialize() external runOnForkingNetwork(MAINNET_CHIANID) {
        assertEq(strategy.owner(), owner);
        assertEq(strategy.token(), USDC);
        assertEq(strategy.strategyToken(), address(strategyToken));
        assertEq(strategy.idleCDO(), address(this));
        assertEq(strategy.oneToken(), ONE_SCALE);
        assertEq(strategy.price(), ONE_SCALE);
        assertEq(strategy.getApr(), 0);
        assertTrue(strategy.lastIndexedTime() != 0);
        assertTrue(strategy.releaseBlocksPeriod() != 0);

        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        strategy.initialize(
            "Idle TestStrategy USDC",
            "IdleTestStrategy[USDC]",
            address(strategyToken),
            address(underlying),
            owner // owner
        );
    }

    function testMintAndRedeem() external runOnForkingNetwork(MAINNET_CHIANID) {
        underlying.approve(address(strategy), 1e10);
        strategy.deposit(1e10);

        assertEq(strategy.balanceOf(address(this)), 1e10);
        assertEq(strategy.totalTokensStaked(), 1e10);

        strategy.redeem(1e10);
        assertEq(strategy.balanceOf(address(this)), 0);
        assertEq(strategy.totalTokensStaked(), 0);
    }

    function testOnlyIdleCDO() external runOnForkingNetwork(MAINNET_CHIANID) {
        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.deposit(1e10);

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.redeem(1e10);
    }

    function testOnlyOwner() external runOnForkingNetwork(MAINNET_CHIANID) {
        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        strategy.setReleaseBlocksPeriod(1000);

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        strategy.setWhitelistedCDO(address(0xcafe));

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        strategy.transferToken(USDC, 1e6, address(0xbabe));
    }

    function testRedeemRewards() external runOnForkingNetwork(MAINNET_CHIANID) {
        underlying.approve(address(strategy), 1e10);
        strategy.deposit(1e10);

        skip(5 days);
        strategy.redeemRewards(bytes(""));

        assertGt(strategy.totalTokensStaked(), 0);
        assertGt(strategy.totalTokensLocked(), 0);

        // rewards are lineally released
        assertEq(strategy.releaseBlocksPeriod(), 6400);
        assertEq(strategy.price(), ONE_SCALE);

        // half of the period
        skip(5 days);
        vm.roll(block.number + 3200);

        uint256 _price = strategy.price();
        assertGt(_price, ONE_SCALE);
        assertGt(strategy.getApr(), 0);

        skip(5 days);
        vm.roll(block.number + 6400);

        assertEq(strategy.price(), 2 * (_price - ONE_SCALE) + ONE_SCALE);
    }
}
