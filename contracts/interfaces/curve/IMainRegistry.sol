// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IMainRegistry {
    function get_pool_from_lp_token(address lp_token)
        external
        returns (address);
}
