// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface ITruefiCreditLine {
  function virtualTokenBalance() external view returns (uint256);
  function lastProtocolFeeRate() external view returns (uint256);
  function unpaidFee() external view returns (uint256);
  function totalAssets() external view returns (uint256);
  function interestRate() external view returns (uint256);
  function utilization() external view returns (uint256);
  function borrower() external view returns (address);
  function unincludedInterest() external view returns (uint256);
  function accruedInterest() external view returns (uint256);
  function repay(uint256 assets) external;
}