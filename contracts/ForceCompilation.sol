// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {KeyringWhitelist} from "./interfaces/KeyringWhitelist.sol";
contract ForceCompilation {
  constructor() {
    // Used to force compilation
    new ProxyAdmin();
    KeyringWhitelist wl = KeyringWhitelist(0x6351370a1c982780Da2D8c85DfedD421F7193Fa5);
    wl;
  }
}