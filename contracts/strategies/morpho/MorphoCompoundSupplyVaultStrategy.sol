// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";
import "../../interfaces/morpho/IMorphoCompoundLens.sol";

contract MorphoCompoundSupplyVaultStrategy is MorphoSupplyVaultStrategy {
    /// @notice address of the MorphoSupplyVault
    IMorphoCompoundLens public LENS = IMorphoCompoundLens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);

    function getApr() external view override returns (uint256 apr) {
        //  The market's average supply rate per block (in wad).
        (apr, , ) = LENS.getAverageSupplyRatePerBlock(poolToken);
    }
}
