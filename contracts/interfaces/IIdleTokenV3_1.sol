// SPDX-License-Identifier: Apache-2.0
/**
 * @title: Idle Token interface
 * @author: Idle Labs Inc., idle.finance
 */
pragma solidity 0.7.6;

import "./IERC20Permit.sol";

interface IIdleTokenV3_1 is IERC20Detailed {
  function tokenPrice() external view returns (uint256 price);
  function tokenDecimals() external view returns (uint256);
  function token() external view returns (address);
  function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);
  function mintIdleToken(uint256 _amount, bool _skipRebalance, address _referral) external returns (uint256 mintedTokens);
  function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
  function redeemInterestBearingTokens(uint256 _amount) external;
  function rebalance() external returns (bool);
  function govTokens(uint256 index) external view returns (address);
  function getGovTokensAmounts(address _usr) external view returns (uint256[] memory _amounts);
}
