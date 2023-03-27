// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";

contract MorphoCompoundSupplyVaultStrategy is MorphoSupplyVaultStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice average number of blocks per year
    /// average block time is 12.06 secs after the merge
    uint256 public constant NBLOCKS_PER_YEAR = 2614925; // 24*365*3600 / 12.06

    function getApr() external view override returns (uint256 apr) {
        //  The market's average supply rate per block (in wad).
        (uint256 ratePerBlock, , ) = COMPOUND_LENS.getAverageSupplyRatePerBlock(poolToken);
        return ratePerBlock * NBLOCKS_PER_YEAR * 100;
    }
}
