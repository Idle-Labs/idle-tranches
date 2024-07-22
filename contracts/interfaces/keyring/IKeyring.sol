// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IKeyring {
  function checkCredential(uint256 policyId, address entity) external view returns (bool);
}