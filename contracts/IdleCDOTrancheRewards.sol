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

/// @title IdleCDOTrancheRewards
/// @notice
/// @dev
contract IdleCDOTrancheRewards is Initializable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOTrancheRewards, IdleCDOTrancheRewardsStorage {
  using AddressUpgradeable for address payable;
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice Initialize the contract
  /// @dev
  /// @param _trancheToken
  /// @param _rewards The rewards tokens
  /// @param _guardian TODO
  /// @param _idleCDO The CDO where the reward tokens come from
  /// @param _governanceRecoveryFund TODO
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

  /// @notice Stake _amount of tranche token
  /// @param _amount The amount of tranche tokens to stake
  function stake(uint256 _amount) external override {
    _updateUserIdx(msg.sender, _amount);
    usersStakes[msg.sender] += _amount;
    IERC20Detailed(tranche).safeTransferFrom(msg.sender, address(this), _amount);
    totalStaked += _amount;
  }

  /// @notice Unstake _amount of tranche tokens
  /// @param _amount The amount to unstake
  function unstake(uint256 _amount) external override {
    require(usersStakes[msg.sender] >= _amount, "Amount greater than stakes");
    _claim();
    usersStakes[msg.sender] -= _amount;
    IERC20Detailed(tranche).safeTransfer(msg.sender, _amount);
    totalStaked -= _amount;
  }

  /// @notice Sends all the expected rewards to the msg.sender
  /// @dev User index is reset
  function claim() external {
    _claim();
  }

  /// @notice Claim all rewards, used by claim and unstake
  function _claim() internal {
    for (uint256 i; i < rewards.length; i++) {
      address reward = rewards[i];
      uint256 amount = expectedUserReward(msg.sender, reward);
      uint256 balance = IERC20Detailed(reward).balanceOf(address(this));
      if (amount > balance) {
        amount = balance;
      }
      usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
      IERC20Detailed(reward).safeTransfer(msg.sender, amount);
    }
  }

  /// @notice Calculates the expected rewards for a user
  /// @dev
  /// @param user The user address
  /// @param reward The reward token address
  /// @return The expected reward amount
  function expectedUserReward(address user, address reward) public view returns(uint256) {
    require(_includesAddress(rewards, reward), "!SUPPORTED");
    return ((rewardsIndexes[reward] - usersIndexes[user][reward]) * usersStakes[user]) / ONE_TRANCHE_TOKEN;
  }

  /// @notice TODO
  /// @dev
  /// @param _reward TODO
  /// @param _amount TODO
  function depositReward(address _reward, uint256 _amount) external override {
    require(msg.sender == idleCDO, "!AUTH");
    require(_includesAddress(rewards, _reward), "!SUPPORTED");
    IERC20Detailed(_reward).safeTransferFrom(msg.sender, address(this), _amount);
    rewardsIndexes[_reward] += _amount * ONE_TRANCHE_TOKEN / totalStaked;
  }

  /// @notice TODO
  /// @dev
  /// @param _user TODO
  /// @param _amountToStake TODO
  /// @param _amountToStake TODO
  function _updateUserIdx(address _user, uint256 _amountToStake) internal {
    address[] memory _rewards = rewards;
    uint256 currIdx;
    address reward;
    uint256 _currStake = usersStakes[msg.sender];

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
