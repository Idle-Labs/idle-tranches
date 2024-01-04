// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IGammaChef {
  function poolLength() external view returns (uint256);
  function lpToken(uint256) external view returns (address);
  function deposit(uint256 pid, uint256 amount, address to) external;
  function withdraw(uint256 pid, uint256 amount, address to) external;
  function harvest(uint256 pid, address to) external;
  function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
}