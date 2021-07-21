// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "../IdleCDO.sol";

contract EnhancedIdleCDO is IdleCDO {
  function setUniRouterForTest(address a) external {
    uniswapRouterV2 = IUniswapV2Router02(a);
  }
  function setWethForTest(address a) external {
    weth = a;
  }
}
