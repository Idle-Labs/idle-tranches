// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "./IERC20Detailed.sol";

interface IERC20Nonces is IERC20Detailed {
  function nonces(address holder) external view returns(uint);
}

interface IERC20Permit is IERC20Nonces {
  function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                  bool allowed, uint8 v, bytes32 r, bytes32 s) external;

  function permit(address holder, address spender, uint256 value, uint256 expiry,
                  uint8 v, bytes32 r, bytes32 s) external;
}
