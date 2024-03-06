// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;
interface IStakedUSDeV2 {
  function cooldownDuration() external view returns (uint24);
  function unstake(address receiver) external;
  function cooldownAssets(uint256 assets) external returns (uint256);
  function cooldownShares(uint256 shares) external returns (uint256);
}