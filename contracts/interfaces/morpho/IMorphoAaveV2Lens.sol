// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IMorphoAaveV2Lens {
    // https://developers.morpho.xyz/lens#getaveragesupplyrateperblock
    function getAverageSupplyRatePerYear(address _poolToken)
        external
        view
        returns (
            uint256 avgSupplyRatePerYear,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        );

    function getCurrentUserSupplyRatePerYear(address _poolToken, address _user) external view returns (uint256);

    function getRatesPerYear(address _poolToken)
        external
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        );
}
