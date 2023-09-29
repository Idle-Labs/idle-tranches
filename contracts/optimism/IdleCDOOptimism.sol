// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IERC20Detailed.sol";
import "../IdleCDO.sol";

/// @title A perpetual tranche implementation, deployed on Optimism
/// @author Idle Labs Inc.
/// @notice More info and high level overview in the README
/// @dev The contract is upgradable, to add storage slots, create IdleCDOStorageVX and inherit from IdleCDOStorage, then update the definitaion below
contract IdleCDOOptimism is IdleCDO {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice used by child contracts (cdo variants) if anything needs to be done on/after init
  function _additionalInit() internal override {
    weth = address(0x4200000000000000000000000000000000000006);
    feeReceiver = address(0xFDbB4d606C199F091143BD604C85c191a526fbd0); // treasury multisig
    releaseBlocksPeriod = 302400; // 60 * 60 * 24 / 2 * 7 = ~1 week (blocktime 2s)
  }

  /// @notice method used to sell `_rewardToken` for `_token` on uniswap
  /// @param _rewardToken address of the token to sell
  /// @param _path to buy
  /// @param _amount of `_rewardToken` to sell
  /// @param _minAmount min amount of `_token` to buy
  /// @return _amount of _rewardToken sold
  /// @return _amount received for the sell
  function _sellReward(address _rewardToken, bytes memory _path, uint256 _amount, uint256 _minAmount)
    internal override
    returns (uint256, uint256) {
    // If 0 is passed as sell amount, we get the whole contract balance
    if (_amount == 0) {
      _amount = _contractTokenBalance(_rewardToken);
    }
    if (_amount == 0) {
      return (0, 0);
    }
  
    // Uni v3 swap
    ISwapRouter _swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20Detailed(_rewardToken).safeIncreaseAllowance(address(_swapRouter), _amount);
    // multi hop swap params
    ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
      path: _path,
      recipient: address(this),
      deadline: block.timestamp + 100,
      amountIn: _amount,
      amountOutMinimum: _minAmount
    });
    // do the swap and return the amount swapped and the amount received
    return (_amount, _swapRouter.exactInput(params));
  }
}
