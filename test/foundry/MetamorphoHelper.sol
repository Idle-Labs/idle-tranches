// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {UrdFactory} from "morpho-urd/src/UrdFactory.sol";
import {Merkle} from "morpho-urd/lib/murky/src/Merkle.sol";

// This test is used only to automatically compile UrdFactory and Merkle
// contracts that are then used in TestMorphoMetamorphoStrategy via deployCode
// so to avoid compile issues with multiple solidity versions
contract TestMetamorphoHelper is Test {
  function testDeploy() public {
    UrdFactory urdFactory = new UrdFactory();
    Merkle merkle = new Merkle();

    assertEq(address(urdFactory) != address(0), true);
    assertEq(address(merkle) != address(0), true);
  }
}
