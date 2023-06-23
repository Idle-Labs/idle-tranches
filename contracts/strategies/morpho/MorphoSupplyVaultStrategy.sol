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
        address _rewardToken = rewardToken;
        rewards = new uint256[](_rewardToken != address(0) ? 2 : 1); // MORPHO + rewardToken

        // claim MORPHO rewards
        if (address(distributor) != address(0) && data.length != 0) {
            (address account, uint256 claimable, bytes32[] memory proof) = abi.decode(
                data,
                (address, uint256, bytes32[])
            );
            // NOTE: MORPHO is not transferable atm
            rewards[0] = _claimMorpho(account, claimable, proof); // index 0 is always MORPHO
        }

        // claim rewards (e.g. COMP)
        // if rewardToken is not set, skip redeeming rewards
        if (_rewardToken != address(0)) {
            // claim rewards instead of the idleCDO
            uint256 reward = IMorphoSupplyVault(strategyToken).claimRewards(address(idleCDO));
            rewards[1] = reward;
        }
    }

    function getRewardTokens() external override view returns (address[] memory rewards) {
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

    /// @notice transfer MORPHO to the idleCDO
    /// @dev Anyone can call this function
    function transferMorpho() public {
        uint256 bal = MORPHO.balanceOf(address(this));
        MORPHO.safeTransfer(address(idleCDO), bal);
    }

    /// @dev set to address(0) to skip `redeemRewards`
    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }

    /// @notice claim MORPHO by verifying a merkle root
    /// @param account account to claim MORPHO for
    /// @param claimable amount of MORPHO to claim
    function _claimMorpho(
        address account,
        uint256 claimable,
        bytes32[] memory proof
    ) internal returns (uint256 claimed) {
        uint256 balBefore = MORPHO.balanceOf(address(account));
        distributor.claim(account, claimable, proof);
        claimed = MORPHO.balanceOf(address(account)) - balBefore;
    }
}
