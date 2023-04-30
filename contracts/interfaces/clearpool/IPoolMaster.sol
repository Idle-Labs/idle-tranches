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
    function interestRateModel() external view returns (address);
    function borrows() external view returns (uint256);
    function reserves() external view returns (uint256);
    function insurance() external view returns (uint256);
    function principal() external view returns (uint256);
    function reserveFactor() external view returns (uint256);
    function insuranceFactor() external view returns (uint256);
    function availableToWithdraw() external view returns (uint256);
    function getUtilizationRate() external view returns (uint256);
    function cash() external view returns (uint256);
    function interest() external view returns (uint256);
}
