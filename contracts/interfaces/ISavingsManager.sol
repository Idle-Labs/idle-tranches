// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface ISavingsManager {
    /** @dev Admin privs */
    function distributeUnallocatedInterest(address _mAsset) external;

    /** @dev Liquidator */
    function depositLiquidation(address _mAsset, uint256 _liquidation) external;

    /** @dev Liquidator */
    function collectAndStreamInterest(address _mAsset) external;

    /** @dev Public privs */
    function collectAndDistributeInterest(address _mAsset) external;

    /** @dev getter for public lastBatchCollected mapping */
    function lastBatchCollected(address _mAsset) external view returns (uint256);
}
