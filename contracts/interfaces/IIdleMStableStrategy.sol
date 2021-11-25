// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./IIdleCDOStrategy.sol";

interface IIdleMStableStrategy is IIdleCDOStrategy {
    function transferShares(
        address _to,
        uint256 _interestTokens,
        uint256 _govShares
    ) external;
}
