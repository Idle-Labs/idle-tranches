// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDO} from "./IdleCDO.sol";
import "./IdleCDOTranche.sol";
import "./strategies/usual/IdleUsualStrategy.sol";

/// @title IdleCDO variant for Usual usd0++ depeg protection
/// @dev users deposits usd0++ in either senior or junior tranches. At the end of the epoch each of the senior 
/// tranche token should be at 1$ parity. If the price of usd0++ is less than 1$ the senior tranche will receive
/// funds from junior tranche to reach 1$ parity. 
/// The vault will harvest yield (in USUAL tokens) during the epoch and distribute it all to the senior tranche.
/// The pool will have deposits/and redeem paused once start, to simulate an epoch, and then no more deposits/redeems
/// will be allowed for the epoch duration, likely 6 months. At the end of the epoch, the pool will be unpaused and
/// interest distributed to the tranches. The vault is 'disposable' meaning that it will run only for 1 epoch.
/// At the end of the epoch vault fetches the oracle price for usd0++ and calculates how much junior should give to senior
contract IdleCDOUsualVariant is IdleCDO {
  // This is the simplified flow:
  // 1. users deposits, updateAccounting (won't change prices), other deposits.
  // 2. start epoch, deposits/redeems paused. We deposit all usd0++ in the strategy and mint strategyTokens 1:1 with the underlyings sent.
  // 3. multiple harvests and updateAccounting during epoch. We give all yield to junior. 
  //    Price of seniors won't change during epoch (strategyPtice never changes)
  // 4. Stop epoch, redeems enabled. We fetch chainlink price for usd0++ and calculate what should be the target TVL for AA to 
  //    reach 1$ parity. We manually set lastNAVAA to the target AA NAV. We trigger updateAccounting, this update accounting will 
  //    consider to have a loss (eq to the diff between lastNAVAA and target AA tvl) and this loss will be absorbed by junior

  /// @notice usd0++ price at the start of the epoch
  uint256 public priceAtStartEpoch;
  /// @notice flag to check if the epoch is running
  bool public isEpochRunning;

  function _additionalInit() internal override {
    // no unlent perc
    unlentPerc = 0;
    // we set the release block period to 0 because when epoch starts we pause deposits / redeems
    releaseBlocksPeriod = 0;
    // we don't default automatically as strategyPrice is always set to one underlying token
    maxDecreaseDefault = FULL_ALLOC;
    // we don't use the tranche apr split ratio as all yield goes to junior and then junior eventually covers seniors
    isAYSActive = false;
  }

  /// @notice start the epoch, disable new deposits / redeems
  function startEpoch() external {
    _checkOnlyOwner();

    // we pause deposits
    _pause();
    // prevent withdrawals
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    // set epoch as not running
    isEpochRunning = true;

    // save initial price for reference
    address _strategy = strategy;
    priceAtStartEpoch = IdleUsualStrategy(_strategy).getChainlinkPrice();

    // deposit all usd0++ in the strategy and mint strategyTokens 1:1
    IIdleCDOStrategy(_strategy).deposit(IERC20Detailed(token).balanceOf(address(this)));
  }

  /// @notice stop the epoch, enable redeems only
  function stopEpoch() external {
    _checkOnlyOwner();

    IdleUsualStrategy _strategy = IdleUsualStrategy(strategy);
    // we fetch and set oracle price for reference
    uint256 _oraclePrice = _strategy.getChainlinkPrice();
    _strategy.setOraclePrice(_oraclePrice);

    // we unpause redeems only
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    // set epoch as not running
    isEpochRunning = false;

    // if usd0++ price is 1$ or more then junior doesn't owe anything to senior
    if (_oraclePrice >= oneToken) {
      return;
    }
    // if price is less than 1$ we calculate how much junior should give to senior considering 1 usd0++ = 1$
    // eg price is 0.9$, lastNAVAA is 100 usd0++ (ie 90$) and targetAATVL should be 100$ so 100 / 0.9 = 111.11 usd0++
    // so we do lastNAVAA * (1 / oraclePrice) = 100 * (1 / 0.9) = 111.11
    uint256 targetAATVL = lastNAVAA * oneToken / _oraclePrice;

    // we increase the lastNAVAA so that the senior tranche is at par with 1$
    lastNAVAA += targetAATVL - lastNAVAA;

    // this will cause the next updateAccounting call to account a loss which will be absorbed by the junior tranche
    _updateAccounting();    
  }

  /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted and the
  /// total gain/loss for a specific tranche
  /// @dev Check IdleCDO.sol for more details. Only change is inside the `if (totalGain > 0)` block rest is the same
  /// @param _nav current NAV
  /// @param _lastNAV last saved NAV
  /// @param _lastTrancheNAV last saved tranche NAV
  /// @return _virtualPrice tranche price considering all interest
  /// @return _totalTrancheGain (int256) tranche gain/loss since last update
  function _virtualPriceAux(
    address _tranche,
    uint256 _nav,
    uint256 _lastNAV,
    uint256 _lastTrancheNAV,
    uint256
  ) internal override view returns (uint256 _virtualPrice, int256 _totalTrancheGain) {
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
      // if we gained something
      if (totalGain > 0) {
        // we give all yield to junior
        _totalTrancheGain = _isAATranche ? int256(0) : totalGain;
      } else { // totalGain is negative here
        // Redirect the whole loss (which should be < maxDecreaseDefault) to junior holders
        int256 _juniorTVL = int256(_isAATranche ? _lastNAV - _lastTrancheNAV : _lastTrancheNAV);
        int256 _newJuniorTVL = _juniorTVL + totalGain; 
        // if junior holders have enough TVL to cover
        if (_newJuniorTVL > 0) {
          // then juniors get all loss (totalGain) and senior gets 0 loss
          _totalTrancheGain = _isAATranche ? int256(0) : totalGain;
        } else {
          // otherwise all loss minus junior tvl to senior
          if (!_isAATranche) {
            // juniors have no more claims, price is set to 0, gain is set to -juniorTVL
            return (0, -_juniorTVL);
          }
          // seniors get the loss - old junior TVL
          _totalTrancheGain = _newJuniorTVL;
        }
      }
    }
    // Split the new NAV (_lastTrancheNAV + _totalTrancheGain) per tranche token
    _virtualPrice = uint256(int256(_lastTrancheNAV) + _totalTrancheGain) * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// NOTE: strategy price is alway equal to 1 underlying
  function _checkDefault() override internal {}
  function setSkipDefaultCheck(bool) external override {}
  function setMaxDecreaseDefault(uint256) external override {}

  /// NOTE: unlent perc should always be 0 and set in additionalInit
  function setUnlentPerc(uint256) external override {}
  /// NOTE: the vault is not using the traditional split ratio
  function setTrancheAPRSplitRatio(uint256) external override {}

  /// NOTE: stkIDLE gating is not used
  function toggleStkIDLEForTranche(address) external override {}
  function _checkStkIDLEBal(address, uint256) internal view override {}
  function setStkIDLEPerUnderlying(uint256) external override {}
}
