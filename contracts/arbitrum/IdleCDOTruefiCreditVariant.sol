// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOArbitrum} from "./IdleCDOArbitrum.sol";

/// @title IdleCDO variant for Truefi Lines of Credit https://docs.truefi.io/faq/truefi-protocol/automated-lines-of-credit/lines-of-credit-technical-details
contract IdleCDOTruefiCreditVariant is IdleCDOArbitrum {

  /// @notice If loss < 1% => loss do not follow junior / senior but is socialized
  /// if 1% < loss < 5% (ie maxDecreaseDefault) => junior tranche will absorb the loss
  /// if loss > 5% => junior will absorb the loss and pool goes into default
  function _additionalInit() internal override {
    super._additionalInit();
    lossToleranceBps = 1000; // 1% (there is a 0.5% fee on TVL over a year + some buffer)
  }
}
