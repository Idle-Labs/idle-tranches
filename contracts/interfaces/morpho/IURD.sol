// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/// @notice This contract allows Metamorpho users to claim their rewards
interface IURD {
  /// @notice Claims rewards.
  /// @param _account The address of the claimer.
  /// @param _reward The address of the reward.
  /// @param _claimable The overall claimable amount of token rewards.
  /// @param _proof The merkle proof that validates this claim.
  function claim(
    address _account,
    address _reward,
    uint256 _claimable,
    bytes32[] calldata _proof
  ) external;

  /// @notice Forces update the root of a given distribution (bypassing the timelock).
  /// @param newRoot The new merkle root.
  /// @param newIpfsHash The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
  function setRoot(
    bytes32 newRoot, 
    bytes32 newIpfsHash
  ) external;

  function owner() external view returns (address);
}
