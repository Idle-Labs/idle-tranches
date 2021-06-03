//SPDX-License-Identifier: Apache 2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Inherit this contract and add the _guarded method to the child contract
abstract contract GuardedLaunchUpgradable is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using AddressUpgradeable for address payable;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 public limit;
  address public governanceRecoveryFund;
  IERC20Upgradeable public guardedToken;
  IERC20Upgradeable public guardedInterestBearing;
  mapping (address => uint256) private userDeposits;

  function __GuardedLaunch_init(uint256 _limit, address _guardedToken, address _governanceRecoveryFund, address _guardian) internal initializer {
    require(_governanceRecoveryFund != address(0) && _guardedToken != address(0), 'Address is 0');
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    limit = _limit;
    governanceRecoveryFund = _governanceRecoveryFund;
    guardedToken = IERC20Upgradeable(_guardedToken);
    transferOwnership(_guardian);
  }

  // Call this method inside the child contract
  function _guarded(uint256 _amount) internal view {
    if (limit == 0) {
      return;
    }
    require(getContractValue() + _amount <= limit, 'Contract limit');
  }

  // abstract
  function getContractValue() public virtual view returns (uint256);

  // 0 means no limit
  function _setLimit(uint256 _limit) external onlyOwner {
    limit = _limit;
  }

  // Emergency methods, funds gets transferred to the governanceRecoveryFund address
  function transferToken(address token, uint256 value) external onlyOwner nonReentrant returns (bool) {
    require(token != address(0), 'Address is 0');
    IERC20Upgradeable(token).safeTransfer(governanceRecoveryFund, value);
    return true;
  }
  function transferETH(uint256 value) onlyOwner nonReentrant external {
    address payable to = payable(governanceRecoveryFund);
    to.sendValue(value);
  }
}
