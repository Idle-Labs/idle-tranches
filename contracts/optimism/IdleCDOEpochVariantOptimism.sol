// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCDOEpochVariant.sol";

/// @title Optimism variant of IdleCDOEpochVariant
contract IdleCDOEpochVariantOptimism is IdleCDOEpochVariant {
  /// @notice update optimism addresses
  function _additionalInit() internal override {
    super._additionalInit();
    // no need to set weth address as harvest is disabled
    // weth = 0x4200000000000000000000000000000000000006;
    feeReceiver = 0xFDbB4d606C199F091143BD604C85c191a526fbd0; // treasury multisig
  }
}
