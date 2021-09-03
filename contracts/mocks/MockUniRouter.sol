// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniRouter {
  function swapExactTokensForTokens(
    uint256 _amount,
    uint256 amountOutMin,
    address[] calldata path,
    address,
    uint256
  ) external returns (uint256[] memory amounts) {
    IERC20(path[0]).transferFrom(msg.sender, address(this), _amount);
    amounts = new uint256[](3);
    amounts[0] = _amount;
    for (uint256 i = 0; i < path.length; i++) {
      if (i == amounts.length - 1) {
        // set last element of the array (last) the
        amounts[i] = amountOutMin;
      }
    }
    IERC20(path[2]).transfer(msg.sender, amountOutMin);
  }
}
