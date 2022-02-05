// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IRewardPool {
    function balanceOf(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function rewardToken() external view returns (address);
}
