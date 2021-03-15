// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.6;

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IIdleTokenV3_1.sol";
import "./interfaces/IIdleTokenHelper.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract IdleStrategy is IIdleCDOStrategy, Ownable, ReentrancyGuard {
  using Address for address payable;
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public governanceRecoveryFund;
  address public override strategyToken;
  address public override token;
  uint256 public override oneToken;
  uint256 public override tokenDecimals;

  IERC20 public underlyingToken;
  IIdleTokenV3_1 public idleToken;
  IIdleTokenHelper public idleTokenHelper;

  constructor(address _idleToken, address _governanceRecoveryFund) {
    strategyToken = _idleToken;
    governanceRecoveryFund = _governanceRecoveryFund;
    token = IIdleTokenV3_1(_idleToken).token();
    tokenDecimals = ERC20(token).decimals();
    oneToken = 10**(tokenDecimals);
    idleToken = IIdleTokenV3_1(_idleToken);
    underlyingToken = IERC20(token);
    idleTokenHelper = IIdleTokenHelper(address(0x04Ce60ed10F6D2CfF3AA015fc7b950D13c113be5));
    underlyingToken.safeApprove(_idleToken, uint256(-1));
  }

  function priceRedeem() public override view returns(uint256) {
    return idleTokenHelper.getRedeemPrice(address(idleToken));
  }

  function priceMint() public override view returns(uint256) {
    return idleToken.tokenPrice();
  }

  function getApr() external override view returns(uint256) {
    return idleToken.getAvgAPR();
  }

  function deposit(uint256 _amount) external override returns(uint256 minted) {
    underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
    minted = idleToken.mintIdleToken(_amount, true, address(0));
    idleToken.transfer(msg.sender, minted);
  }

  function redeem(uint256 _amount) public override returns(uint256 redeemed) {
    idleToken.transferFrom(msg.sender, address(this), _amount);
    redeemed = idleToken.redeemIdleToken(_amount);
    underlyingToken.safeTransfer(msg.sender, redeemed);
    _withdrawGovToken(msg.sender);
  }

  function redeemUnderlying(uint256 _amount) external override returns(uint256) {
    return redeem(_amount.mul(oneToken).div(priceRedeem()));
  }

  function _withdrawGovToken(address _to) internal {
    uint256[] memory amounts = idleToken.getGovTokensAmounts(address(0));

    for (uint256 i = 0; i < amounts.length; i++) {
      IERC20 govToken = IERC20(idleToken.govTokens(i));
      govToken.safeTransfer(_to, govToken.balanceOf(address(this)));
    }
  }

  function getRewardTokens() external override view returns(address[] memory tokens) {
    uint256[] memory amounts = idleToken.getGovTokensAmounts(address(0));
    tokens = new address[](amounts.length);

    for (uint256 i = 0; i < amounts.length; i++) {
      tokens[i] = idleToken.govTokens(i);
    }
  }

  // Emergency methods, funds gets transferred to the governanceRecoveryFund address
  function transferToken(address _token, uint256 value) external onlyOwner nonReentrant returns (bool) {
    require(_token != address(0), 'Address is 0');
    IERC20(_token).safeTransfer(governanceRecoveryFund, value);
    return true;
  }

  function transferETH(uint256 value) onlyOwner nonReentrant external {
    address payable to = payable(governanceRecoveryFund);
    to.sendValue(value);
  }
}
