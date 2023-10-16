// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IIdleCDOStrategy} from "./interfaces/IIdleCDOStrategy.sol";
import {IdleCDO} from "./IdleCDO.sol";
import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

interface IInstadappVaultV2 {
    function withdrawalFeePercentage() external view returns(uint256);
}

/// @title IdleCDO variant for instadapp iETHv2, which can handle a withdraw fee 
contract IdleCDOInstadappLiteVariant is IdleCDO {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice the tolerance for the liquidation in basis points. 100000 = 100%
    /// @dev relative to the amount to liquidate
    uint256 internal liquidationToleranceBps;
    address internal constant ETHV2Vault = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;

    function _additionalInit() internal override {
        liquidationToleranceBps = 500; // 0.5%
        lossToleranceBps = 500; // 0.5%
    }

    /// @notice a loss of up to liquidationToleranceBps % is allowed (slippage / withdraw fee)
    /// @dev this should liquidate at least _amount of `token` from the lending provider or revertIfNeeded
    /// @param _amount in underlying tokens
    /// @param _revertIfNeeded flag whether to revert or not if the redeemed amount is not enough
    /// @return _redeemedTokens number of underlyings redeemed
    /// @return _fee underlyings kept by the lending provider as fee
    function _liquidateWithFee(uint256 _amount, bool _revertIfNeeded) internal returns (
        uint256 _redeemedTokens,
        uint256 _fee
    ) {
        _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
        if (_revertIfNeeded) {
            uint256 _tolerance = (_amount * liquidationToleranceBps) / FULL_ALLOC;
            // keep `_tolerance` wei as margin for rounding errors
            require(_redeemedTokens + _tolerance >= _amount, "5");
        }

        if (_redeemedTokens > _amount) {
            _redeemedTokens = _amount;
        }
        _fee = _amount - _redeemedTokens;
    }

    /// @notice It calculates the expected fee for redeeming `_toRedeem` underlyings
    /// @param _toRedeem amount of underlyings to redeem
    /// @return _expectedFee amount of underlyings to be kept by the lending provider as fee
    function _calcUnderlyingProtocolFee(uint256 _toRedeem) virtual internal returns (uint256 _expectedFee) {
        // get exit fee from instadapp vault
        // from instadapp: withdraw fee is either amount in percentage or absolute minimum. This var defines the percentage in 1e6
        // this number is given in 1e4, i.e. 1% would equal 10,000; 10% would be 100,000 etc.
        _expectedFee = _toRedeem * IInstadappVaultV2(ETHV2Vault).withdrawalFeePercentage() / 1e6;
    }

    /// @notice It allows users to burn their tranche token and redeem their principal + interest back
    /// @dev automatically reverts on lending provider default (_strategyPrice decreased).
    /// @dev in this variant the fee is readded after the _liquidate call so the lastNAV is updated correctly
    /// @param _amount in tranche tokens
    /// @param _tranche tranche address
    /// @return toRedeem number of underlyings redeemed
    function _withdraw(uint256 _amount, address _tranche) override internal nonReentrant returns (uint256 toRedeem) {
        // check if a deposit is made in the same block from the same user
        _checkSameTx();
        // check if _strategyPrice decreased
        _checkDefault();
        // accrue interest to tranches and updates tranche prices
        _updateAccounting();
        // redeem all user balance if 0 is passed as _amount
        if (_amount == 0) {
            _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
        }
        require(_amount > 0, '0');
        address _token = token;
        // get current available unlent balance
        uint256 balanceUnderlying = _contractTokenBalance(_token);
        // Calculate the amount to redeem
        toRedeem = _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
        // save full amount that user is redeeming (without counting fees)
        uint256 _want = toRedeem;
        // calculate expected fee
        uint256 _expectedFee = _calcUnderlyingProtocolFee(toRedeem);
        // actual fee paid, considering the unlent balance present in this contract
        // this value should be lte than _expectedFee as only a portion of the toRedeem
        // will be redeemed from the lending provider if there is some unlent balance
        uint256 _paidFee;
        if (toRedeem > balanceUnderlying) {
            // if the unlent balance is not enough we try to redeem what's missing directly from the strategy
            // and then add it to the current unlent balance
            (toRedeem, _paidFee) = _liquidateWithFee(toRedeem - balanceUnderlying, revertIfTooLow);
            // add the unlent balance to the redeemed amount
            toRedeem += balanceUnderlying;
            // be sure to remove the missing fee, even when using 
            // the unlent balance the user should pay the full fee
            if (_paidFee < _expectedFee) {
                toRedeem -= (_expectedFee - _paidFee);
            }
        } else {
            // user is redeeming all from the unlent balance but the fee is still applied,
            // the pool is 'gaining' the _expectedFee which will increase the lastNAV
            toRedeem -= _expectedFee;
        }

        // burn tranche token
        IdleCDOTranche(_tranche).burn(msg.sender, _amount);

        // update NAV with the _amount of underlyings removed (eventual fee gained is not
        // considered here so virtualPrice will be updated accordingly)
        if (_tranche == AATranche) {
            lastNAVAA -= _want;
        } else {
            lastNAVBB -= _want;
        }
        // update trancheAPRSplitRatio
        _updateSplitRatio(_getAARatio(true));

        // send underlying to msg.sender. Keep this at the end of the function to avoid 
        // potential read only reentrancy on cdo variants that have hooks (eg with nfts)
        IERC20Detailed(_token).safeTransfer(msg.sender, toRedeem);
    }

    /// @param _diffBps tolerance in % (FULL_ALLOC = 100%) for allowing loss on redeems for msg.sender 
    function setLiquidationToleranceBps(uint256 _diffBps) external {
        _checkOnlyOwner();
        liquidationToleranceBps = _diffBps;
    }
}
