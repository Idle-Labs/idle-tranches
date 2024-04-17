// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDO} from "./IdleCDO.sol";

/// @title IdleCDO variant for gearbox passive lending.
/// @notice strategyToken is set to the strategy itself which tokenizes the staked position (sdTokens) to farm GEAR
contract IdleCDOGearboxVariant is IdleCDO {
  function _additionalInit() internal override {
    strategyToken = strategy;
  }
}
