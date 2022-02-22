// based on https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code

/**
 *Submitted for verification at Etherscan.io on 2017-12-12
*/

// Copyright (C) 2015, 2016, 2017 Dapphub

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.10;

interface IWETH9 {
    function balanceOf(address target) external view returns (uint256);
    function deposit() external payable ;
    function withdraw(uint wad) external ;
    function totalSupply() external view returns (uint) ;
    function approve(address guy, uint wad) external returns (bool) ;
    function transfer(address dst, uint wad) external returns (bool) ;
    function transferFrom(address src, address dst, uint wad) external returns (bool);

}