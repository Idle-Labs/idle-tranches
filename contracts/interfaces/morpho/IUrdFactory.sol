// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./IURD.sol";

interface IUrdFactory {
  function createUrd(
    address initialOwner,
    uint256 initialTimelock,
    bytes32 initialRoot,
    bytes32 initialIpfsHash,
    bytes32 salt
  ) external returns (IURD);
}
