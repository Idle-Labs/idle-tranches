// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";
import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

error EpochNotRunning();
error NotAllowed();
error Is0();

/// @title IdleCDOEpochQueue
/// @dev Contract that collects deposits during an epoch to be processed in the next
/// buffer period (ie between two epochs)
contract IdleCDOEpochQueue is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice 1 tranche token = 1e18
  uint256 private constant ONE_TRANCHE = 1e18;
  /// @notice idleCDOEpochVariant contract
  address public idleCDOEpoch;
  /// @notice IdleCreditVault strategy contract 
  address public strategy;
  /// @notice address of the underlying token
  address public underlying;
  /// @notice address of the tranche
  address public tranche;
  /// @notice mapping of deposits (underlyings) per user per epoch
  mapping(address => mapping (uint256 => uint256)) public userDepositsEpochs;
  /// @notice mapping of tranche price per epoch
  mapping(uint256 => uint256) public epochPrice;
  /// @notice amount of pending deposits (underlyings) per epoch
  mapping(uint256 => uint256) public epochPendingDeposits;
  /// @notice mapping of withdraw requests (tranche tokens) per user per epoch
  mapping(address => mapping (uint256 => uint256)) public userWithdrawalsEpochs;
  /// @notice amount of pending withdrawals (tranche tokens) per epoch
  mapping(uint256 => uint256) public epochPendingWithdrawals;
  /// @notice amount of pending claims (underlyings) per epoch
  mapping(uint256 => uint256) public epochPendingClaims;
  /// @notice mapping of withdraw price per epoch
  mapping(uint256 => uint256) public epochWithdrawPrice;
  /// @notice mapping of epoch to flag if instant withdrawals are enabled
  mapping(uint256 => bool) public isEpochInstant;
  /// @notice flag to check if there are pending claims
  bool public pendingClaims;

  /// @notice initialize the implementation contract to avoid malicious initialization
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    idleCDOEpoch = address(1);
  }

  /// @notice initialize the contract
  /// @param _idleCDOEpoch address of the IdleCDOEpochVariant contract
  /// @param _owner address of the owner of the contract
  /// @param _isAATranche true if the tranche is the AA one
  function initialize(
    address _idleCDOEpoch,
    address _owner,
    bool _isAATranche
  ) external initializer {
    if (idleCDOEpoch != address(0)) {
      revert NotAllowed();
    }
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(_idleCDOEpoch);
    idleCDOEpoch = _idleCDOEpoch;
    strategy = _cdo.strategy();
    underlying = _cdo.token();
    tranche = _isAATranche ? _cdo.AATranche() : _cdo.BBTranche();
    
    // approve the CDO contract to spend the underlying tokens 
    IERC20Detailed(underlying).safeApprove(address(_cdo), type(uint256).max);

    transferOwnership(_owner);
  }

  /// @notice deposit tokens to be processed in the buffer period
  /// @param amount of underlyings to deposit
  function requestDeposit(uint256 amount) external nonReentrant {
    // check if the wallet is allowed to deposit (ie epoch is running and keyring KYC completed)
    _checkAllowed(msg.sender);
    // get underlying tokens from user
    IERC20Detailed(underlying).safeTransferFrom(msg.sender, address(this), amount);
    // deposit will be made in the next buffer period (ie next epoch)
    uint256 nextEpoch = IdleCreditVault(strategy).epochNumber() + 1;
    // updated user queued amount for the next epoch
    userDepositsEpochs[msg.sender][nextEpoch] += amount;
    // update pending deposits
    epochPendingDeposits[nextEpoch] += amount;
  }

  /// @notice request withdraw of tranche tokens
  /// @param amount of tranche tokens to withdraw
  function requestWithdraw(uint256 amount) external nonReentrant {
    // check if the wallet is allowed to deposit (ie epoch is running and keyring KYC completed)
    _checkAllowed(msg.sender);
    // get tranche tokens from user
    IERC20Detailed(tranche).safeTransferFrom(msg.sender, address(this), amount);
    // withdraw requests will be made in the next buffer period (ie next epoch)
    uint256 nextEpoch = IdleCreditVault(strategy).epochNumber() + 1;
    // updated user queued withdraw amount for the next epoch. Epoch number
    // is considered the epoch when processWithdrawRequests will be called
    userWithdrawalsEpochs[msg.sender][nextEpoch] += amount;
    // update pending withdraw requests
    epochPendingWithdrawals[nextEpoch] += amount;
  }

  /// @notice delete a deposit request
  /// @param _requestEpoch epoch of the deposit request
  function deleteRequest(uint256 _requestEpoch) external {
    // if the epoch price is already set, deposits were already processed so
    // the deposit request can't be deleted.
    // if epoch is running revert, delete of deposits requests can be done only during buffer period
    if (epochPrice[_requestEpoch] != 0 || IdleCDOEpochVariant(idleCDOEpoch).isEpochRunning()) {
      revert NotAllowed();
    }

    uint256 amount = userDepositsEpochs[msg.sender][_requestEpoch];
    if (amount == 0) {
      return;
    }
    // reset user deposit for the epoch
    userDepositsEpochs[msg.sender][_requestEpoch] = 0;
    // update pending deposits
    epochPendingDeposits[_requestEpoch] -= amount;
    // transfer underlyings back to the user
    IERC20Detailed(underlying).safeTransfer(msg.sender, amount);
  }

  /// @notice delete a withdraw request
  /// @param _requestEpoch epoch of the withdraw request
  function deleteWithdrawRequest(uint256 _requestEpoch) external {
    // if the epoch withdraw price is already set, withdrawal requests were already processed so
    // the withdraw request can't be deleted. Withdraw requests can be deleted even if the epoch is running
    if (epochWithdrawPrice[_requestEpoch] != 0) {
      revert NotAllowed();
    }

    uint256 amount = userWithdrawalsEpochs[msg.sender][_requestEpoch];
    if (amount == 0) {
      return;
    }
    // reset user withdraw request for the epoch
    userWithdrawalsEpochs[msg.sender][_requestEpoch] = 0;
    // update pending withdraw requests
    epochPendingWithdrawals[_requestEpoch] -= amount;
    // transfer tranche tokens back to the user
    IERC20Detailed(tranche).safeTransfer(msg.sender, amount);
  }

  /// @notice process deposits during buffer period. Only owner or strategy manager can call this
  /// @dev will revert in IdleCDOEpochVariant if called when epoch running
  function processDeposits() external {
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    IdleCreditVault _strategy = IdleCreditVault(strategy);
    // only owner or strategy manager can call this
    if (msg.sender != owner() && msg.sender != _strategy.manager()) {
      revert NotAllowed();
    }

    uint256 _epoch = _strategy.epochNumber();
    uint256 _pending = epochPendingDeposits[_epoch];

    if (_pending == 0) {
      return;
    }

    // deposit underlyings in the CDO contract, if the epoch is running it will revert
    uint256 _trancheMinted;
    if (tranche == _cdo.AATranche()) {
      _trancheMinted = _cdo.depositAA(_pending);
    } else {
      _trancheMinted = _cdo.depositBB(_pending);
    }
    // save current implied tranche price for this epoch based on underlyings deposited and tranche tokens minted
    epochPrice[_epoch] = _pending * ONE_TRANCHE / _trancheMinted;
    epochPendingDeposits[_epoch] = 0;
  }

  /// @notice process withdraw requests during buffer period. Only owner or strategy manager can call this
  /// @dev will revert in IdleCDOEpochVariant if called when epoch running. Note that withdrawals are a 2-step 
  /// process where first one request the withdrawl and then he claims the withdraw after an epoch is passed.
  /// Withdrawals can be of 2 types, normal withdrawals (ie users wait for a full epoch) and instant withdrawals
  /// where users wait for the instant delay period after an epoch is started (eg 3 days after epoch started)
  function processWithdrawRequests() external {
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    IdleCreditVault _strategy = IdleCreditVault(strategy);
    uint256 _epoch = _strategy.epochNumber();
    // only owner or strategy manager can call this
    // we revert if the are claims that needs to be processed
    if ((msg.sender != owner() && msg.sender != _strategy.manager()) || pendingClaims) {
      revert NotAllowed();
    }

    uint256 _pending = epochPendingWithdrawals[_epoch];
    if (_pending == 0) {
      return;
    }

    uint256 _pendingWithdraws = _strategy.pendingWithdraws();
    // here we receive strategyTokens for the queue contract, strategyTokens are 1:1 with underlyings
    // This call will set isEpochInstant to true in strategy if the epoch is an instant withdraw epoch
    uint256 _underlyingsRequested = _cdo.requestWithdraw(_pending, tranche);
    // save if the epoch is an instant withdraw epoch by comparing value of pendingWithdraws which gets updated only for instant withdraws
    isEpochInstant[_epoch] = _strategy.pendingWithdraws() == _pendingWithdraws;
    // save current implied tranche price for this epoch based on underlyings that will be received on claim
    uint256 _epochPrice = _underlyingsRequested * ONE_TRANCHE / _pending;
    if (_epochPrice == 0) {
      revert Is0();
    }
    epochWithdrawPrice[_epoch] = _epochPrice;
    // set pending withdraw requests to 0
    epochPendingWithdrawals[_epoch] = 0;
    // set pending claims to the amount of underlyings requested
    epochPendingClaims[_epoch] = _underlyingsRequested;
    // set flag for pending claims to true
    pendingClaims = true;
  }

  /// @notice process withdrawal claims. Claims can be done during the epoch for instant withdrawals
  /// an only in the buffer or after one epoch for the normal withdrawals
  /// @param _epoch epoch to claim, should be the epoch in which processWithdrawRequests is called
  function processWithdrawalClaims(uint256 _epoch) external {
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    // only owner or strategy manager can call this
    if (msg.sender != owner() && msg.sender != IdleCreditVault(strategy).manager()) {
      revert NotAllowed();
    }

    uint256 _pending = epochPendingClaims[_epoch];
    if (_pending == 0) {
      return;
    }

    // check if the epoch is an instant withdraw epoch.
    // These calls will transfer underlyings to this contract and burn strategyTokens
    if (isEpochInstant[_epoch]) {
      _cdo.claimInstantWithdrawRequest();
    } else {
      _cdo.claimWithdrawRequest();
    }

    // reset epoch pending claims
    epochPendingClaims[_epoch] = 0;
    // reset pending claims flag
    pendingClaims = false;
  }

  /// @notice claim deposit request
  /// @param _epoch epoch of the deposit request
  function claimDepositRequest(uint256 _epoch) external {
    // check if deposits were processed for the epoch
    if (epochPendingDeposits[_epoch] != 0) {
      revert NotAllowed();
    }
    uint256 amount = userDepositsEpochs[msg.sender][_epoch];
    if (amount == 0) {
      return;
    }
    // reset user deposit for the epoch
    userDepositsEpochs[msg.sender][_epoch] = 0;
    // transfer tranche tokens to user based on the price of that epoch
    IERC20Detailed(tranche).safeTransfer(msg.sender, amount * ONE_TRANCHE / epochPrice[_epoch]);
  }

  /// @notice claim withdraw request
  /// @param _epoch epoch when withdraw request were processed
  function claimWithdrawRequest(uint256 _epoch) external {
    // check if withdraw requests were processed and claimed for the epoch
    if (epochWithdrawPrice[_epoch] == 0 || epochPendingClaims[_epoch] != 0) {
      revert NotAllowed();
    }
    // amount is in tranche tokens
    uint256 amount = userWithdrawalsEpochs[msg.sender][_epoch];
    if (amount == 0) {
      return;
    }
    // reset user withdraw request counter for the epoch
    userWithdrawalsEpochs[msg.sender][_epoch] = 0;
    // transfer underlyings to user based on the withdraw price of that epoch
    IERC20Detailed(underlying).safeTransfer(msg.sender, amount * epochWithdrawPrice[_epoch] / ONE_TRANCHE);
  }

  /// @notice check if the wallet is allowed to deposit
  /// @param wallet address to check
  function _checkAllowed(address wallet) internal view {
    IdleCDOEpochVariant cdoEpoch = IdleCDOEpochVariant(idleCDOEpoch);
    if (!cdoEpoch.isEpochRunning()) {
      revert EpochNotRunning();
    }
    if (!cdoEpoch.isWalletAllowed(wallet)) {
      revert NotAllowed();
    }
  }
}