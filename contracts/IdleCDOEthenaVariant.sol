// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IIdleCDOStrategy} from "./interfaces/IIdleCDOStrategy.sol";
import {IdleCDO} from "./IdleCDO.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";
import {EthenaCooldownRequest} from "./strategies/ethena/EthenaCooldownRequest.sol";
import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {IStakedUSDeV2} from "./interfaces/ethena/IStakedUSDeV2.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

/// @title IdleCDO variant for ethena susde, which has a cooldown period for withdrawals
contract IdleCDOEthenaVariant is IdleCDO {
  using SafeERC20Upgradeable for IERC20Detailed;
  using ClonesWithImmutableArgs for address;

  address public constant cooldownImpl = 0xe0C4a2B14F0ACd936226A598BE6BfeD190E098d1;
  event NewCooldownRequestContract(address indexed contractAddress, address indexed user, uint256 susdeAmount);

  function _additionalInit() internal override {
    unlentPerc = 0;
  }

  /// @notice method used to deposit `token` and mint tranche tokens
  /// @dev deposit underlyings to strategy immediately
  /// @return _minted number of tranche tokens minted
  function _deposit(
    uint256 _amount,
    address _tranche,
    address _referral
  ) internal override whenNotPaused returns (uint256 _minted) {
    _minted = super._deposit(_amount, _tranche, _referral);
    IIdleCDOStrategy(strategy).deposit(_amount);
  }

  /// @notice It allows users to burn their tranche token and redeem their principal + interest back
  /// @dev automatically reverts on lending provider default (_strategyPrice decreased).
  /// @param _amount in tranche tokens
  /// @param _tranche tranche address
  /// @return toRedeem number of underlyings redeemed
  function _withdraw(uint256 _amount, address _tranche) override internal nonReentrant returns (uint256 toRedeem) {
    // if no cooldown is set we can use the normal path
    // if (IStakedUSDeV2(strategyToken).cooldownDuration() == 0) {
    //   return super._withdraw(_amount, _tranche);
    // }
    require(IStakedUSDeV2(strategyToken).cooldownDuration() != 0, '9');
    // we send susde to a contract, one for each cooldown request,
    // created on the fly for the user as multiple cooldowns cannot be managed 
    // by the same contract

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
    require(_amount != 0, '0');
    // Calculate the amount of USDe that the user can redeem
    toRedeem = _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    // Get amount of SUSDe
    uint256 SUSDeRedeemed = toRedeem * ONE_TRANCHE_TOKEN / _strategyPrice();

    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= toRedeem;
    } else {
      lastNAVBB -= toRedeem;
    }

    // update trancheAPRSplitRatio
    _updateSplitRatio(_getAARatio(true));

    // Create a contract for this cooldown request, passing address(this) and msg.sender as args
    EthenaCooldownRequest clone = EthenaCooldownRequest(cooldownImpl.clone(
      abi.encodePacked(address(this), msg.sender), 
      msg.value
    ));
    // Send requested SUSDe to the new contract
    IERC20Detailed(strategyToken).safeTransfer(address(clone), SUSDeRedeemed);
    // Start the cooldown
    clone.startCooldown();
    // emit event for the client to be aware of the new contract address
    emit NewCooldownRequestContract(address(clone), msg.sender, SUSDeRedeemed);
  }
}
