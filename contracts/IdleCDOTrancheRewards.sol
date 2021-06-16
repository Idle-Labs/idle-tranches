// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";
import "./interfaces/IIdleCDO.sol";

import "./IdleCDOTrancheRewardsStorage.sol";
import "hardhat/console.sol";

contract IdleCDOTrancheRewards is Initializable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOTrancheRewards, IdleCDOTrancheRewardsStorage {
  using AddressUpgradeable for address payable;
  using SafeERC20Upgradeable for IERC20Detailed;

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
    _updateUserIdx(msg.sender, _amount);
    usersStakes[msg.sender] += _amount;
    IERC20Detailed(tranche).safeTransferFrom(msg.sender, address(this), _amount);
    totalStaked += _amount;
  }

  function unstake(uint256 _amount) external override returns (uint256) {
    _updateUserIdx(msg.sender, 0);
    // _claim();
    usersStakes[msg.sender] -= _amount;
    IERC20Detailed(tranche).safeTransfer(msg.sender, _amount);
    totalStaked -= _amount;
  }

  function userExpectedReward(address user, address reward) public view returns(uint256) {
    require(_includesAddress(rewards, reward), "!SUPPORTED");

    return ((rewardsIndexes[reward] - usersIndexes[user][reward]) * usersStakes[user]) / ONE_TRANCHE_TOKEN;
  }

  function totalRewards(address _reward) public view returns(uint256) {
    return IERC20Detailed(_reward).balanceOf(address(this));
  }

  function depositReward(address _reward, uint256 _amount) external override {
    require(msg.sender == idleCDO, "!AUTH");
    require(_amount > 0, "!AMOUNT0");
    require(_includesAddress(rewards, _reward), "!SUPPORTED");
    IERC20Detailed(_reward).safeTransferFrom(msg.sender, address(this), _amount);
    rewardsIndexes[_reward] += _amount * ONE_TRANCHE_TOKEN / totalStaked;
  }

  function _updateUserIdx(address _user, uint256 _amountToStake) internal {
    address[] memory _rewards = rewards;
    uint256 currIdx;
    address reward;
    uint256 _currStake = usersStakes[msg.sender];

    // for (uint256 i = 0; i < rewards.length; i++) {
    //   address reward = rewards[i];
    //   if (_currStake == 0) {
    //     usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
    //   } else {
    //     uint256 globIdx = rewardsIndexes[reward];
    //     uint256 userIndex = usersIndexes[msg.sender][reward];
    //     uint256 currReward = _amountToStake * (globIdx - userIndex);
    //
    //     // uixd = currReward / (staked + _amountToStake) - globIdx
    //     usersIndexes[msg.sender][reward] = (currReward * ONE_TRANCHE_TOKEN / (_currStake + _amountToStake)) - globIdx;
    //   }
    // }

    for (uint256 i = 0; i < rewards.length; i++) {
      address reward = rewards[i];
      if (_currStake == 0) {
        usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
      } else {
        uint256 userIndex = usersIndexes[msg.sender][reward];
        usersIndexes[msg.sender][reward] = userIndex + (
          _amountToStake * (rewardsIndexes[reward] - userIndex) / (usersStakes[msg.sender] + _amountToStake)
        );
      }
    }
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
    IERC20Detailed(token).safeTransfer(governanceRecoveryFund, value);
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
