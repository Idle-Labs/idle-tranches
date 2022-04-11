// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ConvexBaseStrategy} from "./ConvexBaseStrategy.sol";
import {IMetaPoolRegistry} from "../../interfaces/curve/IMetaPoolRegistry.sol";

abstract contract ConvexFactoryMetaPoolStrategy is ConvexBaseStrategy {
    /// @notice curve metapool factory
    address public constant METAPOOL_FACTORY =
        address(0xB9fC157394Af804a3578134A6585C0dc9cc990d4);

    /// @dev This method queries the Metapool Factory to get the underlying coins of a
    ///      plain pool created with the factory (no wrapped assets).
    function _curveUnderlyingCoins(address _curveLpToken, uint256 _position)
        internal
        view
        override
        returns (address)
    {
        address[4] memory _coins = IMetaPoolRegistry(METAPOOL_FACTORY).get_underlying_coins(_curveLpToken);
        return _coins[_position];
    }
}