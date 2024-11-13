//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract Timelock is TimelockController {
  constructor(
    uint256 minDelay, 
    address[] memory proposers, 
    address[] memory executors,
    address owner
  ) TimelockController(minDelay, proposers, executors, owner) {}
}