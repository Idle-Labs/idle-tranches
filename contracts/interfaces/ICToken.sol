// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface ICToken {
  function accrueInterest() external;
  function exchangeRateStored() external view returns (uint256);
}
