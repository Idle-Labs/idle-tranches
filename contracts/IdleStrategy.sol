// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IIdleToken.sol";
import "./interfaces/IIdleTokenHelper.sol";
import "./interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract IdleStrategy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy {
  using AddressUpgradeable for address payable;
  using SafeERC20Upgradeable for IERC20Detailed;

  address public override strategyToken;
  address public override token;
  uint256 public override oneToken;
  uint256 public override tokenDecimals;

  IERC20Detailed public underlyingToken;
  IIdleToken public idleToken;

  function initialize(address _idleToken) public initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    strategyToken = _idleToken;
    token = IIdleToken(_idleToken).token();
    tokenDecimals = IERC20Detailed(token).decimals();
    oneToken = 10**(tokenDecimals);
    idleToken = IIdleToken(_idleToken);
    underlyingToken = IERC20Detailed(token);
    underlyingToken.safeApprove(_idleToken, type(uint256).max);
  }

  function deposit(uint256 _amount) external override returns(uint256 minted) {
    require(msg.sender == address(idleToken), '!AUTH');
    IIdleToken _idleToken = idleToken;
    underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
    minted = _idleToken.mintIdleToken(_amount, true, address(0));
    _idleToken.transfer(msg.sender, minted);
  }

  function redeem(uint256 _amount) public override returns(uint256) {
    require(msg.sender == address(idleToken), '!AUTH');
    return _redeem(_amount);
  }

  function redeemUnderlying(uint256 _amount) external override returns(uint256) {
    require(msg.sender == address(idleToken), '!AUTH');
    // we are getting price before transferring so price of msg.sender
    return redeem(_amount * oneToken / price(msg.sender));
  }

  // internals
  function _withdrawGovToken(address _to) internal {
    address[] memory _govTokens = idleToken.getGovTokens();

    for (uint256 i = 0; i < _govTokens.length; i++) {
      IERC20Detailed govToken = IERC20Detailed(_govTokens[i]);
      govToken.safeTransfer(_to, govToken.balanceOf(address(this)));
    }
  }

  function _redeem(uint256 _amount) internal returns(uint256 redeemed) {
    IIdleToken _idleToken = idleToken;
    _idleToken.transferFrom(msg.sender, address(this), _amount);
    redeemed = _idleToken.redeemIdleToken(_amount);
    underlyingToken.safeTransfer(msg.sender, redeemed);
    _withdrawGovToken(msg.sender);
  }

  // views
  function price() public override view returns(uint256) {
    return idleToken.tokenPriceWithFee(msg.sender);
  }

  function price(address _user) public override view returns(uint256) {
    return idleToken.tokenPriceWithFee(_user);
  }

  function getApr() external override view returns(uint256) {
    return idleToken.getAvgAPR();
  }

  function getRewardTokens() external override view returns(address[] memory tokens) {
    return idleToken.getGovTokens();
  }

  // onlyOwner
  // This contract should not have funds at the end of each tx
  // Emergency methods
  function transferToken(address _token, uint256 value, address _to) external onlyOwner nonReentrant returns (bool) {
    require(_token != address(0), 'Address is 0');
    IERC20Detailed(_token).safeTransfer(_to, value);
    return true;
  }

  function transferETH(uint256 value, address payable _to) onlyOwner nonReentrant external {
    _to.sendValue(value);
  }
}
