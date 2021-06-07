// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract IdleCDOStorage {
  uint256 public constant FULL_ALLOC = 100000;
  uint256 public constant MAX_FEE = 20000;
  uint256 public constant ONE_18 = 10**18;
  // variable used to save the last tx.origin and block.number
  bytes32 internal _lastCallerBlock;

  address public weth;
  address public incentiveToken;

  address public token;
  address public guardian;
  uint256 public oneToken;
  address public rebalancer;
  IUniswapV2Router02 internal uniswapRouterV2;

  bool public allowAAWithdraw;
  bool public allowBBWithdraw;
  bool public revertIfTooLow;
  bool public skipDefaultCheck;

  address public strategy;
  address public strategyToken;
  address public AATranche;
  address public BBTranche;
  uint256 public trancheAPRSplitRatio; // 100% => 100000 => 100% apr to tranche AA
  uint256 public trancheIdealWeightRatio; // 100% => 100000 => 100% of tranches are AA
  uint256 public idealRange; // trancheIdealWeightRatio ± idealRanges, used in updateIncentives
  uint256 public priceAA;
  uint256 public priceBB;
  uint256 public lastNAVAA;
  uint256 public lastNAVBB;
  uint256 public lastStrategyPrice;
  uint256 public lastAAPrice;
  uint256 public lastBBPrice;

  uint256 public fee;
  address public feeReceiver;

  // event MintAA(address usr, address amount);
  // event MintBB(address usr, address amount);
  // event WithdrawAA(address usr, address amount);
  // event WithdrawBB(address usr, address amount);
  event FeeDeposit(address fees, address to);
}
