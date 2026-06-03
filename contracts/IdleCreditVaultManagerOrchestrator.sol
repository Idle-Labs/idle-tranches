// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCDOEpochQueue} from "./IdleCDOEpochQueue.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

/// @title IdleCreditVaultManagerOrchestrator
/// @notice Narrow manager contract for operating multiple single-asset credit vaults as a cluster.
contract IdleCreditVaultManagerOrchestrator is Initializable, OwnableUpgradeable {
  /// @param cdo credit vault to stop
  /// @param newApr APR to set for the next epoch
  /// @param interest stop-epoch interest override
  /// @param duration duration to set for the next epoch
  /// @param loss strategy-token loss amount to burn after stop
  /// @param allowDefault true to allow this action to leave the vault defaulted
  struct StopEpochWithDurationAction {
    address cdo;
    uint256 newApr;
    uint256 interest;
    uint256 duration;
    uint256 loss;
    bool allowDefault;
  }

  error OrchestratorNotOperator();
  error OrchestratorNotAllowed();
  error OrchestratorInvalidAddress();
  error OrchestratorStartFailed();
  error OrchestratorDefaulted();

  address public operator;
  mapping(address => bool) public isCreditVaultAllowed;

  /// @param cdo credit vault whose epoch was started
  event EpochStarted(address indexed cdo);
  /// @param cdo credit vault whose epoch was stopped
  /// @param defaulted true if the vault is defaulted after stopping
  event EpochStopped(address indexed cdo, bool defaulted);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the orchestrator.
  /// @param _operator account allowed to operate cluster and forwarded manager actions
  function initialize(address _operator) external initializer {
    __Ownable_init();
    _checkAddress(_operator);
    operator = _operator;
  }

  /// @notice Set the account allowed to operate cluster and forwarded manager actions.
  /// @param _operator new operator address
  function setOperator(address _operator) external {
    _checkOnlyOwner();
    _checkAddress(_operator);
    operator = _operator;
  }

  /// @notice Allow or remove one CDO from orchestrated actions.
  /// @param _cdo credit vault address
  /// @param _allowed true to allow orchestrated actions for `_cdo`, false to remove it
  function setCreditVaultAllowed(address _cdo, bool _allowed) external {
    _checkOnlyOwner();
    _checkAddress(_cdo);
    isCreditVaultAllowed[_cdo] = _allowed;
  }

  /// @notice Start all provided vault epochs atomically.
  /// @param _cdos credit vaults to start
  function startEpoch(address[] calldata _cdos) external {
    _checkOnlyOperator();

    uint256 len = _cdos.length;
    for (uint256 i = 0; i < len; i++) {
      IdleCDOEpochVariant cdo = _creditVault(_cdos[i]);
      cdo.startEpoch();
      if (!cdo.isEpochRunning() || cdo.defaulted()) revert OrchestratorStartFailed();
      emit EpochStarted(address(cdo));
    }
  }

  /// @notice Stop vault epochs with duration updates atomically, optionally allowing selected vaults to default.
  /// @param _actions stop-with-duration parameters for each credit vault
  function stopEpochWithDuration(StopEpochWithDurationAction[] calldata _actions) external {
    _checkOnlyOperator();

    uint256 len = _actions.length;
    for (uint256 i = 0; i < len; i++) {
      StopEpochWithDurationAction calldata op = _actions[i];
      IdleCDOEpochVariant cdo = _creditVault(op.cdo);
      cdo.stopEpochWithDuration(op.newApr, op.interest, op.duration, op.loss);
      _finalizeStopEpoch(cdo, op.allowDefault);
    }
  }

  /// @notice Forward `getInstantWithdrawFunds` to one registered CDO.
  /// @param _cdo credit vault address
  function getInstantWithdrawFunds(address _cdo) external {
    _checkOnlyOperator();
    _creditVault(_cdo).getInstantWithdrawFunds();
  }

  /// @notice Forward `setEpochParams` to one registered CDO.
  /// @param _cdo credit vault address
  /// @param _epochDuration new epoch duration
  /// @param _bufferPeriod new buffer period between epochs
  function setEpochParams(address _cdo, uint256 _epochDuration, uint256 _bufferPeriod) external {
    _checkOnlyOperator();
    _creditVault(_cdo).setEpochParams(_epochDuration, _bufferPeriod);
  }

  /// @notice Forward raw strategy APRs to the strategy derived from a registered CDO.
  /// @param _cdo credit vault address
  /// @param _unscaledApr unscaled APR to save in the strategy
  /// @param _apr raw APR to save in the strategy
  function setStrategyAprsRaw(address _cdo, uint256 _unscaledApr, uint256 _apr) external {
    _checkOnlyOperator();
    IdleCreditVault(_creditVault(_cdo).strategy()).setAprs(_unscaledApr, _apr);
  }

  /// @notice Forward `setCanTransfer` to the strategy derived from a registered CDO.
  /// @param _cdo credit vault address
  /// @param _canTransfer true to allow strategy-token transfers
  function setCanTransfer(address _cdo, bool _canTransfer) external {
    _checkOnlyOperator();
    IdleCreditVault(_creditVault(_cdo).strategy()).setCanTransfer(_canTransfer);
  }

  /// @notice Forward `processDeposits` to a queue linked to a registered CDO.
  /// @param _epochQueue queue address whose CDO must be registered
  function processDeposits(address _epochQueue) external {
    _checkOnlyOperator();
    _creditVaultQueue(_epochQueue).processDeposits();
  }

  /// @notice Forward `processWithdrawRequests` to a queue linked to a registered CDO.
  /// @param _epochQueue queue address whose CDO must be registered
  function processWithdrawRequests(address _epochQueue) external {
    _checkOnlyOperator();
    _creditVaultQueue(_epochQueue).processWithdrawRequests();
  }

  /// @notice Forward `processWithdrawalClaims` to a queue linked to a registered CDO.
  /// @param _epochQueue queue address whose CDO must be registered
  /// @param _claimEpoch epoch whose withdrawal claims should be processed
  function processWithdrawalClaims(address _epochQueue, uint256 _claimEpoch) external {
    _checkOnlyOperator();
    _creditVaultQueue(_epochQueue).processWithdrawalClaims(_claimEpoch);
  }

  /// @param _cdo credit vault address
  /// @return cdo typed credit vault
  function _creditVault(address _cdo) internal view returns (IdleCDOEpochVariant cdo) {
    if (!isCreditVaultAllowed[_cdo]) revert OrchestratorNotAllowed();
    cdo = IdleCDOEpochVariant(_cdo);
  }

  /// @notice Validate and return a queue linked to a registered credit vault.
  /// @param _epochQueue queue address to validate
  /// @return epochQueue typed epoch queue
  function _creditVaultQueue(address _epochQueue) internal view returns (IdleCDOEpochQueue epochQueue) {
    _checkAddress(_epochQueue);
    epochQueue = IdleCDOEpochQueue(_epochQueue);
    if (!isCreditVaultAllowed[epochQueue.idleCDOEpoch()]) revert OrchestratorNotAllowed();
  }

  function _checkOnlyOwner() internal view {
    if (msg.sender != owner()) revert OrchestratorNotAllowed();
  }

  function _checkOnlyOperator() internal view {
    if (msg.sender != operator && msg.sender != owner()) revert OrchestratorNotOperator();
  }

  /// @param _addr address to check
  function _checkAddress(address _addr) internal pure {
    if (_addr == address(0)) revert OrchestratorInvalidAddress();
  }

  /// @param _cdo credit vault that should be stopped
  /// @param _allowDefault true to allow `_cdo` to be defaulted
  function _finalizeStopEpoch(IdleCDOEpochVariant _cdo, bool _allowDefault) internal {
    bool isDefaulted = _cdo.defaulted();
    if (isDefaulted && !_allowDefault) revert OrchestratorDefaulted();
    emit EpochStopped(address(_cdo), isDefaulted);
  }
}
