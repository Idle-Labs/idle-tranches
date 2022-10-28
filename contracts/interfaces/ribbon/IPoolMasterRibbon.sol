// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IPoolFactoryRibbon.sol";

interface IPoolMasterRibbon {
    function factory() external view returns (IPoolFactoryRibbon);

    function provide(uint256 currencyAmount, address referral) external;

    function redeem(uint256 tokens) external;

    function getSupplyRate() external view returns (uint256);

    function getCurrentExchangeRate() external view returns (uint256);

    function rewardPerSecond() external view returns (uint256);
}
