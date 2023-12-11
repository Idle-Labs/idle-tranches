// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IIdleCDOStrategy} from "./interfaces/IIdleCDOStrategy.sol";
import {IdleCDO} from "./IdleCDO.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";
import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title IdleCDO variant for amphor, which has epochs and deposit/withdraw windows
contract IdleCDOAmphorVariant is IdleCDO {
  using SafeERC20Upgradeable for IERC20Detailed;

  function _additionalInit() internal override {
    unlentPerc = 0;
    lossToleranceBps = 500; // 0.5%
  }

  /// @notice method used to deposit `token` and mint tranche tokens
  /// @dev deposit underlyings to strategy immediately. This method can 
  /// revert if the strategy is not accepting new deposits ie when
  /// epoch is already started
  /// @return _minted number of tranche tokens minted
  function _deposit(
    uint256 _amount,
    address _tranche,
    address _referral
  ) internal override whenNotPaused returns (uint256 _minted) {
    _minted = super._deposit(_amount, _tranche, _referral);
    // This is done to avoid having people deposits in the vault
    // when an epoch is running, which would imply getting yield
    // from others which have funds actually deposited in the strategy
    // while these funds will be left unlent
    IIdleCDOStrategy(strategy).deposit(_amount);
  }

  /// @notice mint tranche tokens and updates tranche last NAV
  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _mintShares(uint256 _amount, address _to, address _tranche) internal override returns (uint256 _minted) {
    // calculate # of tranche token to mint based on current tranche price: _amount / tranchePrice
    // we should remove 1 wei per 1 unit of underlying from _amount 
    // to avoid rounding issues given that tokens are deposited directly by the user in the strategy
    // eg if we deposit 100 USDC (100 * 1e6) we should set _amount to 100 * 1e6 - 100
    _amount -= _amount / oneToken;

    _minted = _amount * ONE_TRANCHE_TOKEN / _tranchePrice(_tranche);

    IdleCDOTranche(_tranche).mint(_to, _minted);
    // update NAV with the _amount of underlyings added
    if (_tranche == AATranche) {
      lastNAVAA += _amount;
    } else {
      lastNAVBB += _amount;
    }
  }
}
