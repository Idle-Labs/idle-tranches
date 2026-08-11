// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDOCreditVault} from "./IdleCDOCreditVault.sol";
import {IKeyring} from "./interfaces/keyring/IKeyring.sol";
import {IProgrammableBorrower} from "./interfaces/IProgrammableBorrower.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

error NotAllowed();

/// @title IdleCDO variant that supports epochs. 
/// @dev When epoch is running no deposits or withdrawals are allowed. When epoch ends 
/// lenders can request withdrawals, that will be fullfilled by the end of the next epoch.
/// If the apr for the new epoch is lower than the last one, lenders can request 'instant' 
/// withdrawals that will be fullfilled when the epoch starts and after instantWithdrawDelay (3 days).
/// Funds for instant and normal withdrawals are sent to the strategy contract (IdleCreditVault)
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract IdleCDOEpochVariant is IdleCDOCreditVault {
  /// @notice flag to check if epoch is running
  bool public isEpochRunning;
  /// @notice flag to allow AA withdraw requests
  bool public allowAAWithdrawRequest;
  /// @notice flag to allow BB withdraw requests
  bool public allowBBWithdrawRequest;
  /// @notice duration of the epoch
  uint256 public epochDuration;
  /// @notice delay to allow instant withdraw requests after next epoch starts
  uint256 public instantWithdrawDelay;
  /// @notice expected interest for the current epoch
  uint256 public expectedEpochInterest;
  /// @notice end date of the current epoch
  uint256 public epochEndDate;
  /// @notice deadline to allow instant withdraw requests
  uint256 public instantWithdrawDeadline;
  /// @notice apr of the last epoch, unscaled
  uint256 public lastEpochApr;
  /// @notice min apr change to trigger instant withdraw
  uint256 public instantWithdrawAprDelta;
  /// @notice fees from pending withdraw request for the curr epoch
  uint256 public pendingWithdrawFees;
  /// @notice net underlyings gained last epoch
  uint256 public lastEpochInterest;
  /// @notice flag to allow instant withdraws
  bool public allowInstantWithdraw;
  /// @notice flag to completely disable instant withdraw
  bool public disableInstantWithdraw;
  /// @notice flag to check if borrower defaulted
  bool public defaulted;
  /// @notice Keyring wallet checker address
  address public keyring;
  /// @notice keyring policyId
  uint256 public keyringPolicyId;
  /// @notice time between 2 epochs, can be set to 0 to start the next epoch without waiting a specified time
  uint256 public bufferPeriod;
  /// @dev Deprecated storage slot. Do not remove: kept to preserve the upgradeable storage layout.
  bool internal keyringAllowWithdraw;
  /// @notice amount of over/under performance that withdrawal requests will cause
  int256 internal interestForOverUnderPerformance;
  /// @notice flag to disable deposits during an epoch
  bool public isDepositDuringEpochDisabled;
  /// @notice flag to mint interest as strategy tokens without moving underlyings
  bool public isInterestMinted;

  event AccrueInterest(uint256 interest, uint256 fees);
  event BorrowerDefault(uint256 funds);

  function _additionalInit() internal virtual override {
    // all yield to senior
    isAYSActive = false;

    // set epoch params
    epochDuration = 30 days;
    bufferPeriod = 5 days;
    // we set epochEndDate to avoid issues with the first epoch, so we set
    // it to current time minus bufferPeriod so that the first epoch can start right away
    epochEndDate = block.timestamp - 5 days;

    // allow requests for withdrawals
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;

    // default no instant withdraw allowed
    disableInstantWithdraw = true;

    // by default deposits during an epoch are disabled
    isDepositDuringEpochDisabled = true;

    // scale the apr to include the buffer period
    _setScaledApr(_getStrategyApr());
  }

  /// @notice Check if msg sender is owner or manager
  function _checkOnlyOwnerOrManager() internal view {
    _checkNotAllowed(msg.sender != owner() && msg.sender != IdleCreditVault(strategy).manager());
  }

  /// @notice Revert if condition is true
  /// @param _revertCondition condition to check
  function _checkNotAllowed(bool _revertCondition) internal pure {
    if (_revertCondition) revert NotAllowed();
  }

  /// @notice Ensure programmable borrowers are only used with minted-interest accounting.
  /// @dev Programmable borrower flows assume minted interest and do not support instant funding.
  function _checkProgrammableBorrowerMode() internal view {
    _checkNotAllowed(isProgrammableBorrower && (!isInterestMinted || _pendingInstant() != 0));
  }

  ///
  /// Only owner or manager methods 
  ///

  /// @notice update epoch duration
  /// @dev IMPORTANT: bufferPeriod should not be changed once set otherwise interest calculations will be wrong
  /// @param _epochDuration duration in seconds
  /// @param _bufferPeriod time between 2 epochs
  function setEpochParams(uint256 _epochDuration, uint256 _bufferPeriod) public {
    _checkOnlyOwnerOrManager();
    // cannot set epoch params if epoch is running
    // cannot set epochDuration to 0 as it's reserved for closing the pool
    // and cannot set epochDuration if previously was set to 0 as borrower repaid all funds
    _checkNotAllowed(defaulted || isEpochRunning || _epochDuration == 0 || epochDuration == 0);
    epochDuration = _epochDuration;
    bufferPeriod = _bufferPeriod;
  }

  /// @notice update instant withdraw params
  /// @param _delay delay in seconds
  /// @param _aprDelta min apr delta to trigger instant withdraw
  /// @param _disable flag to disable instant withdraw
  function setInstantWithdrawParams(uint256 _delay, uint256 _aprDelta, bool _disable) public virtual {
    _checkOnlyOwnerOrManager();
    _checkNotAllowed(paused());
    instantWithdrawDelay = _delay;
    instantWithdrawAprDelta = _aprDelta;
    disableInstantWithdraw = _disable;
  }

  /// @notice update keyring address
  /// @param _keyring address of the keyring contract
  /// @param _keyringPolicyId policyId to check for wallet
  function setKeyringParams(address _keyring, uint256 _keyringPolicyId) external {
    _checkOnlyOwnerOrManager();
    keyring = _keyring;
    keyringPolicyId = _keyringPolicyId;
  }

  /// @notice set flag to disable deposits during an epoch
  /// @param _isDisabled true to disable deposits during an epoch
  function setIsDepositDuringEpochDisabled(bool _isDisabled) external {
    _checkOnlyOwnerOrManager();
    isDepositDuringEpochDisabled = _isDisabled;
  }

  /// @notice Skim raw donated underlyings before forcing accounting.
  /// @dev Prevents unsolicited transfers from being crystallized as tranche gains by manual accounting.
  function updateAccounting() external override {
    _checkOnlyOwnerOrGuardian();
    _skimDonatedAssets();
    _forceUpdateAccounting();
  }

  /// @notice set flag to mint interest as strategy tokens without moving underlyings
  /// @dev Programmable borrowers always require minted-interest accounting.
  /// @param _isMinted true to mint interest instead of transferring underlyings
  function setIsInterestMinted(bool _isMinted) external {
    _checkOnlyOwner();
    _checkNotAllowed(!_isMinted && isProgrammableBorrower);
    isInterestMinted = _isMinted;
  }

  /// @notice Set whether the current strategy borrower should be treated as programmable.
  /// @dev This is configured explicitly instead of inferring from code size so contract borrowers
  /// such as Safe wallets are not misclassified. The flag cannot be changed while an epoch is live.
  /// @param _isProgrammable true to enable programmable-borrower hooks and accounting
  function setIsProgrammableBorrower(bool _isProgrammable) external {
    _checkOnlyOwner();
    _checkNotAllowed(isEpochRunning);
    isProgrammableBorrower = _isProgrammable;
  }

  /// @notice Finalize a hard-default recovery and crystallize the realized loss on tranche prices.
  /// @dev `_recoverySource` must approve the strategy for `_recoveredAmount`. Recovered funds are sent
  /// directly to the strategy recovery reserve so they do not inflate CDO NAV before finalization.
  /// Finalization is one-time and cannot be topped up through this recovery path. Any raw underlying
  /// held by the CDO is treated as a donation and sent to `feeReceiver` before recovery is calculated.
  /// Recovery uses one aggregate multiplier and does not preserve AA seniority. Before applying
  /// that multiplier, active gross backing is split by saved NAV and active default interest uses
  /// the configured AA/BB APR split, matching the tranche-specific interest in fixed-APR receipts.
  /// A zero or subprecision aggregate recovery finalizes at price zero so tranche prices expose the
  /// full loss and pending receipts can be cleared without a payout.
  /// @param _recoveredAmount amount of underlying recovered for active LPs and defaulted receipts
  /// @param _recoverySource address that supplies the recovered underlying
  function finalizeDefault(uint256 _recoveredAmount, address _recoverySource) external {
    _checkOnlyOwnerOrManager();
    // Send raw CDO underlying to feeReceiver as donated assets; recovery must enter through the strategy.
    _skimDonatedAssets();
    // Recovery math and reserve accounting live in the strategy where receipt claims are paid.
    uint256 defaultBBNav = IdleCreditVault(strategy).finalizeDefaultRecovery(_recoveredAmount, _recoverySource);

    // Default recovery should not keep accruing fees or leave old fee claims senior to LP recovery.
    fee = 0;
    managementFee = 0;
    unclaimedFees = 0;
    latestHarvestBlock = block.timestamp;

    // The strategy returns BB's final recovered active NAV. Writing both final NAVs directly
    // makes hard default the sole exception to the ordinary BB-first loss waterfall.
    lastNAVBB = defaultBBNav;
    lastNAVAA = _contractTokenBalance(strategyToken) - defaultBBNav;

    // Crystallize the strategy-token rebalance so virtualPrice/tranchePrice expose the realized loss.
    _forceUpdateAccounting();

    expectedEpochInterest = 0;
    pendingWithdrawFees = 0;
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;
    // This flag gates claimInstantWithdrawRequest. New instant requests stay disabled below.
    allowInstantWithdraw = true;
    disableInstantWithdraw = true;
    epochDuration = 0;
    epochEndDate = 0;
    _setScaledApr(0);
  }

  /// @notice Start the epoch. No deposits or withdrawals are allowed after this.
  /// @dev We calculate the total funds that the borrower should return at the end of the epoch
  /// ie interests + fees from normal withdraw requests. We send to the borrower underlyings amounts ie interests + 
  /// new deposits - instant withdraw requests if any. If funds are not enough to satisfy all requests
  /// then borrower should return the difference before instantWithdrawDeadline. After epoch start there
  /// should be no underlyings in this contract
  function startEpoch() external {
    _checkOnlyOwnerOrManager();

    // Check that buffer period passed (and epoch is not running as epochEndDate is set)
    // and that the pool is not closed (ie epochDuration == 0)
    uint256 _epochDuration = epochDuration; 
    _checkNotAllowed(defaulted || block.timestamp < (epochEndDate + bufferPeriod) || _epochDuration == 0);
    _checkProgrammableBorrowerMode();
    // Remove raw donated underlyings before calculating epoch interest or borrower transfer amounts.
    _skimDonatedAssets();

    isEpochRunning = true;
    // prevent deposits
    _pause();

    // prevent withdrawals requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;

    IdleCreditVault _strategy = IdleCreditVault(strategy);

    // calculate expected interest 
    // NOTE: all withdrawal requests, burn tranche tokens and decrease getContractValue,
    // this can be done only prior to the start of the epoch so getContractValue() is the total amount net
    // of all withdrawal requests. We add the fee that we should get for normal pending withdraws
    // we also add/remove the over/under performance caused by withdraw requests.
    // Pending fees remain due even if fixed-APR requests exhaust active interest.
    int256 adjustedActiveInterest = int256(_calcInterest(getContractValue())) + interestForOverUnderPerformance;
    if (adjustedActiveInterest < 0) adjustedActiveInterest = 0;
    expectedEpochInterest = pendingWithdrawFees + uint256(adjustedActiveInterest);
    interestForOverUnderPerformance = 0;

    // set expected epoch end date
    epochEndDate = block.timestamp + _epochDuration;
    // set instant withdraw deadline
    instantWithdrawDeadline = block.timestamp + instantWithdrawDelay;

    // transfer in this contract funds from interest payment (if any) and buffer deposits sent to the strategy
    uint256 _totEpochDeposits = _strategy.totEpochDeposits();
    // If interest is minted we do not transfer interest to the strategy
    uint256 _toSend = isInterestMinted ? _totEpochDeposits : lastEpochInterest + _totEpochDeposits;
    if (_toSend != 0) {
      _strategy.sendInterestAndDeposits(_toSend);
    }

    // we should first check if there are *instant* redeem requests pending 
    // and if yes we should send as much underlyings as possible to the IdleCreditVault contract
    // if there is any surplus then we send those to the borrower
    uint256 pendingInstant = _pendingInstant();
    uint256 totUnderlyings = _contractTokenBalance(token);
    uint256 _pendingWithdraws = _strategy.pendingWithdraws();
    _strategy.collectInstantWithdrawFunds(pendingInstant > totUnderlyings ? totUnderlyings : pendingInstant);

    // if there are more requests than the current underlyings we simply send all underlyings
    // to the IdleCreditVault contract
    if (pendingInstant > totUnderlyings) {
      // if borrower is programmable, notify epoch start even if no funds were sent
      _startEpochProgrammableBorrower(_pendingWithdraws);
      return;
    }
    // allow instant withdraws right away without waiting for the deadline
    allowInstantWithdraw = true;
    // and transfer the surplus to the borrower
    uint256 _toBorrower = totUnderlyings - pendingInstant;
    try this.sendFundsToBorrower(_toBorrower) {
      // funds transferred correctly
      _startEpochProgrammableBorrower(_pendingWithdraws);
    } catch {
      // The borrower did not receive the funds, so keep the strategy-token backing in the strategy.
      _transferUnderlyings(address(_strategy), _toBorrower);
      _strategy.reserveDefaultRecovery(_toBorrower);
      _handleBorrowerDefault(_toBorrower);
    }
  }

  /// @notice workaround to have safeTransfer to borrower as external and use it in a try/catch block
  /// @param _amount Amount of underlyings to transfer
  function sendFundsToBorrower(uint256 _amount) external {
    _checkNotAllowed(msg.sender != address(this));
    _transferUnderlyings(_borrower(), _amount);
  }

  /// @notice Stop epoch, accrue interest to the vault and get funds to fullfill normal
  /// (ie non-instant) withdraw requests from the prev epoch.
  /// @param _newApr New apr to set for the next epoch
  /// @param _interest Interest gained in the epoch. This will overwrite the expected interest
  /// must be 0 if there is no need to overwrite the expected interest and if > 0 then it should
  /// be greater than the pending withdraw fees and newApr must be 0. If `_interest` is 1 then
  /// it is interpreted as a special case where we request everything back from the borrower.
  /// Programmable borrowers only support `_interest` values `0` and `1`.
  /// @dev Only owner or manager can call this function. Borrower MUST approve this contract
  function stopEpoch(uint256 _newApr, uint256 _interest) public {
    _stopEpoch(_newApr, _interest, 0);
  }

  /// @notice Internal stop-epoch implementation with optional proportional pending-receipt loss.
  /// @param _newApr New apr to set for the next epoch
  /// @param _interest Interest gained in the epoch
  /// @param _lossAmount Loss amount to split between active LPs and pending receipts
  function _stopEpoch(uint256 _newApr, uint256 _interest, uint256 _lossAmount) private {
    _checkOnlyOwnerOrManager();
    bool _isRequestingAllFunds = _interest == 1;
    _checkProgrammableBorrowerMode();

    IdleCreditVault _strategy = IdleCreditVault(strategy);
    uint256 _pendingWithdrawFees = pendingWithdrawFees;

    _checkNotAllowed(
      // Check that epoch is running
      !isEpochRunning || 
      // Check that end date is passed
      block.timestamp < epochEndDate || 
      // Check that there are no pending instant withdraws, ie `getInstantWithdrawFunds` was called
      // before closing the epoch
      _pendingInstant() != 0 ||
      // Check that overridden interest, if passed (ie > 1), is greater than pending withdraw fees and the apr is 0 
      // otherwise withdrawal requests may not be fullfilled as they consider also the interest gained in the next epoch 
      (_interest > 1 && (_interest < _pendingWithdrawFees || _newApr != 0)) ||
      // Closing already recalls all principal, so applying a separate loss burn would strand returned cash.
      (_isRequestingAllFunds && _lossAmount != 0)
    );

    uint256 _totBorrowed = _beforeStopEpoch(_isRequestingAllFunds);
    // we check if there are donated assets to the pool and transfer them to the feeReceiver if any
    _skimDonatedAssets();

    _interest = _resolveStopEpochInterest(_interest);

    // Base interest for stopEpoch: explicit override (>1) or precomputed expected epoch interest.
    uint256 _expectedInterest;
    // Strategy finalizes APR0 bucket state and returns adjusted stopEpoch values.
    (_expectedInterest, _pendingWithdrawFees) = _strategy.prepareStopEpochWithApr0(_interest);
    // Pending withdraws may be increased during APR0 settlement, so read after prepareStopEpochWithApr0.
    uint256 _pendingWithdraws = _strategy.pendingWithdraws();

    // special case where we get everything back from the borrower
    if (_isRequestingAllFunds) {
      // Recall gross strategy-token principal, including fee backing excluded from net CDO NAV.
      // Prefunded variants also add queue deposits already sent directly to the borrower.
      _totBorrowed += _contractTokenBalance(strategyToken);
      _expectedInterest += _totBorrowed;
    }
    uint256 _grossInterest = _isRequestingAllFunds ? _expectedInterest - _totBorrowed : _expectedInterest;
    bool _mintInterest = isInterestMinted && !_isRequestingAllFunds;
    // In minted mode IdleCDO only needs cash for withdraw requests, not for epoch interest itself.
    uint256 _amountToPullFromBorrower = _mintInterest ? 0 : _expectedInterest;
    if (_mintInterest && _interest > 1) {
      uint256 _maxApr = _strategy.maxApr();
      _checkNotAllowed(_maxApr != 0 && _grossInterest > _calcInterestWithApr(getContractValue(), _maxApr) + _pendingWithdrawFees);
    }

    // Checkpoint management fees before borrower funds are pulled in so the elapsed-period
    // accrual applies only to the pre-stop live NAV, not to newly received epoch interest.
    _accrueManagementFee();

    // Persist only resolved epoch interest for recovery accounting. In close-pool mode `_interest == 1`
    // is a sentinel: `_grossInterest` excludes the principal added to `_expectedInterest` above.
    expectedEpochInterest = _grossInterest;
    pendingWithdrawFees = _pendingWithdrawFees;

    // Pending receipts have no tranche identity, so their aggregate loss is pro rata across all
    // receipts. The remaining active loss is applied BB-first after the stop succeeds.
    (_pendingWithdraws, _lossAmount) = _strategy.previewLossAdjustedWithdrawFunds(_lossAmount);

    if (isProgrammableBorrower) {
      // Ask the programmable borrower to recall ERC4626 liquidity before IdleCDO pulls funds.
      // Hook reverts bubble so transient ERC4626 liquidity failures can be retried.
      if (!IProgrammableBorrower(_borrower()).onStopEpoch(_amountToPullFromBorrower + _pendingWithdraws, _isRequestingAllFunds)) {
        // Emit the exact cash liability requested from the borrower, including recalled principal
        // in close-pool mode and excluding interest fronted through minted accounting.
        _handleBorrowerDefault(_amountToPullFromBorrower + _pendingWithdraws);
        return;
      }
    }

    // accrue interest to idleCDO, this will increase tranche prices.
    // Send also tot withdraw requests amount to the IdleCreditVault contract
    try this.getFundsFromBorrower(_amountToPullFromBorrower + _pendingWithdraws) {
      // transfer in strategy and decrease pendingWithdraws
        _strategy.collectWithdrawFunds(_pendingWithdraws);
      // Only settle borrower interest when CDO is fronting it (minted mode, not closing pool).
      // When requesting all funds (_interest == 1) the CDO pulls cash directly, no fronting.
      if (_mintInterest && isProgrammableBorrower) {
        IProgrammableBorrower(_borrower()).settleBorrowerInterest();
      }
      // Split pending withdraw fees before update accounting
      // NOTE: Fees are sent with 2 different transfer calls, here and after updateAccounting, to avoid complicated calculations
      if (!_mintInterest) {
        _transferFeeUnderlyings(_pendingWithdrawFees);
      }

      if (_isRequestingAllFunds) {
        // we already have strategyTokens equal to _totBorrowed in this contract
        // so we transfer _totBorrowed to the strategy to avoid double counting for getContractValue
        _transferUnderlyings(address(_strategy), _totBorrowed);
      }

      if (_mintInterest) {
        // if interest is not transferred we mint strategy tokens equal to the full epoch interest
        if (_grossInterest != 0) _strategy.mintStrategyTokens(_grossInterest);
        // and increase unclaimedFees by pending withdraw fees before _updateAccounting
        unclaimedFees += _pendingWithdrawFees;
      }

      // update tranche prices and unclaimed fees
      _updateAccounting();

      // transfer fees
      uint256 _fees = unclaimedFees;
      if (_mintInterest) {
        // If interest is minted then we mint new shares for fee receivers instead of transferring underlyings
        if (_fees != 0) {
          uint256 feeReceiverAmount = _feeReceiverAmount(_fees);
          if (feeReceiverAmount != 0) {
            _mintSharesAtCurrPrice(feeReceiverAmount, feeReceiver, AATranche);
          }
          _mintSharesAtCurrPrice(_fees - feeReceiverAmount, owner(), AATranche);
          _updateSplitRatio(_getAARatio(true));
        }
      } else {
        // Cash-funded fees can only use gross interest not already owed to pending withdrawals.
        uint256 _availableForFees = _grossInterest > _pendingWithdrawFees ? _grossInterest - _pendingWithdrawFees : 0;
        if (_fees > _availableForFees) {
          _fees = _availableForFees;
        }
        _transferFeeUnderlyings(_fees);
      }
      // Any fee that cannot be paid in cash remains accrued and continues reducing NAV.
      unclaimedFees -= _fees;

      uint256 _totalFees = _fees + (_mintInterest ? 0 : _pendingWithdrawFees);
      // save net gain (this does not include interest gained for pending withdrawals)
      uint256 netInterest = _grossInterest > _totalFees ? _grossInterest - _totalFees : 0;
      lastEpochInterest = netInterest;
      // mint strategyTokens equal to interest and send underlying to strategy to avoid double counting for NAV
      _strategy.deposit(_mintInterest ? 0 : netInterest);

      // save last apr, unscaled
      lastEpochApr = _strategy.unscaledApr();
      // set apr for next epoch
      _setScaledApr(_newApr);

      // stop epoch
      isEpochRunning = false;
      expectedEpochInterest = 0;
      pendingWithdrawFees = 0;

      if (!skipDefaultCheck) {
        // Reopen ordinary deposits and requests only when operations were not explicitly shut down.
        _unpause();
        allowAAWithdrawRequest = true;
        allowBBWithdrawRequest = true;
      }
      // block instant withdraws claims as these can be done only after the deadline
      // or only if borrower is repaying all funds
      allowInstantWithdraw = _isRequestingAllFunds;

      if (_isRequestingAllFunds) {
        // user will request only normal withdraw and can claim right after
        disableInstantWithdraw = true;
        epochDuration = 0;
        epochEndDate = 0;
      }

      emit AccrueInterest(_expectedInterest - _totBorrowed, _totalFees);
      if (_lossAmount != 0) {
        _strategy.burnStrategyTokens(_lossAmount);
        // Realize the active loss immediately through the ordinary BB-first waterfall.
        _forceUpdateAccounting();
      }
    } catch {
      // if borrower defaults, prev instant withdraw requests can still be withdrawn
      // as were already fullfilled prior to the default (all funds already sent to the strategy)
      _handleBorrowerDefault(_amountToPullFromBorrower + _pendingWithdraws);
    }
  }

  /// @notice Stop epoch and set new duration
  /// @dev see stopEpoch and setEpochParams for more details, bufferPeriod is not modified
  /// Loss accounting policy for `_lossAmount`:
  /// - pending receipts share the pending portion of the loss pro rata because tranche identity is not stored
  /// - the remaining active-position loss uses the ordinary BB-first tranche waterfall
  /// - hard borrower defaults instead apply one aggregate recovery multiplier to active and pending claims
  /// - if `stopEpoch` defaults (`defaulted = true`), the post-stop loss burn and epoch updates are skipped,
  ///   but variant hooks still run so prefunded queues can settle deposits already sent to the borrower
  /// @param _newApr New apr to set for the next epoch
  /// @param _interest Interest gained in the epoch
  /// @param _duration New epoch duration
  /// @param _lossAmount Amount of strategy tokens to burn as realized loss
  function stopEpochWithDuration(uint256 _newApr, uint256 _interest, uint256 _duration, uint256 _lossAmount) public {
    // stop epoch checks that msg.sender is allowed
    _stopEpoch(_newApr, _interest, _lossAmount);
    if (_interest != 1 && !defaulted) {
      // buffer period is not changed
      setEpochParams(_duration, bufferPeriod);
      // scale the apr with the new duration and buffer
      _setScaledApr(_newApr);
    }
    _afterStopEpochWithDuration();
  }

  /// @notice Hook called before stopping an epoch.
  /// @dev The base variant has no external principal and returns zero. The prefunded variant
  /// overrides this hook to guard direct stops and include principal already sent to the borrower.
  /// @param _isClosing true when this stop recalls all pool principal
  /// @return additionalPrincipal principal held outside the CDO strategy-token balance
  function _beforeStopEpoch(bool _isClosing) internal view virtual returns (uint256) {
    _isClosing;
    return 0;
  }

  /// @notice internal function called in stop epoch with duration after doing anything else
  function _afterStopEpochWithDuration() internal virtual {}

  /// @notice Set the scaled apr for the next epoch
  /// @param _newApr New apr to set for the next epoch
  function _setScaledApr(uint256 _newApr) internal {
    IdleCreditVault(strategy).setAprsWithBuffer(_newApr, epochDuration, bufferPeriod);
  }

  /// @dev Get funds from borrower through an external self-call so callers can use try/catch.
  /// @param _amount Total amount to transfer
  function getFundsFromBorrower(uint256 _amount) external {
    _checkNotAllowed(msg.sender != address(this));
    _transferUnderlyingsFrom(_borrower(), address(this), _amount);
  }

  /// @notice Get funds from borrower to fullfill instant withdraw requests
  /// Manager should call this method after instantWithdrawDeadline (when epoch is running)
  /// @dev Instant withdrawals are not supported when a programmable borrower is configured.
  function getInstantWithdrawFunds() external {
    _checkOnlyOwnerOrManager();
    // Check that programmable mode is disabled, the epoch is running and the deadline passed.
    _checkNotAllowed(isProgrammableBorrower || !isEpochRunning || block.timestamp < instantWithdrawDeadline);

    IdleCreditVault _strategy = IdleCreditVault(strategy);
    uint256 _instantWithdraws = _pendingInstant();
    // transfer funds for instant withdraw to this contract
    try this.getFundsFromBorrower(_instantWithdraws) {
      // transfer funds to IdleCreditVault and decrease pendingInstantWithdraws
      if (_instantWithdraws != 0) {
        _strategy.collectInstantWithdrawFunds(_instantWithdraws);
      }
      // allow instant withdraws
      allowInstantWithdraw = true;
    } catch {
      _handleBorrowerDefault(_instantWithdraws);
    }
  }

  /// @notice Handle borrower default
  function _handleBorrowerDefault(uint256 funds) internal {
    defaulted = true;
    // Do not reopen instant claims here. They remain disabled when funding is pending;
    // successful full funding is the only path that enables them before finalization.

    if (isProgrammableBorrower) {
      IProgrammableBorrower(_borrower()).onDefault();
    }

    // deposits should be already prevented
    if (!paused()) {
      _pause();
    }

    // stop the current epoch
    isEpochRunning = false;

    // prevent withdrawals requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;

    emit BorrowerDefault(funds);
  }

  /// @notice Prevent deposits and redeems for all classes of tranches
  function _emergencyShutdown(bool isAAWithdrawAllowed) internal override {
    // prevent deposits
    if (!paused()) {
      _pause();
    }
    // Preserve AA requests only if they were already open. This keeps a forced mid-epoch loss or
    // prior emergency from reopening them, while a normal explicit-loss stop can leave them open.
    if (!isAAWithdrawAllowed) {
      allowAAWithdrawRequest = false;
    }
    allowBBWithdrawRequest = false;
    // Persist the emergency state and let authorized forced accounting crystallize the loss.
    skipDefaultCheck = true;
  }

  /// @notice allow deposits and redeems for all classes of tranches
  /// @dev can be called by the owner only
  function restoreOperations() external override {
    _checkOnlyOwner();
    // Check if the pool was defaulted
    _checkNotAllowed(defaulted || priceAA == 0);
    skipDefaultCheck = false;
    // During an epoch ordinary deposits and withdrawal requests must remain disabled. Clearing
    // the emergency flag intentionally restores only the dedicated depositDuringEpoch path.
    if (isEpochRunning) return;
    if (paused()) {
      _unpause();
    }
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;
  }

  /// @notice Prevent external unpause while an epoch, emergency shutdown, or hard default is active.
  function _beforeUnpause() internal view override {
    _checkNotAllowed(defaulted || isEpochRunning || skipDefaultCheck);
  }

  /// 
  /// User methods
  ///

  /// @notice Deposit funds in the vault. Overrides the parent method and adds a check for wallet 
  function _deposit(uint256 _amount, address _tranche) internal override whenNotPaused returns (uint256) {
    _checkNotAllowed(!isWalletAllowed(msg.sender));
    // we check if there are donated assets to the pool and transfer them to the feeReceiver if any
    _skimDonatedAssets();
    // do the inherited deposit flow
    return super._deposit(_amount, _tranche);
  }

  /// @notice Deposit during an active epoch with prorated interest
  /// @param _amount Amount of underlyings
  /// @param _tranche Tranche to deposit into
  /// @return _minted Amount of tranche tokens minted
  function depositDuringEpoch(uint256 _amount, address _tranche) external virtual returns (uint256 _minted) {
    _checkTranche(_tranche);
    _checkNotAllowed(
      isDepositDuringEpochDisabled ||
      skipDefaultCheck ||
      // programmable borrowers use APR=0 so mid-epoch deposits would dilute existing depositors
      isProgrammableBorrower ||
      // check if AYS is active as we don't support deposits during epoch in that case
      isAYSActive ||
      // check if epoch is still running even if not manually stopped yet
      !isEpochRunning || block.timestamp >= epochEndDate ||
      !isWalletAllowed(msg.sender)
    );

    if (_amount == 0) {
      return _minted;
    }

    uint256 _trancheTotSupply = _trancheSupply(_tranche);
    // Avoid pricing discontinuities for the first mid-epoch deposit in a tranche
    _checkNotAllowed(_trancheTotSupply == 0);

    _skimDonatedAssets();
    // Check that limit is not exceeded after removing skimmable raw donations.
    _guarded(_amount);
    _updateAccounting();

    // Get underlyings from user
    _transferUnderlyingsFrom(msg.sender, address(this), _amount);

    // interest for the remaining epoch plus the full buffer period
    // NOTE: _calcInterest already gives full‑epoch + full‑buffer interest for the whole epoch
    //   So when a user joins mid‑epoch, we take the fraction of that full‑period interest 
    //   that matches the time they actually remain plus the entire buffer
    uint256 buffer = bufferPeriod;
    uint256 remaining = epochEndDate - block.timestamp;
    uint256 interest = _calcInterest(_amount) *
      // the time the depositor actually participates (remaining epoch + full buffer)
      (remaining + buffer) /
      // the total time baked into the scaled APR (epoch + buffer).
      (epochDuration + buffer);

    uint256 expectedInt = expectedEpochInterest;
    uint256 pendingFees = pendingWithdrawFees;
    uint256 trancheExpected;
    // existing holders' share of net expected interest for the epoch (pre-deposit)
    // (exclude pendingWithdrawFees since they go to fee receivers, not tranche holders)
    if (expectedInt > pendingFees) {
      trancheExpected = _calcTrancheInterestShare(
        _netGainAfterFees(expectedInt - pendingFees, _calculateManagementFee(lastNAVAA + lastNAVBB, remaining)),
        _tranche
      );
    }
    // interest this deposit will earn for the tranche over the remaining time (net of fees)
    uint256 trancheInterest = _calcTrancheInterestShare(
      _netGainAfterFees(interest, _calculateManagementFee(_amount, remaining)),
      _tranche
    );
    // pre-deposit expected final NAV for existing holders.
    // This won't ever be zero as we checked _trancheTotSupply and we seed initial NAV at tranche creation
    uint256 expectedFinal = _lastSavedNAV(_tranche) + trancheExpected;

    // mint at a discounted price so depositor gets principal + its prorated interest at epoch end
    // A mid‑epoch depositor should get _amount + trancheInterest at epoch end.
    // So they need minted = (amount + trancheInterest) / priceEnd.
    // priceEnd = expectedFinal / _trancheTotSupply
    // so minted = (amount + trancheInterest) * _trancheTotSupply / expectedFinal
    _minted = (_amount + trancheInterest) * _trancheTotSupply / expectedFinal;
    _mintShares(_tranche, msg.sender, _minted, _amount);

    // update expected epoch interest
    expectedEpochInterest += interest;
    // mint strategy tokens to this contract
    IdleCreditVault(strategy).mintStrategyTokens(_amount);
    // transfer underlyings to the borrower
    _transferUnderlyings(_borrower(), _amount);
  }

  /// @notice Request a withdraw from the vault
  /// @param _amount Amount of tranche tokens 
  /// @param _tranche Tranche to withdraw from
  /// @return _underlyings Amount of underlyings requested
  function requestWithdraw(uint256 _amount, address _tranche) external returns (uint256 _underlyings) {
    _checkTranche(_tranche);
    _checkNotAllowed(
      (_tranche == AATranche ? !allowAAWithdrawRequest : !allowBBWithdrawRequest) ||
      !isWalletAllowed(msg.sender)
    );
  
    // we check if there are donated assets to the pool and transfer them to the feeReceiver if any
    _skimDonatedAssets();

    // we trigger an update accounting to check for eventual losses
    _updateAccounting();

    IdleCreditVault creditVault = IdleCreditVault(strategy);
    if (_amount == 0) {
      _amount = _userTrancheBal(msg.sender, _tranche);
    }
    _underlyings = _trancheToUnderlyings(_amount, _tranche);

    // Programmable borrower deployments do not support instant withdrawals.
    // If apr decresed wrt last epoch, request instant withdraw and burn tranche tokens directly
    // we compare unscaled aprs
    if (_isInstantWithdrawEnabled()) {
      uint256 currentApr = creditVault.unscaledApr();
      if (lastEpochApr > (currentApr + instantWithdrawAprDelta)) {
        // burn strategy tokens from cdo and mint an equal amount to msg.sender as receipt
        creditVault.requestInstantWithdraw(_underlyings, msg.sender);
        // burn tranche tokens and decrease NAV
        _withdrawOps(_amount, _underlyings, _tranche);
        return _underlyings;
      }
    }

    uint256 principal = _underlyings;
    (uint256 interest, int256 diff) = _calcInterestWithdrawRequest(_underlyings, _tranche);
    uint256 totalFees = _totalWithdrawFees(principal, interest);
    // user is requesting principal + interest minus upfront management fee and net performance fee
    _underlyings = principal + interest - totalFees;
    // add expected fees to pending withdraw fees counter
    pendingWithdrawFees += totalFees;

    /// if there is an AA withdrawal the overperformance that the amount withdrawed would have generated for BB tranches
    /// is saved in interestForOverUnderPerformance. This is used to calculate the interest that should be added to the
    /// expectedEpochInterest at the startEpoch.
    /// If there is a BB withdrawal this amount is subtracted from the expectedEpochInterest
    interestForOverUnderPerformance += diff;

    // The receipt is fixed now and leaves live NAV. Charge management fees upfront
    // for the time it waits outside live NAV: remaining buffer plus the next epoch.
    creditVault.requestWithdraw(_underlyings, msg.sender, principal);
    // burn tranche tokens and decrease NAV without interest for the next epoch as it was not yet counted in NAV
    _withdrawOps(_amount, principal, _tranche);
  }

  /// @notice Transfer donated assets to the feeReceiver
  function _skimDonatedAssets() internal {
    _transferUnderlyings(feeReceiver, _contractTokenBalance(token));
  }

  /// @notice Calculate the interest of an epoch for the given amount
  /// @param _amount Amount of underlyings
  function _calcInterest(uint256 _amount) internal view returns (uint256) {
    return _calcInterestWithApr(_amount, _getStrategyApr());
  }

  /// @notice Calculate the interest of an epoch for the given amount and apr
  /// @param _amount Amount of underlyings
  /// @param _apr Apr used for the calculation
  function _calcInterestWithApr(uint256 _amount, uint256 _apr) internal view returns (uint256) {
    return _amount * (_apr / 100) * epochDuration / (365 days * ONE_TRANCHE_TOKEN);
  }

  /// @notice Get current tranches value
  /// @param _amount Amount of tranche tokens
  /// @param _tranche Tranche to get the value for
  /// @return Value of the tranche tokens in underlyings
  function _trancheToUnderlyings(uint256 _amount, address _tranche) internal view returns (uint256) {
    return _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice Revert unless an address is one of this vault's tranche tokens.
  /// @param _tranche tranche address to validate
  function _checkTranche(address _tranche) internal view {
    _checkNotAllowed(_tranche != AATranche && _tranche != BBTranche);
  }

  /// @notice Get borrower address from strategy.
  /// @return borrower address
  function _borrower() internal view returns (address) {
    return IdleCreditVault(strategy).borrower();
  }

  /// @notice Get pending instant withdraws from strategy.
  /// @return pending instant withdraws
  function _pendingInstant() internal view returns (uint256) {
    return IdleCreditVault(strategy).pendingInstantWithdraws();
  }

  /// @notice Return whether new requests may use instant-withdraw mode.
  /// @dev Child variants can permanently disable instant mode independently of legacy storage.
  function _isInstantWithdrawEnabled() internal view virtual returns (bool) {
    return !disableInstantWithdraw && !isProgrammableBorrower;
  }

  /// @notice Calculate the interest of an epoch for a withdraw request
  /// @dev to avoid having funds not getting interest during buffer period, the apr 
  /// set in the stopEpoch is higher than then intended one so it will cover also the buffer period
  /// eg epoch = 30 days, buffer = 5 days, then if we want to give 10% apr for all the 35 days then
  /// in stop epoch we set the apr to 10% * 35/30 = 11.67%. For this reason people who instead request
  /// a withdraw should not get the additional interest for the buffer period because they can withdraw
  /// a block after the buffer period starts. So we calculate the interest for the 30 days only,
  /// eg. if apr is set to 11.67% and we want to calculate the interest for 30 days at 10% we need to do the 
  /// the opposite -> 11.67% * 30/35 = 10%
  /// @param _amount Amount of underlyings
  /// @param _tranche Tranche to withdraw from
  /// @return _interest Interest for the given amount and given tranche
  /// @return _diff over/under performance that this withdraw will cause to the other tranche
  function _calcInterestWithdrawRequest(uint256 _amount, address _tranche) internal view returns (uint256 _interest, int256 _diff) {
    uint256 _duration = epochDuration;
    if (_duration == 0) {
      return (_interest, _diff);
    }

    uint256 _buffer = bufferPeriod;
    // calculate total vault interest (they don't get the interest for the buffer period for withdraw requests so 
    // we scale it back since _calcInterest is scaling the interest with tht buffer period),
    uint256 totInterest = _calcInterest(_managedContractValue()) * _duration / (_duration + _buffer);
    // calculate total tranche interest for the whole tranche supply
    uint256 totTrancheInterest = _calcTrancheInterestShare(totInterest, _tranche);
    // calculate interest for the given tranche and given amount
    uint256 _trancheBal = _lastSavedNAV(_tranche);
    _interest = _trancheBal == 0 ? 0 : _amount * totTrancheInterest / _trancheBal;
    // calculate the interest that the _amount would have received if there was no split ratio (ie interest split based only on tvl).
    // This is used to calculate the interest that should be added to the expectedEpochInterest when 
    // withdrawing an AA tranche or the interest that should be removed from expectedEpochInterest when
    // withdrawing a BB tranche
    uint256 interestWithoutSplitRatio = _calcInterest(_amount) * _duration / (_duration + _buffer);
    // difference between total interest and tranche interest (positive for AA, negative for BB)
    _diff = int256(interestWithoutSplitRatio) - int256(_interest);
  }

  /// @notice Calculate the tranche share of the total interest for the epoch
  /// @param _totalInterest Total interest for the epoch (net of fees not meant for tranches)
  /// @param _tranche Tranche to get the interest for
  function _calcTrancheInterestShare(uint256 _totalInterest, address _tranche) internal view returns (uint256) {
    uint256 ratio = trancheAPRSplitRatio;
    return _totalInterest * (_tranche == AATranche ? ratio : FULL_ALLOC - ratio) / FULL_ALLOC;
  }

  /// @notice Apply projected management and performance fees to a positive gain.
  function _netGainAfterFees(uint256 _gain, uint256 _managementFee) private view returns (uint256 netGain) {
    if (_managementFee >= _gain) return netGain;
    // remove mgmt fee and performance fee
    _gain -= _managementFee;
    return _gain - _gain * fee / FULL_ALLOC;
  }

  /// @notice Calculate total fees charged on a withdrawal request.
  /// @param _principal Principal leaving live NAV.
  /// @param _interest Projected interest for the requested principal.
  /// @return Total management and performance fees to subtract from principal plus projected interest.
  function _totalWithdrawFees(uint256 _principal, uint256 _interest) private view returns (uint256) {
    uint256 _mgmtFee = _calculateManagementFee(_principal, _withdrawRequestManagementFeeDuration());
    // When interest covers management fees, interest - netGain equals management fee plus performance fee.
    return _mgmtFee >= _interest ?
      _mgmtFee :
      _interest - _netGainAfterFees(_interest, _mgmtFee);
  }

  /// @notice Get the max amount of underlyings that can be withdrawn by user
  /// @param _user User address
  /// @param _tranche Tranche to withdraw from
  function maxWithdrawable(address _user, address _tranche) external view returns (uint256 currentUnderlyings) {
    currentUnderlyings = _trancheToUnderlyings(_userTrancheBal(_user, _tranche), _tranche);
    currentUnderlyings -= _calculateManagementFee(currentUnderlyings, block.timestamp - latestHarvestBlock);
    // add interest for one epoch
    (uint256 interest, ) = _calcInterestWithdrawRequest(currentUnderlyings, _tranche);
    // remove upfront management fee and performance fee on the remaining projected interest
    currentUnderlyings = currentUnderlyings + interest - _totalWithdrawFees(currentUnderlyings, interest);
  }

  /// @notice Get the duration used for upfront management fees on withdrawal receipts.
  /// @dev Receipts leave live NAV at request time but can be claimed only after the
  /// next epoch settles. Requests made during the buffer also pay for the remaining
  /// buffer time before that next epoch can start.
  /// @return _duration One epoch plus any remaining buffer before the next epoch.
  function _withdrawRequestManagementFeeDuration() private view returns (uint256 _duration) {
    uint256 bufferEnd = epochEndDate + bufferPeriod;
    _duration = epochDuration;
    if (block.timestamp < bufferEnd) {
      _duration += bufferEnd - block.timestamp;
    }
  }

  /// @notice Write off the deposit, this will be used if the borrower and a lender comes to an off-chain agreement
  /// so here we burn tranche tokens, the equivalent amount of strategy tokens. Only the borrower can call this
  /// @param _amount Amount of tranche tokens to write off
  function writeOffDeposit(uint256 _amount, address _tranche) external {
    // only borrower can call this method and only during an epoch, otherwise one should follow the traditional flow
    _checkNotAllowed(_borrower() != msg.sender || !isEpochRunning);
    _checkTranche(_tranche);
    // Remove raw donations so write-off interest math only sees accounted vault value.
    _skimDonatedAssets();

    // Calculate tranche tokens value with current tranche price
    uint256 _underlyings = _trancheToUnderlyings(_amount, _tranche);
    // We now calculate how much interest + fee the tranche would have generated in the current epoch
    (uint256 interest, int256 diff) = _calcInterestWithdrawRequest(_underlyings, _tranche);
    // given that _calcInterestWithdrawRequest returns an interest and diff value meant to be used in requestWithdraw
    // it does not include the buffer period but given that the epoch is running expectedEpochInterest was
    // calculated with the buffer period included, so we need to scale the interest
    uint256 _epochDuration = epochDuration;

    // (interest + diff) gives the interest based on tvl as write off debt won't follow senior/junior interest split ratio
    // diff is positive for AA and negative for BB (in this case it won't be > of interest)
    interest = uint256(int256(interest) + diff) * (_epochDuration + bufferPeriod) / _epochDuration;

    // Burn tranche tokens and decrease lastNAV
    _withdrawOps(_amount, _underlyings, _tranche);
    // Burn strategy tokens and decrease NAV (1:1 with underlyings)
    IdleCreditVault(strategy).burnStrategyTokens(_underlyings);

    // remove the interest + fee from expectedEpochInterest
    expectedEpochInterest -= interest;
  }

  /// @notice Claim a withdraw request from the vault. Can be done when at least 1 epoch passed
  /// since last withdraw request
  function claimWithdrawRequest() external {
    // underlyings requested, here we check that user waited at least one epoch and that borrower
    // did not default upon repayment (old requests can still be claimed)
    IdleCreditVault(strategy).claimWithdrawRequest(msg.sender);
  }

  /// @notice Claim an instant withdraw request from the vault. Can be done when epoch is running
  /// as funds will get transferred from borrower when epoch starts
  function claimInstantWithdrawRequest() external {
    // Check that instant withdraws are available
    _checkNotAllowed(!allowInstantWithdraw);
    IdleCreditVault(strategy).claimInstantWithdrawRequest(msg.sender);
  }

  /// @notice Check if wallet is allowed to interact with the contract
  /// @param _user User address
  /// @return true if wallet is allowed or keyring address is not set
  function isWalletAllowed(address _user) public view returns (bool) {
    address _keyring = keyring;
    return _keyring == address(0) || IKeyring(_keyring).checkCredential(keyringPolicyId, _user);
  }

  /// @notice Notify a programmable borrower that a new epoch has started.
  /// @param _pendingWithdraws Amount reserved for withdraw requests that mature at epoch stop.
  function _startEpochProgrammableBorrower(uint256 _pendingWithdraws) internal {
    if (isProgrammableBorrower) {
      IProgrammableBorrower(_borrower()).onStartEpoch(_pendingWithdraws);
    }
  }

  /// @notice Resolve the stop-epoch interest value, optionally sourcing it from a programmable borrower.
  /// @dev Programmable borrowers are always the source of truth for epoch interest.
  /// In that mode `_interest` values `0` and `1` both resolve to the realized epoch interest,
  /// while `1` still separately signals the close-pool path to the caller.
  function _resolveStopEpochInterest(uint256 _interest) internal view returns (uint256 _resolvedInterest) {
    if (isProgrammableBorrower) {
      _checkNotAllowed(_interest > 1);
      return IProgrammableBorrower(_borrower()).totalInterestDueNow();
    }

    _resolvedInterest = _interest;
  }
}
