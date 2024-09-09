// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IIdleCDO {
  function AATranche() external view returns(address);
  function BBTranche() external view returns(address);
  function AAStaking() external view returns(address);
  function BBStaking() external view returns(address);
  function strategy() external view returns(address);
  function strategyToken() external view returns(address);
  function token() external view returns(address);
  function rebalancer() external view returns(address);
  function owner() external view returns(address);
  function paused() external view returns(bool);
  function directDeposit() external view returns(bool);

  function allowAAWithdraw() external view returns(bool);
  function allowBBWithdraw() external view returns(bool);
  function fee() external view returns(uint256);
  function limit() external view returns(uint256);
  function unclaimedFees() external view returns(uint256);
  function getApr(address _tranche) external view returns(uint256);
  function getContractValue() external view returns(uint256);
  function trancheAPRSplitRatio() external view returns(uint256);
  function getCurrentAARatio() external view returns(uint256);
  function tranchePrice(address _tranche) external view returns(uint256);
  function virtualPrice(address _tranche) external view returns(uint256);
  function getIncentiveTokens() external view returns(address[] memory);
  function setUnlentPerc(uint256) external;

  function depositAA(uint256) external returns(uint256);
  function depositBB(uint256) external returns(uint256);
  function withdrawAA(uint256) external returns(uint256);
  function withdrawBB(uint256) external returns(uint256);
  function emergencyShutdown() external;
  function setGuardian(address) external;

  function harvest(
    bool[] calldata _skipFlags,
    bool[] calldata _skipReward,
    uint256[] calldata _minAmount,
    uint256[] calldata _sellAmounts,
    bytes[] calldata _extraData
  ) external returns (uint256[][] memory _res);
}