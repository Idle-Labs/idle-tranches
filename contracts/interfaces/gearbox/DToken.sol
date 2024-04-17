// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;
interface DToken {
  function withdrawFee() external view returns (uint256);
  function supplyRate() external view returns (uint256);
  function expectedLiquidity() external view returns (uint256);
  function lastBaseInterestUpdate() external view returns (uint40);
  function lastQuotaRevenueUpdate() external view returns (uint40);
  function depositWithReferral(uint256 amount, address receiver, uint256 referralCode) external returns(uint256 shares);
}