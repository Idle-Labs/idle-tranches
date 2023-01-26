pragma solidity 0.8.10;

interface AaveLendingPoolProviderV2 {
  function getLendingPool() external view returns (address);
}
