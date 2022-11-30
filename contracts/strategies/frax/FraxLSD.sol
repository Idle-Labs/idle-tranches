
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../ERC4626Strategy.sol";

contract FraxLSD is ERC4626Strategy {
    /// @notice Initialize must be manually called
    function initialize(
        address _strategyToken,
        address _token,
        address _owner
    ) public {
        _initialize(_strategyToken, _token, _owner);
    }
}
