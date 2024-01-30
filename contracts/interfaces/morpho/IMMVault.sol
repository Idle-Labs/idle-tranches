// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../IERC20Detailed.sol";

interface IMMVault is IERC20Detailed {
  function withdrawQueueLength() external view returns (uint256);
  function withdrawQueue(uint256 idx) external view returns (bytes32);
  function convertToAssets(uint256) external view returns (uint256);
  function totalAssets() external view returns (uint256);
}

