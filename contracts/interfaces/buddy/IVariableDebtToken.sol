pragma solidity 0.8.10;

interface IVariableDebtToken {
  function scaledTotalSupply() external view returns (uint256);
}
