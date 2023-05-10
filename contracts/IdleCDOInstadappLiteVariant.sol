// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IIdleCDOStrategy} from "./interfaces/IIdleCDOStrategy.sol";
import {IdleCDO} from "./IdleCDO.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";

/// @title IdleCDO variant
contract IdleCDOInstadappLiteVariant is IdleCDO {
    /// @notice the tolerance for the liquidation in basis points. 10000 = 100%
    /// @dev relative to the amount to liquidate
    uint256 internal liquidationToleranceBps;

    /// @notice the tolerance for the loss socialized so equally distributed between junior and senior tranches.
    /// @dev idleCDO works as usual if the loss percentage is less than this parameter.
    /// TODO: should change denomination? - FULL_ALLOC (100_000)
    uint256 internal lossToleranceBps;

    function _additionalInit() internal override {
        liquidationToleranceBps = 50; // 0.5%
        lossToleranceBps = 50; // 0.5%
    }

    /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted and the
    /// total gain/loss for a specific tranche
    /// @dev Main scenarios covered:
    /// - if there is a loss on the lending protocol (ie strategy price decrease) up to maxDecreaseDefault (_checkDefault method), the loss is
    ///     - totally absorbed by junior holders if they have enough TVL and deposits/redeems work as normal
    ///     - otherwise a 'default' error (4) is raised and deposits/redeems are blocked
    /// - if there is a loss on the lending protocol (ie strategy price decrease) more than maxDecreaseDefault all deposits and redeems
    ///   are blocked and a 'default' error (4) is raised
    /// - if there is a loss somewhere not in the lending protocol (ie in our contracts) and the TVL decreases then the same process as above
    ///   applies, the only difference is that maxDecreaseDefault is not considered
    /// In any case, once a loss happens, it only gets accounted when new deposits/redeems are made, but those are blocked.
    /// For this reason a protected updateAccounting method has been added which should be used to distributed the loss after a default event
    /// @param _tranche address of the requested tranche
    /// @param _nav current NAV
    /// @param _lastNAV last saved NAV
    /// @param _lastTrancheNAV last saved tranche NAV
    /// @param _trancheAPRSplitRatio APR split ratio for AA tranche
    /// @return _virtualPrice tranche price considering all interest
    /// @return _totalTrancheGain (int256) tranche gain/loss since last update
    function _virtualPriceAux(
        address _tranche,
        uint256 _nav,
        uint256 _lastNAV,
        uint256 _lastTrancheNAV,
        uint256 _trancheAPRSplitRatio
    ) internal view override returns (uint256 _virtualPrice, int256 _totalTrancheGain) {
        // Check if there are tranche holders
        uint256 trancheSupply = IdleCDOTranche(_tranche).totalSupply();
        if (_lastNAV == 0 || trancheSupply == 0) {
            return (oneToken, 0);
        }

        // In order to correctly split the interest generated between AA and BB tranche holders
        // (according to the trancheAPRSplitRatio) we need to know how much interest/loss we gained
        // since the last price update (during a depositXX/withdrawXX/harvest)
        // To do that we need to get the current value of the assets in this contract
        // and the last saved one (always during a depositXX/withdrawXX/harvest)
        // Calculate the total gain/loss
        int256 totalGain = int256(_nav) - int256(_lastNAV);
        // If there is no gain/loss return the current price
        if (totalGain == 0) {
            return (_tranchePrice(_tranche), 0);
        }

        // Remove performance fee for gains
        if (totalGain > 0) {
            totalGain -= (totalGain * int256(fee)) / int256(FULL_ALLOC);
        }

        address _AATranche = AATranche;
        address _BBTranche = BBTranche;
        bool _isAATranche = _tranche == _AATranche;
        // Get the supply of the other tranche and
        // if it's 0 then give all gain to the current `_tranche` holders
        if (IdleCDOTranche(_isAATranche ? _BBTranche : _AATranche).totalSupply() == 0) {
            _totalTrancheGain = totalGain;
        } else {
            if (totalGain > 0) {
                // Split the net gain, with precision loss favoring the AA tranche.
                int256 totalBBGain = (totalGain * int256(FULL_ALLOC - _trancheAPRSplitRatio)) / int256(FULL_ALLOC);
                // The new NAV for the tranche is old NAV + total gain for the tranche
                _totalTrancheGain = _isAATranche ? (totalGain - totalBBGain) : totalBBGain;
            } else if (uint256(-totalGain) <= (lossToleranceBps * _lastNAV) / 10_000) {
                // totalGain is negative here and up to loss socialization tolerance.
                // Check if the loss is less than loss tolerance
                // 1) -totalGain / (lastJuniorNAV + lastSeniorNAV) * 10_000 = -totalGain / _lastNav * 10_000 <= lossToleranceBps
                // 2) lastStrategyPrice * (10_000 - lossToleranceBps) / 10_000 <= currentStrategyPrice
                // socialize loss equally between junior and senior tranches
                // _totalTrancheGain = totalGain / 2
            } else {
                // totalGain is negative here
                // Redirect the whole loss (which should be < maxDecreaseDefault) to junior holders
                int256 _juniorTVL = int256(_isAATranche ? _lastNAV - _lastTrancheNAV : _lastTrancheNAV);
                int256 _newJuniorTVL = _juniorTVL + totalGain;
                // if junior holders have enough TVL to cover
                if (_newJuniorTVL > 0) {
                    _totalTrancheGain = _isAATranche ? int256(0) : totalGain;
                } else {
                    // otherwise all loss minus junior tvl to senior
                    if (!_isAATranche) {
                        // juniors have no more claim price is set to 0, gain is set to -juniorTVL
                        return (0, -_juniorTVL);
                    }
                    // seniors get the loss - old junior TVL
                    _totalTrancheGain = _newJuniorTVL;
                }
            }
        }
        // Split the new NAV (_lastTrancheNAV + _totalTrancheGain) per tranche token
        _virtualPrice =
            (uint256(int256(_lastTrancheNAV) + int256(_totalTrancheGain)) * ONE_TRANCHE_TOKEN) /
            trancheSupply;
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

    function setLiquidationToleranceBps(uint256 _diffBps) external {
        _checkOnlyOwner();
        liquidationToleranceBps = _diffBps;
    }
}
