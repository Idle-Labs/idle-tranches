// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface ICurveDeposit_4token {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[4] calldata amounts, uint256 min_mint_amount)
        external;

    function remove_liquidity_imbalance(
        uint256[4] calldata amounts,
        uint256 max_burn_amount
    ) external;

    function remove_liquidity(uint256 _amount, uint256[4] calldata amounts)
        external;

    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external;

    function calc_token_amount(uint256[4] calldata amounts, bool deposit)
        external
        view
        returns (uint256);
}
