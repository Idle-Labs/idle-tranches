// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IMerkle {
  function getRoot(bytes32[] memory leaves) external pure returns (bytes32);
  function getRoot(bytes32[] memory leaves, uint256 index) external pure returns (bytes32);
  function getProof(bytes32[] memory leaves, uint256 index) external pure returns (bytes32[] memory);
}
