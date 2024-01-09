// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IMetamorphoSnippets {
  function supplyAPYVault(address vault) external view returns (uint256 avgSupplyRate);
}
