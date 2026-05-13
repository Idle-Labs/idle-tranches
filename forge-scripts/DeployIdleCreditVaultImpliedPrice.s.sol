// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {IdleCreditVaultImpliedPrice} from "../contracts/IdleCreditVaultImpliedPrice.sol";

contract DeployIdleCreditVaultImpliedPrice is Script {
  // forge script ./forge-scripts/DeployIdleCreditVaultImpliedPrice.s.sol \
  // --fork-url $ETH_RPC_URL \
  // --ledger \
  // --broadcast \
  // --verify \
  // --sender "<DEPLOYER_ADDRESS>" \
  // -vvv
  function run() external returns (IdleCreditVaultImpliedPrice deployed) {
    vm.startBroadcast();
    deployed = new IdleCreditVaultImpliedPrice();
    vm.stopBroadcast();
  }
}
