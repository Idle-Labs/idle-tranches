//SPDX-License-Identifier: Apache 2.0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice contract used to redistribute funds after a default. One contract for each tranche 
/// class will be created, junior class will be refunded only if senior holders are whole
/// @dev this contract is expected to have *all* `token` transferred to this contract
/// before the first claim AND `totalSupply` of `trancheToken` fixed (ie main contract is paused
/// and no more mint/burn are possible)
contract DefaultDistributor is Ownable {
  using SafeERC20 for IERC20;

  uint256 public constant ONE_TRANCHE = 1e18;
  // underlying token to distribute
  address public token;
  // tranche token to burn to get underlying
  address public trancheToken;
  // rate of underlying for each tranche token
  uint256 public rate;
  // is claim active
  bool public isActive;

  constructor(address _token, address _trancheToken, address _owner) {
    token = _token;
    trancheToken = _trancheToken;
    transferOwnership(_owner);
  }

  /// @notice transfer tranche tokens to this contract and send proportional amount of 
  /// underlying to `_to`
  /// @param _to recipient address
  function claim(address _to) external {
    require(isActive, '!ACTIVE');
    IERC20 tranche = IERC20(trancheToken);
    uint256 trancheBal = tranche.balanceOf(msg.sender);
    tranche.safeTransferFrom(msg.sender, address(this), trancheBal);
    IERC20(token).safeTransfer(_to, trancheBal * rate / ONE_TRANCHE);
  }

  /// @notice Start claim process and set redemption rate
  /// @param _active claim active flag
  function setIsActive(bool _active) external {
    require(owner() == msg.sender, '!AUTH');
    isActive = _active;
    if (_active) {
      rate = IERC20(token).balanceOf(address(this)) * ONE_TRANCHE / IERC20(trancheToken).totalSupply();
    }
  }

  /// @notice Emergency method, tokens gets transferred out 
  /// @param _token address
  /// @param _to recipient
  /// @param _value amount to transfer
  function transferToken(address _token, address _to, uint256 _value) external {
    require(owner() == msg.sender, '!AUTH');
    IERC20(_token).safeTransfer(_to, _value);
  }
}
