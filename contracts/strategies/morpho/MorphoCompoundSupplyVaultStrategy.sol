// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";
import "../../interfaces/morpho/IMorphoCompoundLens.sol";

contract MorphoCompoundSupplyVaultStrategy is MorphoSupplyVaultStrategy {
    /// @notice average number of blocks per year
    /// average block time is 12.06 secs after the merge
    uint256 public constant NBLOCKS_PER_YEAR = 2614925; // 24*365*3600 / 12.06
    /// @notice address of the MorphoSupplyVault
    IMorphoCompoundLens public COMPOUND_LENS = IMorphoCompoundLens(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67);

    function getApr() external view override returns (uint256 apr) {
        //  The market's average supply rate per block (in wad).
        (uint256 ratePerBlock, , ) = COMPOUND_LENS.getAverageSupplyRatePerBlock(poolToken);
        return ratePerBlock * NBLOCKS_PER_YEAR * 100;
    }
}
