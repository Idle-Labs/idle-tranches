// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../ERC4626Strategy.sol";
import "../../interfaces/morpho/IMorphoAaveV2Lens.sol";

contract MorphoAaveV2SupplyVaultStrategy is ERC4626Strategy {
    /// @notice address of the MorphoSupplyVault
    IMorphoAaveV2Lens public MORPHO_LENS = IMorphoAaveV2Lens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);
    address public aToken;

    function initialize(
        string memory _name,
        string memory _symbol,
        address _strategyToken,
        address _token,
        address _owner,
        address _aToken
    ) public initializer {
        _initialize(_name, _symbol, _strategyToken, _token, _owner);
        aToken = _aToken;
    }

    function getApr() external view override returns (uint256 apr) {
        (apr, , ) = MORPHO_LENS.getAverageSupplyRatePerYear(aToken);
    }

    function getRewardTokens() external view returns (address[] memory rewards) {}
}
