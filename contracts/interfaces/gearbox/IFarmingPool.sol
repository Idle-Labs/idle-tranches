// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IFarmingPool {
  struct Info {
    uint40 finished;
    uint32 duration;
    uint184 reward;
    uint256 balance;
  }

  // View functions
  function farmInfo() external view returns(Info memory);
  function farmed(address account) external view returns(uint256);

  // User functions
  function deposit(uint256 amount) external;
  function withdraw(uint256 amount) external;
  function claim() external;
  function exit() external;
}