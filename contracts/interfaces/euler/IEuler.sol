// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IEuler {
    function moduleIdToImplementation(uint moduleId) external view returns (address);
    function moduleIdToProxy(uint moduleId) external view returns (address);
}