// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IERC20Detailed.sol";
import "../interfaces//morpho/IRewardsDistributor.sol";

contract MockRewardsDistributor is IRewardsDistributor {
    address internal constant MORPHO = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;

    function updateRoot(bytes32 _newRoot) external {}

    function withdrawMorphoTokens(address _to, uint256 _amount) external {}

    function claim(
        address _account,
        uint256 _claimable,
        bytes32[] calldata /* _proof */
    ) external {
        IERC20Detailed(MORPHO).transfer(_account, _claimable);
    }
}
