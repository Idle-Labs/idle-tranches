// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCDOEpochVariant.sol";

/// @title Polygon variant of IdleCDOEpochVariant
contract IdleCDOEpochVariantPolygon is IdleCDOEpochVariant {
  /// @notice update Polygon addresses
  function _additionalInit() internal override {
    super._additionalInit();
    // no need to set weth address as harvest is disabled
    feeReceiver = 0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6; // treasury multisig
  }
}
