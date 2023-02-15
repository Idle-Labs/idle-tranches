// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./libraries/Types.sol";

interface IMAProxy {
  function market(address poolToken) external view returns (Types.Market memory market);
  function deltas(address poolToken) external view returns (Types.Delta memory market);
}