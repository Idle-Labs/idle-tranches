// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./MorphoSupplyVaultStrategy.sol";

contract MorphoCompoundSupplyVaultStrategy is MorphoSupplyVaultStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice average number of blocks per year
    /// average block time is 12.06 secs after the merge
    uint256 public constant NBLOCKS_PER_YEAR = 2614925; // 24*365*3600 / 12.06

    function redeemRewards(bytes calldata data)
        public
        override
        onlyIdleCDO
        nonReentrant
        returns (uint256[] memory rewards)
    {
        address _rewardToken = rewardToken;

        rewards = new uint256[](_rewardToken != address(0) ? 2 : 1);

        // claim MORPHO rewards
        if (address(distributor) != address(0) && data.length != 0) {
            (uint256 claimable, bytes32[] memory proof) = abi.decode(data, (uint256, bytes32[]));

            uint256 claimed = _claimMorpho(claimable, proof);
            rewards[0] = claimed;

            // transfer MORPHO to idleCDO
            MORPHO.safeTransfer(idleCDO, claimed);
        }

        // claim rewards (e.g. COMP)
        // if rewardToken is not set, skip redeeming rewards
        if (_rewardToken != address(0)) {
            uint256 reward = IMorphoSupplyVault(strategyToken).claimRewards(address(this));
            rewards[1] = reward;
            // send rewards to the idleCDO
            IERC20Detailed(_rewardToken).safeTransfer(idleCDO, reward);
        }
    }

    function getApr() external view override returns (uint256 apr) {
        //  The market's average supply rate per block (in wad).
        (uint256 ratePerBlock, , ) = COMPOUND_LENS.getAverageSupplyRatePerBlock(poolToken);
        return ratePerBlock * NBLOCKS_PER_YEAR * 100;
    }
}
