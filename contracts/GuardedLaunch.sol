//SPDX-License-Identifier: Apache 2.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Inherit this contract and add the _guarded method to the child contract
contract GuardedLaunch is Ownable, ReentrancyGuard, Pausable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  uint256 public limit;
  uint256 public userLimit;
  address public governanceRecoveryFund;
  ERC20 public guardedToken;
  mapping (address => uint256) private userDeposits;

  constructor(uint256 _limit, uint256 _userLimit, address _guardedToken, address _governanceRecoveryFund) {
    require(_governanceRecoveryFund != address(0) && _guardedToken != address(0), 'Address is 0');
    limit = _limit;
    userLimit = _userLimit;
    governanceRecoveryFund = _governanceRecoveryFund;
    guardedToken = ERC20(_guardedToken);
  }

  // Call this method inside the child contract
  function _guarded(uint256 _amount) internal {
    if (userLimit == 0 && limit == 0) {
      return;
    }

    uint256 userDeposit = userDeposits[msg.sender].add(_amount);
    require(userDeposit < userLimit, 'User limit');
    require(guardedToken.balanceOf(address(this)).add(_amount) < limit, 'Contract limit');

    userDeposits[msg.sender] = userDeposit;
  }
  // 0 means no limit
  function _setLimit(uint256 _limit) external onlyOwner returns (bool) {
    limit = _limit;
  }
  // 0 means no limit
  function _setUserLimit(uint256 _userLimit) external onlyOwner returns (bool) {
    userLimit = _userLimit;
  }

  // Emergency methods, funds gets transferred to the governanceRecoveryFund address
  function transferToken(address token, uint256 value) external onlyOwner nonReentrant returns (bool) {
    require(token != address(0), 'Address is 0');
    IERC20(token).safeTransfer(governanceRecoveryFund, value);
    return true;
  }
  function transferETH(uint256 value) onlyOwner nonReentrant external {
    address payable to = governanceRecoveryFund;
    to.sendValue(value);
  }
}
