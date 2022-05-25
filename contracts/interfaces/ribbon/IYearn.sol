// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IYearnPricer {
    function setExpiryPriceInOracle(uint256 _expiryTimestamp) external;
    function getPrice() external view returns (uint256);
    function underlying() external view returns (address);
}
