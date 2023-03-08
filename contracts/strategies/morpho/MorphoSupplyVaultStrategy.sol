// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/morpho/IMorphoSupplyVault.sol";
import "../../interfaces/morpho/IMorphoAaveV2Lens.sol";
import "../../interfaces/morpho/IMorphoCompoundLens.sol";
import "../../interfaces/morpho/IRewardsDistributor.sol";
import "../ERC4626Strategy.sol";

abstract contract MorphoSupplyVaultStrategy is ERC4626Strategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    //// @notice MORPHO governance token
    IERC20Detailed internal constant MORPHO = IERC20Detailed(0x9994E35Db50125E0DF82e4c2dde62496CE330999);

    /// @notice address of the Morpho Aave V2 Lens
    IMorphoAaveV2Lens public AAVE_LENS;
    /// @notice address of the Morpho Compound Lens
    IMorphoCompoundLens public COMPOUND_LENS;

    /// @notice pool token address (e.g. aDAI, cDAI)
    address public poolToken;

    /// @notice reward token address (e.g. COMP)
    address public rewardToken;

    /// @notice MORPHO reward distributor
    IRewardsDistributor public distributor;

    function initialize(
        address _strategyToken,
        address _token,
        address _owner,
        address _poolToken,
        address _rewardToken,
        address _distributor
    ) public {
        AAVE_LENS = IMorphoAaveV2Lens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);
        COMPOUND_LENS = IMorphoCompoundLens(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67);
        _initialize(_strategyToken, _token, _owner);
        poolToken = _poolToken;
        rewardToken = _rewardToken;
        distributor = IRewardsDistributor(_distributor);
    }

    /// @notice redeem the rewards
    /// @return rewards amount of reward that is deposited to the ` strategy`
    function redeemRewards(bytes calldata data)
        public
        virtual
        override
        onlyIdleCDO
        nonReentrant
        returns (uint256[] memory rewards)
    {
        rewards = new uint256[](rewardToken != address(0) ? 2 : 1);

        if (address(distributor) != address(0) && data.length != 0) {
            (uint256 claimable, bytes32[] memory proof) = abi.decode(data, (uint256, bytes32[]));
            // claim MORPHO rewards
            rewards[0] = _claimMorpho(claimable, proof); // index 0 is always MORPHO
            // transfer MORPHO to idleCDO
            MORPHO.safeTransfer(idleCDO, rewards[0]);
        }
    }

    function getRewardTokens() external view returns (address[] memory rewards) {
        address _rewardToken = rewardToken;

        if (_rewardToken != address(0)) {
            rewards = new address[](2);
            rewards[0] = address(MORPHO);
            rewards[1] = _rewardToken;
        } else {
            rewards = new address[](1);
            rewards[0] = address(MORPHO);
        }
    }

    /// @dev set to address(0) to skip `redeemRewards`
    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }

    function _claimMorpho(uint256 claimable, bytes32[] memory proof) internal returns (uint256 claimed) {
        // claim MORPHO by verifying a merkle root
        distributor.claim(address(this), claimable, proof);
        claimed = MORPHO.balanceOf(address(this));
    }
}
