// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.7;

contract IdleCDOTrancheRewardsStorage {
  uint256 public constant ONE_TRANCHE_TOKEN = 10**18;
  address public idleCDO;
  address public tranche;
  address public governanceRecoveryFund;
  address[] public rewards;
  // amount staked for each user
  mapping(address => uint256) public usersStakes;
  // globalIndex for each reward token
  mapping(address => uint256) public rewardsIndexes;
  // per-user index for each reward token
  mapping(address => mapping(address => uint256)) public usersIndexes;
  // rewards => last amount of reward deposited
  mapping(address => uint256) public lockedRewards;
  // rewards => block in which last rewards have been deposited
  mapping(address => uint256) public lockedRewardsLastBlock;
  // total amount of tranche tokens staked
  uint256 public totalStaked;
  // number of blocks during which rewards will be released for stakers
  uint256 public coolingPeriod;
}
