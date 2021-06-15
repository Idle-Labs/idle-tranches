// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockIdleCDO {
  using SafeERC20 for IERC20;

  address[] public rewards;
  address public trancheRewardsContract;

  constructor(address[] memory _rewards) {
    rewards = _rewards;
  }

  function setTrancheRewardsContract(address a) external {
    trancheRewardsContract = a;
  }

  function redeemRewards() external {
    for (uint256 i = 0; i < rewards.length; i++) {
      address reward = rewards[i];
      IERC20(reward).safeTransfer(trancheRewardsContract, IERC20(reward).balanceOf(address(this)));
    }
  }
}
