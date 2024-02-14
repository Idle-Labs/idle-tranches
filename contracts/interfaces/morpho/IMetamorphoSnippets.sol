// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IMetamorphoSnippets {
  function supplyAPRVault(address vault) external view returns (uint256 avgSupplyRate);
  function supplyAPRVault(address vault, uint256 add, uint256 sub) external view returns (uint256 avgSupplyRate);
}
