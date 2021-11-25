// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

interface IVault {
    function stake(uint256 _amount) external;

    function stake(address _beneficiary, uint256 _amount) external;

    function exit() external;

    function exit(uint256 _first, uint256 _last) external;

    function rawBalanceOf(address _account) external view returns (uint256);
}
