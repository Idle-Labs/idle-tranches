// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

interface IStakedAave {
  function COOLDOWN_SECONDS() external view returns (uint256);
  function redeem(address to, uint256 amount) external;
  function cooldown() external;
  function balanceOf(address) external view returns (uint256);
  function stakersCooldowns(address) external view returns (uint256);
}
