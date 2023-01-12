// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

abstract contract BaseDepositModule {
    function _depositCollateral(address _token, uint256 _amount) internal virtual returns (uint256 _collateralAdded);
}
