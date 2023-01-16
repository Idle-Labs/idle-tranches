// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/morpho/IMorphoSupplyVault.sol";
import "../ERC4626Strategy.sol";

abstract contract MorphoSupplyVaultStrategy is ERC4626Strategy {
    using SafeERC20 for IERC20;

    /// @notice pool token address (e.g. aDAI, cDAI)
    address public poolToken;

    /// @notice reward token address (e.g. COMP)
    /// @dev set to address(0) to skip `redeemRewards`
    address public rewardToken;

    function initialize(
        address _strategyToken,
        address _token,
        address _owner,
        address _poolToken,
        address _rewardToken
    ) public {
        _initialize(_strategyToken, _token, _owner);
        poolToken = _poolToken;
        rewardToken = _rewardToken;
    }

    /// @notice redeem the rewards
    /// @return rewards amount of reward that is deposited to the ` strategy`
    function redeemRewards(bytes calldata) public override onlyIdleCDO nonReentrant returns (uint256[] memory rewards) {
        address _rewardToken = rewardToken;

        // if rewardToken is not set, skip redeeming rewards
        if (_rewardToken != address(0)) {
            // claim rewards
            uint256 rewardsAmount = IMorphoSupplyVault(strategyToken).claimRewards(address(this));
            rewards = new uint256[](1);
            rewards[0] = rewardsAmount;
            // send rewards to the idleCDO
            IERC20(_rewardToken).safeTransfer(idleCDO, rewardsAmount);
        }
    }

    function getRewardTokens() external view returns (address[] memory rewards) {
        address _rewardToken = rewardToken;

        if (_rewardToken != address(0)) {
            rewards = new address[](1);
            rewards[0] = _rewardToken;
        }
    }

    /// @dev set to address(0) to skip `redeemRewards`
    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }
}
