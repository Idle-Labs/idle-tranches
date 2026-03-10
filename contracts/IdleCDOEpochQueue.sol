// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCDOEpochVariantPrefunded} from "./IdleCDOEpochVariantPrefunded.sol";
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
  /// @notice amount of queued deposits (underlyings) still held by this queue per epoch
  /// @dev In prefunded mode this is set to 0 as soon as deposits are forwarded to the borrower.
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
  /// @notice amount of queued deposits already forwarded to the borrower per epoch
  /// @dev Used only by the prefunded flow. For a given epoch this is mutually exclusive with
  /// `epochPendingDeposits`: funds are either still held by the queue or already prefunded.
  mapping(uint256 => uint256) public epochPrefundedDeposits;
  /// @notice cutoff window before epoch end during which prefunded queues block new deposits
  uint256 public prefundedDepositWindow;

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
    _checkNotAllowed(idleCDOEpoch != address(0));
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

  /// @notice set the cutoff window before epoch end for prefunded queue deposits
  /// @dev Eg 5 days means deposits are accepted only until `epochEndDate - 5 days`
  function setPrefundedDepositWindow(uint256 _prefundedDepositWindow) external {
    // only owner or strategy manager can update the prefunded deposit cutoff
    _checkOnlyOwnerOrManager();
    prefundedDepositWindow = _prefundedDepositWindow;
  }

  /// @notice deposit tokens to be processed in the buffer period
  /// @param amount of underlyings to deposit
  function requestDeposit(uint256 amount) external nonReentrant {
    // check if the wallet is allowed to deposit (ie epoch is running and keyring KYC completed)
    _checkAllowed(msg.sender);

    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    uint256 nextEpoch = IdleCreditVault(strategy).epochNumber() + 1;
    uint256 _prefundedWindow = prefundedDepositWindow;
    // Only the AA prefunded queue enforces a deposit cutoff for the next epoch.
    if (tranche == _cdo.AATranche() && _isPrefundedQueueEnabled()) {
      // Once funds are prefunded, or once the subscription window is reached, the next epoch is closed.
      _checkNotAllowed(epochPrefundedDeposits[nextEpoch] != 0 || (
        _prefundedWindow != 0 && block.timestamp + _prefundedWindow >= _cdo.epochEndDate()
      ));
    }

    // get underlying tokens from user
    IERC20Detailed(underlying).safeTransferFrom(msg.sender, address(this), amount);
    // deposit will be made in the next buffer period (ie next epoch)
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

  /// @notice Send all queued deposits for the next epoch to the borrower before epoch stop
  /// @dev This switches the epoch from "pending in queue" to "prefunded to borrower".
  /// After this call, no additional deposits can join the same epoch.
  function processDepositsToBorrower() external {
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    IdleCreditVault _strategy = IdleCreditVault(strategy);
    // only owner or strategy manager can move queued funds to the borrower
    _checkOnlyOwnerOrManager();
    // prefunded flow is supported only for AA queue
    // queue must be explicitly enabled on the prefunded CDO variant
    _checkNotAllowed(tranche != _cdo.AATranche() || !_isPrefundedQueueEnabled());

    // prefunding can be done only while epoch is running
    if (!_cdo.isEpochRunning()) {
      revert EpochNotRunning();
    }

    uint256 _epoch = _strategy.epochNumber() + 1;
    // prefunding can happen only once for an epoch
    _checkNotAllowed(epochPrefundedDeposits[_epoch] != 0);
    uint256 _pending = epochPendingDeposits[_epoch];
    if (_pending == 0) {
      return;
    }

    // Switch the epoch from "queue-held" to "already at borrower" before transferring funds.
    epochPendingDeposits[_epoch] = 0;
    epochPrefundedDeposits[_epoch] = _pending;
    IERC20Detailed(underlying).safeTransfer(_strategy.borrower(), _pending);
  }

  /// @notice delete a deposit request
  /// @param _requestEpoch epoch of the deposit request
  function deleteRequest(uint256 _requestEpoch) external {
    // if the epoch price is already set, deposits were already processed so
    // the deposit request can't be deleted.
    _checkNotAllowed(epochPrice[_requestEpoch] != 0 || epochPrefundedDeposits[_requestEpoch] != 0);

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
    _checkNotAllowed(epochWithdrawPrice[_requestEpoch] != 0);

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
    // only owner or strategy manager can process deposits
    _checkOnlyOwnerOrManager();
    // prefunded-enabled queues do not use the old buffer-period processing path
    _checkNotAllowed(_isPrefundedQueueEnabled());

    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    uint256 _epoch = IdleCreditVault(strategy).epochNumber();
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

  /// @notice Process deposits for prefunded flow (called atomically from stopEpoch on prefunded variant)
  /// @param _epoch epoch being finalized for the prefunded queue
  /// @param _prefundedMinted tranche tokens minted in CDO for prefunded amount
  function processPrefundedDeposits(uint256 _epoch, uint256 _prefundedMinted) external {
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    _checkNotAllowed(
      // final prefunded settlement is driven only by stopEpoch on the prefunded variant
      msg.sender != idleCDOEpoch ||
      // prefunded flow is supported only for AA queue
      tranche != _cdo.AATranche() ||
      // queue must be explicitly enabled on the prefunded CDO variant
      !_isPrefundedQueueEnabled()
    );

    // in prefunded mode stopEpoch must not leave queue-held deposits behind
    // and must pass the minted tranche amount for the prefunded funds
    _checkNotAllowed(epochPendingDeposits[_epoch] != 0 || _prefundedMinted == 0);
    // save epoch price for the prefunded deposits based on underlyings deposited and tranche tokens minted
    epochPrice[_epoch] = epochPrefundedDeposits[_epoch] * ONE_TRANCHE / _prefundedMinted;
    epochPrefundedDeposits[_epoch] = 0;
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
    _checkOnlyOwnerOrManager();
    // we revert if the are claims that needs to be processed
    _checkNotAllowed(pendingClaims);

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
    _checkOnlyOwnerOrManager();

    uint256 _pending = epochPendingClaims[_epoch];
    if (_pending == 0) {
      return;
    }
    uint256 _balPre = IERC20Detailed(underlying).balanceOf(address(this));

    // check if the epoch is an instant withdraw epoch.
    // These calls will transfer underlyings to this contract and burn strategyTokens
    if (isEpochInstant[_epoch]) {
      _cdo.claimInstantWithdrawRequest();
    } else {
      _cdo.claimWithdrawRequest();
    }
    uint256 _received = IERC20Detailed(underlying).balanceOf(address(this)) - _balPre;
    // In APR=0 flow the final claimed amount can differ from request-time pending claims.
    // Rebase the withdraw price to the realized amount so users claim the correct final value.
    if (_received != _pending) {
      uint256 _updatedPrice = epochWithdrawPrice[_epoch] * _received / _pending;
      if (_updatedPrice == 0) {
        revert Is0();
      }
      epochWithdrawPrice[_epoch] = _updatedPrice;
    }

    // reset epoch pending claims
    epochPendingClaims[_epoch] = 0;
    // reset pending claims flag
    pendingClaims = false;
  }

  /// @notice claim deposit request
  /// @param _epoch epoch of the deposit request
  function claimDepositRequest(uint256 _epoch) external {
    // Deposits can be claimed only after the epoch has been finalized and priced.
    _checkNotAllowed(
      epochPrice[_epoch] == 0 ||
      epochPendingDeposits[_epoch] != 0 ||
      epochPrefundedDeposits[_epoch] != 0
    );

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
    _checkNotAllowed(epochWithdrawPrice[_epoch] == 0 || epochPendingClaims[_epoch] != 0);
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
    _checkNotAllowed(!cdoEpoch.isWalletAllowed(wallet));
  }

  /// @notice check if the caller is owner or strategy manager
  function _checkOnlyOwnerOrManager() internal view {
    _checkNotAllowed(msg.sender != owner() && msg.sender != IdleCreditVault(strategy).manager());
  }

  /// @notice check if a condition is not allowed
  /// @param condition boolean condition to check
  function _checkNotAllowed(bool condition) internal pure {
    if (condition) {
      revert NotAllowed();
    }
  }

  /// @notice check if this queue is enabled as prefunded queue in cdo variant
  function _isPrefundedQueueEnabled() internal view returns (bool _isEnabled) {
    // Non-prefunded variants do not expose `epochQueue()`, so treat that case as disabled.
    try IdleCDOEpochVariantPrefunded(idleCDOEpoch).epochQueue() returns (address _epochQueue) {
      _isEnabled = _epochQueue == address(this);
    } catch {}
  }
}
