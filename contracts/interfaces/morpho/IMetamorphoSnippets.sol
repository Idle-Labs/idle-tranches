// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/// @notice This contract allows Metamorpho users to claim their rewards
interface IMetamorphoSnippets {
  function supplyAPYVault(address vault) external view returns (uint256 avgSupplyRate);
}
