
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../ERC4626Strategy.sol";

contract FraxLSD is ERC4626Strategy {
    /// @notice reward token address. No rewards here
    /// @dev set to address(0) to skip `redeemRewards`
    address public rewardToken;

    function initialize(
        address _strategyToken,
        address _token,
        address _owner
    ) public {
        _initialize(_strategyToken, _token, _owner);
    }

    function getApr() external view override returns (uint256 apr) {
      // TODO
    }
}
