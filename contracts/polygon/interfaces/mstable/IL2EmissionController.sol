// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IL2EmissionController {
    function distributeRewards(address[] memory _endRecipients) external;
}
