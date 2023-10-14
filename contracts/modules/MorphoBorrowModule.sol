// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "./BaseBorrowModule.sol";

import "../interfaces/morpho/IMorpho.sol";

contract MorphoBorrowModule is BaseBorrowModule {
    address internal constant MORPHO = 0x8888882f8f843896699869179fB6E4f7e3B58888;

    function _borrowAsset(address _token, uint256 _debts) internal virtual override returns (uint256) {
        IMorpho(MORPHO).borrow(_token, _debts);
        return _debts;
    }

    function _repayAsset(address _token, uint256 _debts) internal virtual override returns (uint256) {
        IMorpho(MORPHO).borrow(_token, _debts);
        return _debts;
    }
}
