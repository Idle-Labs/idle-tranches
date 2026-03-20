// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCDOEpochVariant.sol";

/// @title Avax variant of IdleCDOEpochVariant
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract IdleCDOEpochVariantAvax is IdleCDOEpochVariant {
  /// @notice update avax addresses
  function _additionalInit() internal override {
    super._additionalInit();
    assembly {
      sstore(feeReceiver.slot, 0x8b2aAC97A2dEae85dCD506558c1DeE0f2aeC0550)
    }
  }
}
