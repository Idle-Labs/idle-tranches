// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

abstract contract BaseBorrowModule {
    function _borrowAsset(address _token, uint256 _debt) internal virtual returns (uint256 _debtAdded);

    function _repayAsset(address _token, uint256 _debts) internal virtual returns (uint256);
}
