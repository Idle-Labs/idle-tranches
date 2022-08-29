// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./IdleCDO.sol";

/// @title IdleCDO variant for Euler Levereged strategy. 
/// @author Idle DAO, @bugduino
/// @dev In this variant the `_checkDefault` calculates if strategy price decreased 
/// more than X% with X configurable
contract IdleCDOLeveregedEulerVariant is IdleCDO {
  using SafeERC20Upgradeable for IERC20Detailed;

  uint256 public maxDecreaseDefault;

  /// @dev check if any loan for the pool is defaulted
  function _checkDefault() override internal view {
    uint256 _lastPrice = lastStrategyPrice;

    // calculate max % decrease
    if (!skipDefaultCheck) {
      require(_lastPrice - (_lastPrice * maxDecreaseDefault / FULL_ALLOC) <= _strategyPrice(), "4");
    }
  }

  /// @notice set the max value, in % where `100000` = 100%, of accettable price decrease for the strategy
  /// @dev automatically reverts if strategyPrice decreased more than `_maxDecreaseDefault`
  /// @param _maxDecreaseDefault in tranche tokens
  function setMaxDecreaseDefault(uint256 _maxDecreaseDefault) external {
    _checkOnlyOwner();
    require(_maxDecreaseDefault < FULL_ALLOC);
    maxDecreaseDefault = _maxDecreaseDefault;
  }
}
