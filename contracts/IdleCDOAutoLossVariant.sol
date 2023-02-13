// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./IdleCDO.sol";

/// @title IdleCDO variant for automatically spread any losses, up to a threshold, 
/// directly to junior holders. Based on IdleCDOLeveregedEulerVarial.sol
/// @author Idle DAO, @bugduino
/// @dev In this variant the `_checkDefault` calculates if strategy price decreased 
/// more than X% with X configurable. `_virtualPriceAuxVariant` is also modified to redistribute
/// loss to junior holders only
/// Main scenarios covered:
/// - if there is a loss on the lending protocol (ie strategy price decrease) up to a configurable percentage, the loss is
///     - totally absorbed by junior holders if they have enough TVL
///     - otherwise a default error (4) is raised and deposits/redeems are blocked
/// - if there is a loss on the lending protocol (ie strategy price decrease) more than the configured percentage all deposits and redeems 
///   are blocked and a default error (4) is raised
/// - if there is a loss somewhere not in the lending protocol (ie in our contracts) and the TVL decreases then the same process as above 
///   applies, the only difference is that the max decrease percentage is not considered
/// In any case, once a loss happens, it only gets accounted when new deposits/redeems are made, but those are blocked. 
/// For this reason a protected updateAccounting method has been added which should be used to distributed the loss after a default event
contract IdleCDOAutoLossVariant is IdleCDO {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted
  /// ie the interest/loss generated since the last update of priceAA and priceBB (done on depositXX/withdrawXX/harvest)
  /// useful for showing updated gains on frontends
  /// @param _tranche address of the requested tranche
  /// @return _virtualPrice tranche price considering all interest/losses
  function virtualPrice(address _tranche) public override view returns (uint256 _virtualPrice) {
    // get both NAVs, because we need the total NAV anyway
    uint256 _lastNAVAA = lastNAVAA;
    uint256 _lastNAVBB = lastNAVBB;

    (_virtualPrice, ) = _virtualPriceAuxVariant(
      _tranche,
      getContractValue(), // nav
      _lastNAVAA + _lastNAVBB, // lastNAV
      _tranche == AATranche ? _lastNAVAA : _lastNAVBB, // lastTrancheNAV
      trancheAPRSplitRatio
    );
  }

  /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted and the
  /// total gain/loss for a specific tranche
  /// @param _tranche address of the requested tranche
  /// @param _nav current NAV
  /// @param _lastNAV last saved NAV
  /// @param _lastTrancheNAV last saved tranche NAV
  /// @param _trancheAPRSplitRatio APR split ratio for AA tranche
  /// @return _virtualPrice tranche price considering all interest
  /// @return _totalTrancheGain (int256) tranche gain/loss since last update
  function _virtualPriceAuxVariant(
    address _tranche,
    uint256 _nav,
    uint256 _lastNAV,
    uint256 _lastTrancheNAV,
    uint256 _trancheAPRSplitRatio
  ) internal view returns (uint256 _virtualPrice, int256 _totalTrancheGain) {
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
      totalGain -= totalGain * int256(fee) / int256(FULL_ALLOC);
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
        int256 totalBBGain = totalGain * int256(FULL_ALLOC - _trancheAPRSplitRatio) / int256(FULL_ALLOC);
        // The new NAV for the tranche is old NAV + total gain for the tranche
        _totalTrancheGain = _isAATranche ? (totalGain - totalBBGain) : totalBBGain;
      } else { // totalGain is negative here
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
    _virtualPrice = uint256(int256(_lastTrancheNAV) + int256(_totalTrancheGain)) * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @notice this method updates the accounting of the contract and effectively splits the yield/loss between the
  /// AA and BB tranches. This can be called at any time as is called automatically on each deposit/redeem. It's here
  /// just to be called when a default happened, as deposits/redeems are paused, but we need to update
  /// the loss for junior holders
  function updateAccounting() external {
    _checkOnlyOwnerOrGuardian();
    skipDefaultCheck = true;
    _updateAccounting();
    // update accounting can set `skipDefaultCheck` to true in case of default
    // but this can be manually be reset to true if needed
    skipDefaultCheck = false;
  }

  /// @notice this method is called on depositXX/withdrawXX/harvest and
  /// updates the accounting of the contract and effectively splits the yield/loss between the
  /// AA and BB tranches
  /// @dev this method:
  /// - update tranche prices (priceAA and priceBB)
  /// - update net asset value for both tranches (lastNAVAA and lastNAVBB)
  /// - update fee accounting (unclaimedFees)
  function _updateAccounting() internal override {
    uint256 _lastNAVAA = lastNAVAA;
    uint256 _lastNAVBB = lastNAVBB;
    uint256 _lastNAV = _lastNAVAA + _lastNAVBB;
    uint256 nav = getContractValue();
    uint256 _aprSplitRatio = trancheAPRSplitRatio;
    // If gain is > 0, then collect some fees in `unclaimedFees`
    if (nav > _lastNAV) {
      unclaimedFees += (nav - _lastNAV) * fee / FULL_ALLOC;
    }
    (uint256 _priceAA, int256 _totalAAGain) = _virtualPriceAuxVariant(AATranche, nav, _lastNAV, _lastNAVAA, _aprSplitRatio);
    (uint256 _priceBB, int256 _totalBBGain) = _virtualPriceAuxVariant(BBTranche, nav, _lastNAV, _lastNAVBB, _aprSplitRatio);
    lastNAVAA = uint256(int256(_lastNAVAA) + _totalAAGain);

    // if we have a loss for juniors and the loss is gte lastNAV we trigger a default
    if (_totalBBGain < 0 && -_totalBBGain >= int256(_lastNAVBB)) {
      if (skipDefaultCheck) {
        // This path will be called when a default happens and guardian calls
        // `updateAccounting` after setting skipDefaultCheck
        // We set lastNAVBB to 1 wei * tranche token
        lastNAVBB = IdleCDOTranche(BBTranche).totalSupply() / ONE_TRANCHE_TOKEN;
        _emergencyShutdown();
      } else {
        // revert with 'default' error (4) as seniors will have a loss not covered. 
        // `updateAccounting` should be manually called to distribute loss
        require(false, "4"); 
      }
    } else {
      lastNAVBB = uint256(int256(_lastNAVBB) + _totalBBGain);
    }
    priceAA = _priceAA;
    priceBB = _priceBB;
  }
}
