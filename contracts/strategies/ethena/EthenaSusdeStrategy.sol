// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../ERC4626Strategy.sol";

contract EthenaSusdeStrategy is ERC4626Strategy {
  function initialize(address _vault, address _underlying, address _owner) public {
    _initialize(_vault, _underlying, _owner);
  }

  // @notice apr is calculated in the client directly for this strategy
  // so we return 0 here
  function getApr() external pure override returns (uint256) {}
}