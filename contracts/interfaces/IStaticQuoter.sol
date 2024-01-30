// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/// @notice UniV3 static quoter
/// https://github.com/eden-network/uniswap-v3-static-quoter/blob/master/contracts/UniV3Quoter/UniswapV3StaticQuoter.sol
interface IStaticQuoter {
  function quoteExactInput(bytes memory path, uint256 amountIn)
    external
    view
    returns (uint256 amountOut);
}
