// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

interface ICToken {
  function accrueInterest() external;
}
