// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./IdleCDO.sol";

/// @title IdleCDO variant
contract IdleCDOInstadappLiteVariant is IdleCDO {
    /// 10000 = 100%
    uint256 liquidationToleranceBps;

    function _additionalInit() internal override {
        liquidationToleranceBps = 50; // 0.5%
    }

    /// @dev this should liquidate at least _amount of `token` from the lending provider or revertIfNeeded
    /// @param _amount in underlying tokens
    /// @param _revertIfNeeded flag whether to revert or not if the redeemed amount is not enough
    /// @return _redeemedTokens number of underlyings redeemed
    function _liquidate(uint256 _amount, bool _revertIfNeeded) internal override returns (uint256 _redeemedTokens) {
        _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
        if (_revertIfNeeded) {
            uint256 _tolerance = (_amount * liquidationToleranceBps) / 10000;
            // keep `_tolerance` wei as margin for rounding errors
            require(_redeemedTokens + _tolerance >= _amount, "5");
        }

        if (_redeemedTokens > _amount) {
            _redeemedTokens = _amount;
        }
    }

    // function setLiquidationTolerance(uint256 _diff) external override {
    //     revert("IdleCDOInstadappLiteVariant: setLiquidationTolerance not supported");
    // }
}
