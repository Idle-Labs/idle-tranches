// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
interface IMAToken {
  // aToken address
  function poolToken() external view returns (address);
}