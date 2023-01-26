// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IBaseIRMLinearKink {
    function kink() external view returns (uint);
    function slope1() external view returns (uint);
    function slope2() external view returns (uint);
    function baseRate() external view returns (uint);
}