// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IClearInterestRateModel {
  function getSupplyRate(uint256, uint256, uint256, uint256) external view returns (uint256);
  function utilizationRate(uint256, uint256, uint256) external view returns (uint256);
}
