pragma solidity 0.8.10;

interface WhitePaperInterestRateModel {
  function getBorrowRate(uint256 cash, uint256 borrows, uint256 _reserves) external view returns (uint256, uint256);
  function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa) external view returns (uint256);
  function multiplier() external view returns (uint256);
  function baseRate() external view returns (uint256);
  function blocksPerYear() external view returns (uint256);
  function dsrPerBlock() external view returns (uint256);
}
