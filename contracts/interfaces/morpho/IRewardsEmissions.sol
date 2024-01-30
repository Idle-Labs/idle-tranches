// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;


interface IRewardsEmissions {
  struct RewardsEmission {
    /// @notice The number of reward tokens distributed per year on the supply side (in the reward token decimals).
    uint256 supplyRewardTokensPerYear;
    /// @notice The number of reward tokens distributed per year on the borrow side (in the reward token decimals).
    uint256 borrowRewardTokensPerYear;
    /// @notice The number of reward tokens distributed per year on the collateral side (in the reward token decimals).
    uint256 collateralRewardTokensPerYear;
  }

  function rewardsEmissions(address sender, address urd, address rewardToken, bytes32 marketId) 
    external view returns (RewardsEmission memory);
}
