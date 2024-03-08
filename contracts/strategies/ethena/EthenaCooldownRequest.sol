// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import {IStakedUSDeV2} from "../../interfaces/ethena/IStakedUSDeV2.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";

contract EthenaCooldownRequest is Clone {
  address internal constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
  address internal constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  
  /// @notice only the cdo can call this otherwise one could send 
  /// small amount of funds to this contract and request another
  /// cooldown which will restart the cooldown period
  function startCooldown() external {
    require(msg.sender == _getCDO(), '6');
    IStakedUSDeV2(SUSDE).cooldownShares(IERC20Detailed(SUSDE).balanceOf(address(this)));
  }

  /// @notice anyone can call this as the receiver is the user who
  /// created the contract in the first place
  function unstake() external {
    IStakedUSDeV2(SUSDE).unstake(_getUser());
  }

  /// @notice rescue any token from the contract
  function rescue(address _token) external {
    require(msg.sender == TL_MULTISIG, '6');
    IERC20Detailed(_token).transfer(msg.sender, IERC20Detailed(_token).balanceOf(address(this)));
  }

  /// @notice get CDO address, immutable, from contract bytecode
  function _getCDO() internal pure returns (address) {
    return _getArgAddress(0);
  }

  /// @notice get user address, immutable, from contract bytecode
  function _getUser() internal pure returns (address) {
    return _getArgAddress(20);
  }
}