// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IMetaPoolRegistry {
    function get_coins(address) external view returns (address[4] memory);
    function get_underlying_coins(address) external view returns(address[4] memory);
}
