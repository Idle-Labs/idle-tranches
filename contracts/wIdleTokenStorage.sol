// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract wIdleTokenStorage {
  uint256 public constant FULL_ALLOC = 100000;
  uint256 public constant ONE_18 = 10**18;

  bool public revertIfNeeded;
  bool public skipDefaultCheck;
  address public rebalancer;
  address public token;
  address public weth;
  address public idle;
  address public idleToken;
  uint256 public oneToken;
  uint256 public lastPrice;
  uint256 public contractAvgPrice;
  uint256 public contractDepositedTokens;
  IUniswapV2Router02 internal uniswapRouterV2;

  // variable used to save the last tx.origin and block.number
  bytes32 internal _lastCallerBlock;
}
