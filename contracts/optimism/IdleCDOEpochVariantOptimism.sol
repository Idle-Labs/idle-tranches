// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCDOEpochVariant.sol";

/// @title Optimism variant of IdleCDOEpochVariant
contract IdleCDOEpochVariantOptimism is IdleCDOEpochVariant {
  /// @notice update optimism addresses
  function _additionalInit() internal override {
    super._additionalInit();

    weth = address(0x4200000000000000000000000000000000000006);
    feeReceiver = address(0xFDbB4d606C199F091143BD604C85c191a526fbd0); // treasury multisig
    releaseBlocksPeriod = 302400; // 60 * 60 * 24 / 2 * 7 = ~1 week (blocktime 2s)
  }
}
