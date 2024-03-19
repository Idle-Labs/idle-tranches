// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {DelegateStakingRewardsIDLE} from "../../contracts/DelegateStakingRewardsIDLE.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error NotWhitelisted();

contract TestDelegateStakingRewardsIDLE is Test {
  uint256 BLOCK = 19462710;
  string constant network = 'mainnet';
  address public TREASURY = 0xe4E69ef860D3018B61A25134D60678be8628f780;
  address public IDLE = 0x875773784Af8135eA0ef43b5a374AaD105c5D39e;
  address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  address public constant address1 = 0x500D082eBb47447489D7dAB8fAcE2Ffcb2D4a2De;
  address public constant address2 = 0xd889Acb680D5eDbFeE593d2b7355a666248bAB9b;

  DelegateStakingRewardsIDLE public stakingRewards;

  function setUp() public {
    vm.createSelectFork(network, BLOCK);
    address[] memory _whitelisted = new address[](2);
    _whitelisted[0] = address1;
    _whitelisted[1] = address2;

    stakingRewards = new DelegateStakingRewardsIDLE(
      TREASURY, // rewardsDistributor
      USDC,
      IDLE,
      address(this), // set to deployer
      _whitelisted
    );

    vm.prank(address1);
    IERC20Detailed(IDLE).approve(address(stakingRewards), 100_000e18);
    vm.prank(address2);
    IERC20Detailed(IDLE).approve(address(stakingRewards), 100_000e18);
    vm.prank(TREASURY);
    IERC20Detailed(USDC).approve(address(stakingRewards), type(uint256).max);
  }

  function testStaking() external {
    console.log('BLOCK', block.number);
    vm.expectRevert(NotWhitelisted.selector);
    vm.prank(makeAddr('0xbadbeef'));
    stakingRewards.stake(100_000e18);

    vm.prank(address1);
    stakingRewards.stake(100_000e18);
    vm.prank(address2);
    stakingRewards.stake(100_000e18);
    vm.prank(TREASURY);
    stakingRewards.depositReward(address(0), 1_000e6);

    assertApproxEqAbs(stakingRewards.earned(address1), 0, 1e6);
    assertApproxEqAbs(stakingRewards.earned(address2), 0, 1e6);

    skip(7 days);

    assertApproxEqAbs(stakingRewards.earned(address1), 500e6, 1e6);
    assertApproxEqAbs(stakingRewards.earned(address2), 500e6, 1e6);

    skip(7 days);

    vm.prank(TREASURY);
    stakingRewards.depositReward(address(0), 1_000e6);

    skip(7 days);
    assertApproxEqAbs(stakingRewards.earned(address1), 1_000e6, 1e6);
    assertApproxEqAbs(stakingRewards.earned(address2), 1_000e6, 1e6);
  }
}