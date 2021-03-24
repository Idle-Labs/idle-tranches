//SPDX-License-Identifier: Apache 2.0
pragma solidity 0.8.3;

// Helper contract used to avoid the call of 2 specific methods in the same tx,
// eg avoid deposit and redeem in the same tx
contract FlashProtection {
  // variable used to save the last tx.origin and block.number
  bytes32 private _lastCallerBlock;

  // Set last caller and block.number hash. This should be called at the beginning of the first function
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  // Check that the second function is not called in the same block from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "SAME_TX");
  }
}
