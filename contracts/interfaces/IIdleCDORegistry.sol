// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIdleCDORegistry {
  function isValidCdo(address) external view returns(bool);
  function toggleCDO(address _cdo, bool _valid) external;
}