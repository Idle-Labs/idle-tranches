// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

contract IdleCDOTrancheRewardsStorage {
  address public idleCDO;
  address public tranche;
  address public governanceRecoveryFund;
  address[] public rewards;
}
