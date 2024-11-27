// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCDOEpochVariant.sol";

/// @title Arbitrum variant of IdleCDOEpochVariant
contract IdleCDOEpochVariantArbitrum is IdleCDOEpochVariant {
  /// @notice update optimism addresses
  function _additionalInit() internal override {
    super._additionalInit();
    // no need to set weth address as harvest is disabled
    // weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    feeReceiver = 0xF40d482D7fc94C30b256Dc7E722033bae68EcF90; // treasury multisig
  }
}
