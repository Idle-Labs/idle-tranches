// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/BaseStrategy.sol";
import "../../contracts/mocks/MockStakingReward.sol";

import "../../contracts/interfaces/IERC20Detailed.sol";
import "./TestIdleCDOBase.sol";

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

contract TestBaseStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function _deployStrategy(address _owner)
        internal
        override
        returns (address _strategy, address _underlying)
    {
        _underlying = USDC;

        strategyToken = IERC20Detailed(
            address(new MockStakingReward(IERC20Detailed(_underlying)))
        );
        strategy = new TestStrategy();
        _strategy = address(strategy);

        uint256 amountToFund = 1_000_000 * ONE_SCALE;
        deal(_underlying, address(strategyToken), amountToFund , true); // prettier-ignore
        MockStakingReward(address(strategyToken)).setTestReward(
            1000 * ONE_SCALE
        );

        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(
            address(0)
        );
        TestStrategy(_strategy).initialize(
            "Idle TestStrategy USDC",
            "IdleTestStrategy[USDC]",
            address(strategyToken),
            _underlying,
            _owner
        );
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
        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        TestStrategy(address(strategy)).initialize(
            "Idle TestStrategy USDC",
            "IdleTestStrategy[USDC]",
            address(strategyToken),
            address(underlying),
            owner // owner
        );
    }
}