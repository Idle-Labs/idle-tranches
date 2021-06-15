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
import "./interfaces/IIdleCDO.sol";

import "./IdleCDOTrancheRewardsStorage.sol";
import "hardhat/console.sol";

contract IdleCDOTrancheRewards is Initializable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOTrancheRewards, IdleCDOTrancheRewardsStorage {
  using AddressUpgradeable for address payable;
  using SafeERC20Upgradeable for IERC20Detailed;

  uint256 private constant ONE_18 = 10**18;

  mapping(address => uint256) public usersStakes;
  mapping(address => uint256) public rewardsIndexes;
  mapping(address => mapping(address => uint256)) public usersIndexes;
  mapping(address => uint256) public rewardsLastBalance;

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
    //TODO check _amount > 0
    IERC20Upgradeable(tranche).safeTransferFrom(msg.sender, address(this), _amount);

    address user = msg.sender;
    _redeemRewards(user);

    usersStakes[user] += _amount;

    address reward;
    uint256 userStakes = usersStakes[user];
    uint256 userIndex;

    for (uint256 i = 0; i < rewards.length; i++) {
      reward = rewards[i];
      userIndex = usersIndexes[reward][user];

      usersIndexes[reward][user] = userIndex +
        _amount * (rewardsIndexes[reward] - userIndex) / userStakes;
    }

    return _amount;
  }

  function _redeemRewards(address user) internal {
    if (rewards.length == 0) {
      return;
    }


    uint256 totalStaked = totalStaked();
    uint256 userStakes = usersStakes[user];
    address reward;

    if (totalStaked > 0) {
      IIdleCDO(idleCDO).redeemRewards();

      for (uint256 i = 0; i < rewards.length; i++) {
        reward = rewards[i];

        uint256 rewardBalance = totalRewards(reward);
        if (rewardBalance > 0) {
          rewardsIndexes[reward] = rewardsIndexes[reward] + (
            (rewardBalance - rewardsLastBalance[reward]) * ONE_18 / totalStaked
          );
          rewardsLastBalance[reward] = rewardBalance;
        }

        if (userStakes > 0) {
          uint256 usrIndex = usersIndexes[reward][user];
          uint256 delta = rewardsIndexes[reward] - usrIndex;
          console.log("**** reward index gov %s", rewardsIndexes[reward] / ONE_18);
          console.log("**** user index %s", usrIndex / ONE_18);
          console.log("**** reward index %s", (rewardsIndexes[reward] - usrIndex) / ONE_18);
          if (delta != 0) {
            uint256 share = userStakes * delta / ONE_18;
            console.log("**** userStakes %s", userStakes / ONE_18);
            console.log("**** totalStaked %s", totalStaked / ONE_18);
            console.log("**** share %s", share / ONE_18);
            uint256 bal = totalRewards(reward);
            if (share > bal) {
              share = bal;
            }

            IERC20Upgradeable(reward).safeTransfer(user, share);
            rewardsLastBalance[reward] = totalRewards(reward);
          }
        }
        // save current index for this gov token
        usersIndexes[reward][user] = rewardsIndexes[reward];
        console.log("**** NEW user index %s", rewardsIndexes[reward] / ONE_18);
      }
    }
  }

  function unstake(uint256 _amount) external override  returns (uint256) {
    return _amount;
  }

  function userReward(address reward, address user) public view returns(uint256) {
    uint256 totalStaked = IERC20Upgradeable(tranche).balanceOf(address(this));
    if (totalStaked == 0) {
      return 0;
    }

    return 0;
  }

  function totalStaked() public view returns(uint256) {
    return IERC20Upgradeable(tranche).balanceOf(address(this));
  }

  function totalRewards(address _reward) public view returns(uint256) {
    return IERC20Upgradeable(_reward).balanceOf(address(this));
  }

  function depositReward(address _reward, uint256 _amount) external override {
    require(msg.sender == idleCDO, "!AUTH");
    require(_includesAddress(rewards, _reward), "!SUPPORTED");
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
