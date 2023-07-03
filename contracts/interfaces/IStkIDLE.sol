// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IStkIDLE {
  function create_lock(uint256 _val, uint256 _unlock) external;
  function increase_amount(uint256 _val) external;
  function smart_wallet_checker() external view returns (address);
}

interface SmartWalletChecker {
  function toggleIsOpen(bool _open) external;
}
