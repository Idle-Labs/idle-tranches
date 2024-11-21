// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { TrancheWrapper } from "./TrancheWrapper.sol";
import { IdleCDOEpochVariant } from "./IdleCDOEpochVariant.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

error NotImplemented();

/// @notice wrapper for Tranches of IdleCDOEpochVariant. This contract is NOT ERC4626 compliant
/// as the redeems and withdraws are not implemented. It is however ERC4626 compliant for the deposit
/// and pricing functions.
/// @dev IdleCDOEpochVariant tranches have a 2-step process to withdraw funds, we introduced an 'unwrap' function
/// that allows to convert the 4626 token to the tranche token. Withdrawals should then be done 
/// in the main contract.
contract TrancheEpochSuperformWrapper is TrancheWrapper {
  /// @dev unwrap 4626 to the tranche token
  /// @param _amount amount of 4626 to unwrap
  function unwrap(uint256 _amount) external {
    // burn the 4626 tokens (they are minted 1:1 with the tranche tokens in _deposit)
    _burnFrom(msg.sender, _amount);
    // send the tranche tokens
    ERC20Upgradeable(tranche).transfer(msg.sender, _amount);
  }

  /// @dev check that the depositor and receiver are allowed to interact with the IdleCDOEpochVariant
  function _deposit(
    uint256 amount,
    address receiver,
    address depositor
  ) internal override returns (uint256, uint256) {
    IdleCDOEpochVariant cdoEpoch = IdleCDOEpochVariant(address(idleCDO));
    cdoEpoch.isWalletAllowed(depositor);
    if (receiver != depositor) {
      cdoEpoch.isWalletAllowed(receiver);
    }
    return super._deposit(amount, receiver, depositor);
  }

  // Overrides (reverts for all redeem/mint functions)

  function previewWithdraw(uint256) public override view returns (uint256) {
    revert NotImplemented();
  }
  function previewRedeem(uint256) public override view returns (uint256) {
    revert NotImplemented();
  }
  function withdraw(uint256, address, address) external override returns (uint256) {
    revert NotImplemented();
  }
  function redeem(uint256, address, address) external override returns (uint256) {
    revert NotImplemented();
  }
  function maxWithdraw(address) external override view returns (uint256) {
    revert NotImplemented();
  }
  function maxRedeem(address) external override view returns (uint256) {
    revert NotImplemented();
  }
  function _redeem(uint256, address, address) internal override returns (uint256, uint256) {
    revert NotImplemented();
  }
}