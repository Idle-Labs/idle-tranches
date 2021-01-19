// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.6;

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IIdleTokenV3_1.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IdleStrategy is IIdleCDOStrategy, Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public override strategyToken;
  address public override token;
  uint256 public override oneToken;
  uint256 public override tokenDecimals;

  constructor(address _idleToken) {
    strategyToken = _idleToken;
    token = IIdleTokenV3_1(_idleToken).token();
    tokenDecimals = ERC20(token).decimals();
    oneToken = 10**(tokenDecimals);
    IERC20(token).safeApprove(_idleToken, uint256(-1));
  }

  function price() public override view returns(uint256) {
    // todo use emilianos virtual price implementation?
  }

  function deposit(uint256 _amount) external override returns(uint256 minted) {
    IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
    minted = IIdleTokenV3_1(strategyToken).mintIdleToken(_amount, true, address(0));
    IERC20(strategyToken).safeTransfer(msg.sender, minted);
  }

  function redeem(uint256 _amount) external override returns(uint256 redeemed) {
    IERC20(strategyToken).safeTransferFrom(msg.sender, address(this), _amount);
    redeemed = IIdleTokenV3_1(strategyToken).redeemIdleToken(_amount);
    IERC20(token).safeTransfer(msg.sender, redeemed);

    // TODO send gov tokens too check the rest
  }

  function redeemUnderlying(uint256 _amount) external override returns(uint256 redeemed) {
    uint256 toRedeem = _amount.mul(oneToken).div(price());
    IERC20(strategyToken).safeTransferFrom(msg.sender, address(this), toRedeem);
    redeemed = IIdleTokenV3_1(strategyToken).redeemIdleToken(toRedeem);
    IERC20(token).safeTransfer(msg.sender, redeemed);

    // TODO send gov tokens too check the rest
  }
}
