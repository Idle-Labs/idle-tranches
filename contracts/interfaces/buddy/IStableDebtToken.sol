pragma solidity 0.8.10;

interface IStableDebtToken {
  function getTotalSupplyAndAvgRate() external view returns (uint256, uint256);
}
