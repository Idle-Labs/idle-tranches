// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function approve(address spender, uint256 amount) external returns (bool);
    
    function transfer(address recipient, uint256 amount) external returns (bool);
    
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
