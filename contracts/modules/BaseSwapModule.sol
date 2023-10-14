// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

abstract contract BaseSwapModule {
    function _swapForAsset(address _token, uint256 _amountIn) internal virtual returns (uint256 _amountOut);
}
