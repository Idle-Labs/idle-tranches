pragma solidity 0.8.10;

interface PriceOracle {
  function getUnderlyingPrice(address _idleToken) external view returns (uint256);
  function getPriceUSD(address _asset) external view returns (uint256 price);
  function getPriceETH(address _asset) external view returns (uint256 price);
  function getPriceToken(address _asset, address _token) external view returns (uint256 price);
  function WETH() external view returns (address);

  function getCompApr(address cToken, address token) external view returns (uint256);
  function getStkAaveApr(address aToken, address token) external view returns (uint256);
}
