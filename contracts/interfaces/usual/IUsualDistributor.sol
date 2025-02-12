// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

struct QueuedOffChainDistribution {
  /// @notice Timestamp of the queued distribution
  uint256 timestamp;
  /// @notice Merkle root of the queued distribution
  bytes32 merkleRoot;
}

interface IUsualDistributor {
  function claimOffChainDistribution(address account, uint256 amount, bytes32[] calldata proof) external;
  function getOffChainDistributionData() external view returns (uint256 timestamp, bytes32 merkleRoot);
  function getOffChainDistributionQueue()
    external
    view
    returns (QueuedOffChainDistribution[] memory);
}
