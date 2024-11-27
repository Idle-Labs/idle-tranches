// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../../strategies/ERC4626Strategy.sol";
import "../../interfaces/truefi/ITruefiCreditLine.sol";

contract TruefiCreditLineStrategy is ERC4626Strategy {
  uint256 public constant BASIS_PRECISION = 10000;
  uint256 public constant ONE = 1e18;

  function initialize(address _vault, address _underlying, address _owner) public {
    _initialize(_vault, _underlying, _owner);
  }

  // @notice apr is multiplied by 1e18 so to have 1% == 1e18
  function getApr() external view override returns (uint256) {
    ITruefiCreditLine _tf = ITruefiCreditLine(strategyToken);
    return _tf.interestRate() * _tf.utilization() * ONE / (BASIS_PRECISION * 100);
  }
}
