// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MockERC20.sol";

contract MockIdleToken is ERC20, MockERC20 {
  address[] public govTokens;
  address public underlying;
  uint256 public apr;
  uint256 public _tokenPriceWithFee;
  uint256 public _redeemTokenPriceWithFee;
  uint256 public govAmount;
  bool public transferGovTokens;

  constructor(address _underlying)
    MockERC20('IDLEDAI', 'IDLEDAI') {
      underlying = _underlying;
      _tokenPriceWithFee = 10**18;
  }

  function setGovTokens(address[] memory _govTokens) external {
    govTokens = _govTokens;
  }
  function setTokenPriceWithFee(uint256 _amount) external {
    _tokenPriceWithFee = _amount;
  }
  function setRedeemTokenPrice(uint256 _amount) external {
    _redeemTokenPriceWithFee = _amount;
  }
  function setApr(uint256 _apr) external {
    apr = _apr;
  }
  function setGovAmount(uint256 _govAmount) external {
    govAmount = _govAmount;
  }

  function getGovTokens() external view returns (address[] memory) {
    return govTokens;
  }
  function getAvgAPR() external view returns (uint256) {
    return apr;
  }
  function tokenPriceWithFee(address) external view returns (uint256) {
    return _tokenPriceWithFee;
  }
  function token() public view returns(address) {
    return underlying;
  }

  function mintIdleToken(uint256 _amount, bool, address) external returns(uint256) {
    IERC20(underlying).transferFrom(msg.sender, address(this), _amount * 10**18 / _tokenPriceWithFee);
    _mint(msg.sender, _amount * 10**18 / _tokenPriceWithFee);
    return _amount * 10**18 / _tokenPriceWithFee;
  }

  function redeemIdleToken(uint256 _amount) external returns(uint256) {
    IERC20(underlying).transfer(msg.sender, _amount * _tokenPriceWithFee / 10**18);
    if (govTokens.length > 0) {
      IERC20(govTokens[0]).transfer(msg.sender, govAmount);
    }
    _burn(msg.sender, _amount);
    return _amount * _tokenPriceWithFee / 10**18;
  }
}
