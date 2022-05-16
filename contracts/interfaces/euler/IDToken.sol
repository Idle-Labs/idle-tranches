// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IDToken is IERC20 {
      function name() external view returns(string memory);
  function symbol() external view returns(string memory);
  function decimals() external view returns(uint256);
}