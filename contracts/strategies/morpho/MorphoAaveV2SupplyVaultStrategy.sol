// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";
import "../../interfaces/morpho/IMorphoAaveV2Lens.sol";


contract MorphoAaveV2SupplyVaultStrategy is MorphoSupplyVaultStrategy {
    /// @notice address of the MorphoSupplyVault
    IMorphoAaveV2Lens public AAVE_LENS = IMorphoAaveV2Lens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);

    /// @dev return always a value which is multiplied by 1e18
    ///     eg for 2% apr -> 2*1e18
    function getApr() external view override returns (uint256 apr) {
        // The supply rate per year experienced on average on the given market (in WAD).
        (uint256 ratePerYear, , ) = AAVE_LENS.getAverageSupplyRatePerYear(poolToken);
        apr = ratePerYear / 1e7;
    }
}
