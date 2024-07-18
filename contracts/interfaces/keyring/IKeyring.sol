// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IKeyring {
  function isWalletAllowed(address) external view returns (bool);
}