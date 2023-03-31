// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";

contract MorphoAaveV3SupplyVaultStrategy is MorphoSupplyVaultStrategy {
    /// @dev return always a value which is multiplied by 1e18
    function getApr() external view override returns (uint256 apr) {}
}
