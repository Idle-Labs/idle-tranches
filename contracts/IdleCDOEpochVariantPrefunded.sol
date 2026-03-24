// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

interface IIdleCDOEpochQueuePrefunded {
  function prefundedDepositsToProcess() external view returns (uint256);
  function processPrefundedDeposits(uint256) external;
}

/// @title IdleCDOEpochVariant with prefunded queue deposit processing
/// @dev Use this variant when queue deposits are prefunded to borrower before epoch stop.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract IdleCDOEpochVariantPrefunded is IdleCDOEpochVariant {
  /// @notice queue used for prefunded deposit processing
  address public epochQueue;

  /// @notice set queue used for prefunded processing
  /// @param _epochQueue queue address (can be zero to disable auto processing)
  /// @dev Operational invariant: do not change the queue after deposits were already prefunded
  /// to the borrower and before `stopEpochWithDuration` settles that epoch.
  function setEpochQueue(address _epochQueue) external {
    _checkOnlyOwnerOrManager();
    epochQueue = _epochQueue;
  }

  /// @notice Block the direct `stopEpoch` selector when a prefunded queue is configured
  /// @dev `stopEpochWithDuration` still reaches the base stop flow through an internal call
  function _beforeStopEpoch() internal view override {
    // `stopEpochWithDuration` calls `stopEpoch` internally, so only block the direct selector path.
    _checkNotAllowed(epochQueue != address(0) && msg.sig == this.stopEpoch.selector);
  }

  /// @notice Finalize prefunded queue deposits after the base stop flow completes
  /// @dev Prefunded AA deposits are minted at the post-stop price even if the borrower defaulted during stop
  function _afterStopEpochWithDuration() internal override {
    address _queue = epochQueue;
    if (_queue == address(0)) return;

    IIdleCDOEpochQueuePrefunded _epochQueue = IIdleCDOEpochQueuePrefunded(_queue);
    uint256 _prefunded = _epochQueue.prefundedDepositsToProcess();
    if (_prefunded == 0) return;

    // Prefunded deposits already reached the borrower, so they must join AA even if stop defaulted.
    // Mint tranche shares at the post-stop price and mirror the same amount in strategy tokens,
    // so the queue can later distribute shares to users at the epoch price.
    uint256 _prefundedMinted = _mintSharesAtCurrPrice(_prefunded, _queue, AATranche);
    IdleCreditVault(strategy).mintStrategyTokens(_prefunded);
    // Finalize the prefunded epoch in the queue by storing the epoch price and clearing state.
    _epochQueue.processPrefundedDeposits(_prefundedMinted);
  }
}
