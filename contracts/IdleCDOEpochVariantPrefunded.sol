// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

interface IIdleCDOEpochQueuePrefunded {
  function epochPendingDeposits(uint256) external view returns (uint256);
  function epochPrefundedDeposits(uint256) external view returns (uint256);
  function processPrefundedDeposits(uint256, uint256) external;
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

  /// @inheritdoc IdleCDOEpochVariant
  /// @dev When prefunded processing is configured, managers must use `stopEpochWithDuration`
  /// so the queue settlement hook always runs after the full stop flow.
  function stopEpoch(uint256 _newApr, uint256 _interest) public override {
    // `stopEpochWithDuration` calls `stopEpoch` internally, so only block the direct selector path.
    _checkNotAllowed(epochQueue != address(0) && msg.sig == this.stopEpoch.selector);
    super.stopEpoch(_newApr, _interest);
  }

  /// @inheritdoc IdleCDOEpochVariant
  /// @dev After the base epoch stop logic runs, this variant also settles AA deposits that were
  /// already prefunded to the borrower through the queue, even if the borrower defaulted at stop.
  function stopEpochWithDuration(uint256 _newApr, uint256 _interest, uint256 _duration, uint256 _lossAmount) public override {
    super.stopEpochWithDuration(_newApr, _interest, _duration, _lossAmount);

    address _queue = epochQueue;
    if (_queue != address(0)) {
      IIdleCDOEpochQueuePrefunded _epochQueue = IIdleCDOEpochQueuePrefunded(_queue);
      IdleCreditVault _strategy = IdleCreditVault(strategy);
      // On borrower default the base stop flow does not bump the strategy epoch number, but prefunded
      // deposits still belong to the epoch that just finished and must be settled against that epoch id.
      uint256 _epoch = _strategy.epochNumber() + (defaulted ? 1 : 0);
      uint256 _prefunded = _epochQueue.epochPrefundedDeposits(_epoch);
      if (_prefunded != 0) {
        // Prefunded deposits already reached the borrower, so they must join AA even if stop defaulted.
        // Mint tranche shares at the post-stop price and mirror the same amount in strategy tokens,
        // so the queue can later distribute shares to users at the epoch price.
        uint256 _prefundedMinted = _mintSharesAtCurrPrice(_prefunded, _queue, AATranche);
        _strategy.mintStrategyTokens(_prefunded);
        // Finalize the prefunded epoch in the queue by storing the epoch price and clearing state.
        _epochQueue.processPrefundedDeposits(_epoch, _prefundedMinted);
      } else {
        // Prefunded queues must not reach stopEpochWithDuration with raw underlyings still sitting in the queue.
        _checkNotAllowed(_epochQueue.epochPendingDeposits(_epoch) != 0);
      }
    }
  }
}
