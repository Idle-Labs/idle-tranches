// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

interface IIdleCDOEpochQueuePrefunded {
  function prefundedDepositsToProcess() external view returns (uint256);
  function epochPrefundedDeposits(uint256) external view returns (uint256);
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

  /// @inheritdoc IdleCDOEpochVariant
  function setInstantWithdrawParams(uint256 _delay, uint256 _aprDelta, bool _disable) public override {
    _checkNotAllowed(!_disable);
    super.setInstantWithdrawParams(_delay, _aprDelta, true);
  }

  /// @notice Block the direct `stopEpoch` selector when a prefunded queue is configured
  /// @dev `stopEpochWithDuration` still reaches the base stop flow through an internal call.
  /// @param _isClosing true when this stop recalls all pool principal
  /// @return additionalPrincipal prefunded principal already sent to the borrower
  function _beforeStopEpoch(bool _isClosing) internal view override returns (uint256 additionalPrincipal) {
    // `stopEpochWithDuration` calls `stopEpoch` internally, so only block the direct selector path.
    address _queue = epochQueue;
    if (_queue == address(0)) return additionalPrincipal;
    _checkNotAllowed(msg.sig == this.stopEpoch.selector);
    if (_isClosing) {
      uint256 nextEpoch = IdleCreditVault(strategy).epochNumber() + 1;
      additionalPrincipal = IIdleCDOEpochQueuePrefunded(_queue).epochPrefundedDeposits(nextEpoch);
    }
  }

  /// @notice Disable mid-epoch deposits for the prefunded variant.
  function depositDuringEpoch(uint256, address) external pure override returns (uint256) {
    _checkNotAllowed(true);
    return 0;
  }

  /// @inheritdoc IdleCDOEpochVariant
  function _isInstantWithdrawEnabled() internal pure override returns (bool) {
    return false;
  }

  /// @notice Check whether an amount can safely move from the queue to the borrower.
  /// @dev Includes the persistent emergency flag and guarded-launch limit that the queue cannot
  /// otherwise observe. The amount must include all queue deposits targeted to the next epoch.
  /// @param _amount queued underlying proposed for prefunding
  function checkPrefunding(uint256 _amount) external view {
    _checkNotAllowed(defaulted || skipDefaultCheck || priceAA == 0);
    _guarded(_amount);
  }

  /// @notice Finalize prefunded queue deposits after the base stop flow completes
  /// @dev Prefunded AA deposits are minted at the post-stop price even if the borrower defaulted during stop
  function _afterStopEpochWithDuration() internal override {
    address _queue = epochQueue;
    if (_queue == address(0)) return;

    IIdleCDOEpochQueuePrefunded _epochQueue = IIdleCDOEpochQueuePrefunded(_queue);
    uint256 _prefunded = _epochQueue.prefundedDepositsToProcess();
    if (_prefunded == 0) return;
    // A zero post-loss AA price cannot safely mint new shares into the same tranche token.
    _checkNotAllowed(priceAA == 0);

    // Prefunded deposits already reached the borrower, so they must join AA even if stop defaulted.
    // Mint tranche shares at the post-stop price and mirror the same amount in strategy tokens,
    // so the queue can later distribute shares to users at the epoch price.
    uint256 _prefundedMinted = _mintSharesAtCurrPrice(_prefunded, _queue, AATranche);
    IdleCreditVault(strategy).mintStrategyTokens(_prefunded);
    // Finalize the prefunded epoch in the queue by storing the epoch price and clearing state.
    _epochQueue.processPrefundedDeposits(_prefundedMinted);
  }
}
