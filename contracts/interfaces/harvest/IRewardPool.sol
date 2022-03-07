// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IRewardPool {
    /// @notice returns the number of reward bearing tokens
    function balanceOf(address account) external view returns (uint256);

    /// @notice stake underlying tokens. The contract must be approved
    function stake(uint256 amount) external;

    /// @notice withdraw underlying tokens. 
    function withdraw(uint256 amount) external;

    /// @notice claim the reward
    function getReward() external;

    /// @notice returns the address of reward token
    function rewardToken() external view returns (address);
}
