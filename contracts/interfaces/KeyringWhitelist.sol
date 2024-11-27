// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface KeyringWhitelist {
  function setWhitelistStatus(address entity, bool status) external;
  function whitelist(address entity) external view returns(bool);
}