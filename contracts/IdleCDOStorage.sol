// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract IdleCDOStorage {
  uint256 public constant FULL_ALLOC = 100000;
  uint256 public constant ONE_18 = 10**18;
  // variable used to save the last tx.origin and block.number
  bytes32 internal _lastCallerBlock;

  address public weth;
  address public idle;

  address public token;
  uint256 public oneToken;
  address public rebalancer;
  IUniswapV2Router02 internal uniswapRouterV2;

  bool public allowAAWithdraw;
  bool public allowBBWithdraw;
  bool public revertIfTooLow;
  bool public skipDefaultCheck;

  address public strategy;
  address public AATranche;
  address public BBTranche;
  uint256 public trancheAPRSplitRatio; // 100% => 100000 => 100% apr to tranche AA
  uint256 public trancheIdealWeightRatio; // 100% => 100000 => 100% of tranches are AA
  uint256 public lastStrategyPrice;
  uint256 public lastAAPrice;
  uint256 public lastBBPrice;
}
