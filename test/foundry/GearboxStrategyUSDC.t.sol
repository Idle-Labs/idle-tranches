// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";
import {TestGearboxStrategyWETH} from "./GearboxStrategyWETH.t.sol";

contract TestGearboxStrategyUSDC is TestGearboxStrategyWETH {
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  function setUp() public override {
    defaultUnderlying = USDC;
    defaultStaking = 0x9ef444a6d7F4A5adcd68FD5329aA5240C90E14d2;
    defaultUniv3Path = abi.encodePacked(GEAR, uint24(10000), WETH, uint24(500), USDC);
    defaultVault = IERC4626Upgradeable(0xda00000035fef4082F78dEF6A8903bee419FbF8E);
    super.setUp();
  }
}
