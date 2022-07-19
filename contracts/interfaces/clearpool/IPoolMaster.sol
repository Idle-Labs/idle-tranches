// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IPoolFactory.sol";

interface IPoolMaster {
    function factory() external view returns (IPoolFactory);

    function provide(uint256 currencyAmount) external;

    function redeem(uint256 tokens) external;

    function getSupplyRate() external view returns (uint256);

    function getCurrentExchangeRate() external view returns (uint256);

    function rewardPerSecond() external view returns (uint256);
}
