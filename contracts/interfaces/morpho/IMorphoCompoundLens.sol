// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IMorphoCompoundLens {
    /// @notice Computes and returns the current supply rate per block experienced on average on a given market.
    /// @param _poolToken The market address.
    /// @return avgSupplyRatePerBlock The market's average supply rate per block (in wad).
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getAverageSupplyRatePerBlock(address _poolToken)
        external
        view
        returns (
            uint256 avgSupplyRatePerBlock,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        );

    function getUserHealthFactor(address _user, address[] calldata _updatedMarkets) external view returns (uint256);

    function getCurrentSupplyBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );

    function getCurrentBorrowBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );
}
