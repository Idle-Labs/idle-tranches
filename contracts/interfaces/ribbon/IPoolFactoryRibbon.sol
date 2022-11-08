// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IPoolFactoryRibbon {
    function rbn() external view returns (address);

    function withdrawReward(address[] memory pools) external;
}
