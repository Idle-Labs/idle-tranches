// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";

import "./IdleCDOTrancheRewardsStorage.sol";

contract IdleCDOTrancheRewards is Initializable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOTrancheRewards, IdleCDOTrancheRewardsStorage {
  using AddressUpgradeable for address payable;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  function initialize(
    address _trancheToken, address[] memory _rewards, address _guardian, address _idleCDO, address _governanceRecoveryFund
  ) public initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    transferOwnership(_guardian);

    idleCDO = _idleCDO;
    tranche = _trancheToken;
    rewards = _rewards;
    governanceRecoveryFund = _governanceRecoveryFund;
  }

  function stake(uint256 _amount) external override returns (uint256) {
    return _amount;
  }
  function unstake(uint256 _amount) external override  returns (uint256) {
    return _amount;
  }
  function depositReward(address _reward, uint256 _amount) external override {
    require(msg.sender == idleCDO, "!AUTH");
    require(_includesAddress(rewards, _reward), "!SUPPORTED");
    // TODO
    _amount;
  }
  // TODO add stake, unstake, funds recover, get rewards etc


  /// @dev this method is only used to check whether a token is an incentive tokens or not
  /// in the harvest call. The maximum number of element in the array will be a small number (eg at most 3-5)
  /// @param _array array of addresses to search for an element
  /// @param _val address of an element to find
  /// @return flag if the _token is an incentive token or not
  function _includesAddress(address[] memory _array, address _val) internal pure returns (bool) {
    for (uint256 i = 0; i < _array.length; i++) {
      if (_array[i] == _val) {
        return true;
      }
    }
    // explicit return to fix linter
    return false;
  }

  // Emergency method, funds gets transferred to the governanceRecoveryFund address
  function transferToken(address token, uint256 value) external onlyOwner nonReentrant returns (bool) {
    require(token != address(0), 'Address is 0');
    IERC20Upgradeable(token).safeTransfer(governanceRecoveryFund, value);
    return true;
  }
  /// @notice can be called by both the owner and the guardian
  /// @dev Pauses deposits and redeems
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev Unpauses deposits and redeems
  function unpause() external onlyOwner {
    _unpause();
  }
}
