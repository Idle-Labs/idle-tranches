// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCreditVaultWriteOffEscrow.sol";

/// @title Avax variant of IdleCreditVaultWriteOffEscrow
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract IdleCreditVaultWriteOffEscrowAvax is IdleCreditVaultWriteOffEscrow {
  /// @notice update avax addresses
  function initialize(address _idleCDOEpoch, address _owner, bool _isAATranche) public override initializer {
    super.initialize(_idleCDOEpoch, _owner, _isAATranche);
    feeReceiver = 0x8b2aAC97A2dEae85dCD506558c1DeE0f2aeC0550; // treasury multisig
  }
}
