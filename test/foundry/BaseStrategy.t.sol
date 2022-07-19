// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/BaseStrategy.sol";
import "../../contracts/mocks/MockStakingReward.sol";

import "../../contracts/interfaces/IERC20Detailed.sol";
import "./TestIdleCDOBase.sol";

contract TestStrategy is BaseStrategy {
    MockStakingReward public stakingContract;

    function initialize(
        string memory _name,
        string memory _symbol,
        MockStakingReward _stakingContract,
        address _underlyingToken,
        address _owner
    ) public initializer {
        _initialize(_name, _symbol, _underlyingToken, _owner);
        stakingContract = _stakingContract;
    }

    /// @dev makes the actual deposit into the `strategy`
    /// @param _amount amount of tokens to deposit
    function _deposit(uint256 _amount) internal override returns (uint256) {
        underlyingToken.approve(address(stakingContract), _amount);
        stakingContract.stake(_amount);
        return _amount;
    }

    /// @dev makes the actual withdraw from the 'strategy'
    /// @return amountWithdrawn returns the amount withdrawn
    function _withdraw(uint256 _amountToWithdraw, address _destination)
        internal
        override
        returns (uint256)
    {
        stakingContract.unstake(_amountToWithdraw);
        underlyingToken.transfer(_destination, _amountToWithdraw);
        return _amountToWithdraw;
    }

    function _redeemRewards(bytes calldata)
        internal
        override
        returns (uint256[] memory rewards)
    {
        rewards = new uint256[](1);
        uint256 balBefore = underlyingToken.balanceOf(address(this));
        stakingContract.claimRewards();
        rewards[0] = underlyingToken.balanceOf(address(this)) - balBefore;
    }

    function getRewardTokens()
        external
        view
        returns (address[] memory rewards)
    {
        rewards = new address[](1);
        rewards[0] = token;
    }
}

contract TestBaseStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function _deployStrategy(address _owner)
        internal
        override
        returns (address _strategy, address _underlying)
    {
        _underlying = USDC;
        strategy = new TestStrategy();
        MockStakingReward _stakingContract = new MockStakingReward(
            IERC20Detailed(_underlying)
        );

        _strategy = address(strategy);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(
            address(0)
        );
        TestStrategy(_strategy).initialize(
            "Idle TestStrategy USDC",
            "IdleTestStrategy[USDC]",
            _stakingContract,
            _underlying,
            _owner
        );

        strategyToken = IERC20Detailed(_strategy); // strategy itself
        uint256 _decimals = strategyToken.decimals();

        uint256 amountToFund = 10_000_000 * 10**_decimals;
        deal(_underlying, address(_stakingContract), amountToFund , true); // prettier-ignore
        _stakingContract.setTestReward(100_000 * 10**_decimals);
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        TestStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testOnlyOwner()
        public
        override
        runOnForkingNetwork(MAINNET_CHIANID)
    {
        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        TestStrategy(address(strategy)).setReleaseBlocksPeriod(1000);

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        TestStrategy(address(strategy)).setWhitelistedCDO(address(0xcafe));

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        TestStrategy(address(strategy)).transferToken(
            address(underlying),
            1e6,
            address(0xbabe)
        );
    }

    function testCantReinitialize()
        external
        override
        runOnForkingNetwork(MAINNET_CHIANID)
    {
        MockStakingReward _stakingContract = TestStrategy(address(strategy))
            .stakingContract();
        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        TestStrategy(address(strategy)).initialize(
            "Idle TestStrategy USDC",
            "IdleTestStrategy[USDC]",
            _stakingContract,
            address(underlying),
            owner // owner
        );
    }
}
