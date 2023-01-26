// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;
import {Types} from "./libraries/Types.sol";

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
    function getNextUserSupplyRatePerYear(
        address _poolToken,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextSupplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );
    function getIndexes(address _poolToken) external view returns (Types.Indexes memory indexes);
}

