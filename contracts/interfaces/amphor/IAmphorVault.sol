// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IAmphorVault {
  // @dev The `start` function is used to start the lock period of the vault.
  // It is the only way to lock the vault. `onlyOwner`
  function start() external;
  // @dev The `end` function is used to end the lock period of the vault.
  // @notice onlyOwner and only when the vault is locked.
  // @param assetReturned The underlying assets amount to be deposited into
  // the vault (transferFrom)
  function end(uint256 assetReturned) external;
  // @dev The locking status of the vault.
  // @return `true` if the vault is open for deposits, `false` otherwise.
  function vaultIsOpen() external returns (bool);
  // @dev The total underlying assets amount just before the lock period.
  // @return Amount of the total underlying assets just before the last vault
  // locking.
  function lastSavedBalance() external returns (uint256);
  function owner() external returns (address);
}