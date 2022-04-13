// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;
import "../../../interfaces/IVault.sol";

interface IVaultPolygon is IVault {
    function balanceOf(address _user) external view returns (uint256);

    function earned(address _account) external view returns (uint256, uint256);

    function claimReward() external;
}
