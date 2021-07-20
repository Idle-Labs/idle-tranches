// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";
import "./interfaces/IIdleCDO.sol";

import "./IdleCDOTrancheRewardsStorage.sol";

/// @title IdleCDOTrancheRewards
/// @notice Contract used for staking specific tranche tokens and getting incentive rewards
/// This contract keeps the accounting of how many rewards each user is entitled to using 2 indexs:
/// a per-user index (`usersIndexes[user][reward]`) and a global index (`rewardsIndexes[reward]`)
/// The difference of those indexes
contract IdleCDOTrancheRewards is Initializable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOTrancheRewards, IdleCDOTrancheRewardsStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  // Used to prevent initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    tranche = address(1);
  }

  /// @notice Initialize the contract
  /// @param _trancheToken tranche address
  /// @param _rewards rewards token array
  /// @param _owner The owner of the contract
  /// @param _idleCDO The CDO where the reward tokens come from
  /// @param _governanceRecoveryFund address where rewards will be sent in case of transferToken call
  /// @param _coolingPeriod number of blocks that needs to pass since last staking before unstake is possible
  function initialize(
    address _trancheToken, address[] memory _rewards, address _owner,
    address _idleCDO, address _governanceRecoveryFund, uint256 _coolingPeriod
  ) public initializer {
    require(tranche == address(0), 'Initialized');
    require(_owner != address(0) && _trancheToken != address(0) && _idleCDO != address(0) && _governanceRecoveryFund != address(0), "IS_0");
    // Initialize inherited contracts
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    PausableUpgradeable.__Pausable_init();
    // transfer ownership to owner
    transferOwnership(_owner);
    // set state variables
    idleCDO = _idleCDO;
    tranche = _trancheToken;
    rewards = _rewards;
    governanceRecoveryFund = _governanceRecoveryFund;
    coolingPeriod = _coolingPeriod;
  }

  /// @notice Stake _amount of tranche token to receive rewards
  /// @param _amount The amount of tranche tokens to stake
  function stake(uint256 _amount) external whenNotPaused override {
    if (_amount == 0) {
      return;
    }
    // save current block.number
    usersStakeBlock[msg.sender] = block.number;
    // update user index for each reward, used to calculate the correct reward amount
    // for each user
    _updateUserIdx(msg.sender, _amount);
    // increase the staked amount associated with the user
    usersStakes[msg.sender] += _amount;
    // get _amount of `tranche` tokens from the user
    IERC20Detailed(tranche).safeTransferFrom(msg.sender, address(this), _amount);
    // increase the total staked amount counter
    totalStaked += _amount;
  }

  /// @notice Unstake _amount of tranche tokens and redeem ALL accrued rewards
  /// @dev if the contract is paused, unstaking any amount will cause the loss of all
  /// accrued and unclaimed rewards so far
  /// @param _amount The amount of tranche tokens to unstake
  function unstake(uint256 _amount) external nonReentrant override {
    if (_amount == 0) {
      return;
    }
    // check that the last stake was made at least `coolingPeriod` blocks
    // to prevent theft of rewards by sandwiching the `depositReward` tx
    require(usersStakeBlock[msg.sender] + coolingPeriod < block.number, "COOLING_PERIOD");

    if (paused()) {
      // If the contract is paused, "unstake" will skip the claim of the rewards,
      // and those rewards won't be claimable in the future.
      address reward;
      for (uint256 i = 0; i < rewards.length; i++) {
        reward = rewards[i];
        // set the user index equal to the global one, which means 0 rewards
        usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
      }
    } else {
      // Claim all rewards accrued
      _claim();
    }
    // if _amount is greater than usersStakes[msg.sender], the next line fails
    usersStakes[msg.sender] -= _amount;
    // send funds to the user
    IERC20Detailed(tranche).safeTransfer(msg.sender, _amount);
    // update the total staked counter
    totalStaked -= _amount;
  }

  /// @notice Sends all the expected rewards to the msg.sender
  /// @dev User index is reset
  function claim() whenNotPaused nonReentrant external {
    _claim();
  }

  /// @notice Claim all rewards, used by `claim` and `unstake`
  function _claim() internal {
    address[] memory _rewards = rewards;
    for (uint256 i = 0; i < _rewards.length; i++) {
      address reward = _rewards[i];
      // get how much `reward` we should send to the user
      uint256 amount = expectedUserReward(msg.sender, reward);
      uint256 balance = IERC20Detailed(reward).balanceOf(address(this));
      // Check that the amount is available in the contract
      if (amount > balance) {
        amount = balance;
      }
      // Set the user index equal to the global one, which means 0 rewards
      usersIndexes[msg.sender][reward] = rewardsIndexes[reward];
      // transfer the reward to the user
      IERC20Detailed(reward).safeTransfer(msg.sender, amount);
    }
  }

  /// @notice Calculates the expected rewards for a user
  /// @param user The user address
  /// @param reward The reward token address
  /// @return The expected reward amount
  function expectedUserReward(address user, address reward) public view returns(uint256) {
    require(_includesAddress(rewards, reward), "!SUPPORTED");
    // The amount of rewards for a specific reward token is given by the difference
    // between the global index and the user's one multiplied by the user staked balance
    return ((rewardsIndexes[reward] - usersIndexes[user][reward]) * usersStakes[user]) / ONE_TRANCHE_TOKEN;
  }

  /// @notice Called by IdleCDO to deposit incentive rewards
  /// @param _reward The rewards token address
  /// @param _amount The amount to deposit
  function depositReward(address _reward, uint256 _amount) external override {
    require(msg.sender == idleCDO, "!AUTH");
    require(_includesAddress(rewards, _reward), "!SUPPORTED");
    // Get rewards from IdleCDO
    IERC20Detailed(_reward).safeTransferFrom(msg.sender, address(this), _amount);
    if (totalStaked > 0) {
      // rewards are splitted among all stakers by increasing the global index
      // proportionally for everyone (based on totalStaked)
      rewardsIndexes[_reward] += _amount * ONE_TRANCHE_TOKEN / totalStaked;
    }
  }
  /// @notice It sets the coolingPeriod that a user needs to wait since his last stake
  /// before the unstake will be possible
  /// @param _newCoolingPeriod The new cooling period
  function setCoolingPeriod(uint256 _newCoolingPeriod) external onlyOwner {
    coolingPeriod = _newCoolingPeriod;
  }

  /// @notice Update user indexe for each reward, based on the amount being staked
  /// @param _user The user who is staking
  /// @param _amountToStake The amound staked
  function _updateUserIdx(address _user, uint256 _amountToStake) internal {
    address[] memory _rewards = rewards;
    uint256 userIndex;
    address reward;
    uint256 _currStake = usersStakes[_user];

    for (uint256 i = 0; i < _rewards.length; i++) {
      reward = _rewards[i];
      if (_currStake == 0) {
        // Set the user address equal to the global one which means 0 reward for the user
        usersIndexes[_user][reward] = rewardsIndexes[reward];
      } else {
        userIndex = usersIndexes[_user][reward];
        // Calculate the new user idx
        // The user already staked something so he already have some accrued rewards
        // which are: r = (rewardsIndexes - userIndex) * _currStake -> (see expectedUserReward method)
        // Those same rewards should now be splitted between more staked tokens
        // specifically (_currStake + _amountToStake) so the userIndex should increase.
        usersIndexes[_user][reward] = userIndex + (
          // Accrued rewards should not change after adding more staked tokens so
          // we can calculate the increase of the userIndex by solving the following equation
          // (rewardsIndexes - userIndex) * _currStake = (rewardsIndexes - (userIndex + X)) * (_currStake + _amountToStake)
          // for X we get the increase for the userIndex:
          _amountToStake * (rewardsIndexes[reward] - userIndex) / (_currStake + _amountToStake)
        );
      }
    }
  }

  /// @dev this method is only used to check whether a token is an incentive tokens or not
  /// in the depositReward call. The maximum number of element in the array will be a small number (eg at most 3-5)
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

  // @notice Emergency method, funds gets transferred to the governanceRecoveryFund address
  function transferToken(address token, uint256 value) external onlyOwner nonReentrant {
    require(token != address(0), 'Address is 0');
    IERC20Detailed(token).safeTransfer(governanceRecoveryFund, value);
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
