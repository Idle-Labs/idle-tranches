// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IAlgebraQuoter {
  function quoteExactInput(bytes memory path, uint amountIn) external returns (uint amountOut, uint16[] memory fees);
}