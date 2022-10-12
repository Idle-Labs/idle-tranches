// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../ERC4626Strategy.sol";
import "../../interfaces/morpho/IMorphoAaveV2Lens.sol";
import "../../interfaces/morpho/IMorpho.sol";

contract MorphoAaveV2SupplyVaultStrategy is ERC4626Strategy {
    /// @notice address of the MorphoSupplyVault
    IMorphoAaveV2Lens public MORPHO_LENS = IMorphoAaveV2Lens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);
    /// @notice aToken address
    address public aToken;
    /// @dev set to address(0) to skip `redeemRewards`
    address public morpho;

    function initialize(
        string memory _name,
        string memory _symbol,
        address _strategyToken,
        address _token,
        address _owner,
        address _aToken,
        address _morpho
    ) public initializer {
        _initialize(_name, _symbol, _strategyToken, _token, _owner);
        aToken = _aToken;
        morpho = _morpho; // set to address(0) to skip `redeemRewards`
    }

    function getApr() external view override returns (uint256 apr) {
        (apr, , ) = MORPHO_LENS.getAverageSupplyRatePerYear(aToken);
    }

    /// @notice redeem the rewards
    /// @return rewards amount of reward that is deposited to the ` strategy`
    function redeemRewards(bytes calldata) public override onlyIdleCDO nonReentrant returns (uint256[] memory rewards) {
        if (morpho == address(0)) {
            return rewards;
        }
        rewards = new uint256[](1);
        address[] memory tokens = new address[](1);
        tokens[0] = aToken;
        IMorpho(morpho).claimRewards(tokens, false);
    }

    function getRewardTokens() external view returns (address[] memory rewards) {}

    /// @dev set to address(0) to skip `redeemRewards`
    function setMorpho(address _morpho) external onlyOwner {
        morpho = _morpho;
    }
}
