// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";
import "../../interfaces/morpho/IMorphoCompoundLens.sol";

contract MorphoCompoundSupplyVaultStrategy is MorphoSupplyVaultStrategy {
    uint256 public constant NBLOCKS_PER_YEAR = 2614925;
    /// @notice address of the MorphoSupplyVault
    IMorphoCompoundLens public COMPOUND_LENS = IMorphoCompoundLens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);

    function getApr() external view override returns (uint256 apr) {
        //  The market's average supply rate per block (in wad).
        (uint256 ratePerBlock, , ) = COMPOUND_LENS.getAverageSupplyRatePerBlock(poolToken);
        return ratePerBlock * NBLOCKS_PER_YEAR * 100;
    }
}
