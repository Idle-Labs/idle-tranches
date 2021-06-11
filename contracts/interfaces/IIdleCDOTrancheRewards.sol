// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface IIdleCDOTrancheRewards {
  function stake(uint256 _amount) external returns (uint256);
  function unstake(uint256 _amount) external returns (uint256);
  function depositReward(address _reward, uint256 _amount) external;
}
