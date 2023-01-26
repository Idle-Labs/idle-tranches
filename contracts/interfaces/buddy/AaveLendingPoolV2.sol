pragma solidity 0.8.10;

import './DataTypes.sol';

interface AaveLendingPoolV2 {
  function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
  function withdraw(address asset, uint256 amount, address to) external;
  function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);
}
