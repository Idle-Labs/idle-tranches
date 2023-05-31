// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IIdleCDOStrategy} from "./interfaces/IIdleCDOStrategy.sol";
import {IdleCDO} from "./IdleCDO.sol";

/// @title IdleCDO variant
contract IdleCDOInstadappLiteVariant is IdleCDO {
    /// @notice the tolerance for the liquidation in basis points. 100000 = 100%
    /// @dev relative to the amount to liquidate
    uint256 internal liquidationToleranceBps;

    function _additionalInit() internal override {
        liquidationToleranceBps = 500; // 0.5%
        lossToleranceBps = 500; // 0.5%
    }

    /// @notice a loss of up to liquidationToleranceBps % is allowed (slippage / withdraw fee)
    /// @dev this should liquidate at least _amount of `token` from the lending provider or revertIfNeeded
    /// @param _amount in underlying tokens
    /// @param _revertIfNeeded flag whether to revert or not if the redeemed amount is not enough
    /// @return _redeemedTokens number of underlyings redeemed
    function _liquidate(uint256 _amount, bool _revertIfNeeded) internal override returns (uint256 _redeemedTokens) {
        _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
        if (_revertIfNeeded) {
            uint256 _tolerance = (_amount * liquidationToleranceBps) / FULL_ALLOC;
            // keep `_tolerance` wei as margin for rounding errors
            require(_redeemedTokens + _tolerance >= _amount, "5");
        }

        if (_redeemedTokens > _amount) {
            _redeemedTokens = _amount;
        }
    }

    /// @param _diffBps tolerance in % (FULL_ALLOC = 100%) for allowing loss on redeems for msg.sender 
    function setLiquidationToleranceBps(uint256 _diffBps) external {
        _checkOnlyOwner();
        liquidationToleranceBps = _diffBps;
    }
}
