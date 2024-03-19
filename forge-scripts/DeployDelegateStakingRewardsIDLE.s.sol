// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {DelegateStakingRewardsIDLE} from "../contracts/DelegateStakingRewardsIDLE.sol";
import {IERC20Detailed} from "../contracts/interfaces/IERC20Detailed.sol";

contract DeployDelegateStakingRewardsIDLE is Script {
  address public DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address public TREASURY = 0xe4E69ef860D3018B61A25134D60678be8628f780;
  address public IDLE = 0x875773784Af8135eA0ef43b5a374AaD105c5D39e;
  address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  // forge script ./forge-scripts/DeployDelegateStakingRewardsIDLE.s.sol \
  // --fork-url $ETH_RPC_URL \
  // --ledger \
  // --broadcast \
  // --optimize \
  // --optimizer-runs 200 \
  // --verify \
  // --with-gas-price 50000000000 \
  // --sender "0xE5Dab8208c1F4cce15883348B72086dBace3e64B" \
  // -vvv
  function run() external {
    vm.startBroadcast();
    address[] memory _whitelisted = new address[](0);
    DelegateStakingRewardsIDLE stakingRewards = new DelegateStakingRewardsIDLE(
      TREASURY, // rewardsDistributor
      USDC,
      IDLE,
      DEPLOYER,
      _whitelisted
    );
    vm.stopBroadcast();
  }
}