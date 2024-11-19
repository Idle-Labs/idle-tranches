// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDO} from "./IdleCDO.sol";
import {IKeyring} from "./interfaces/keyring/IKeyring.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";
import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {IIdleCDOStrategy} from "./interfaces/IIdleCDOStrategy.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

error EpochRunning();
error NotAllowed();
error Default();

/// @title IdleCDO variant that supports epochs. 
/// @dev When epoch is running no deposits or withdrawals are allowed. When epoch ends 
/// lenders can request withdrawals, that will be fullfilled by the end of the next epoch.
/// If the apr for the new epoch is lower than the last one, lenders can request 'instant' 
/// withdrawals that will be fullfilled when the epoch starts and after instantWithdrawDelay (3 days).
/// Funds for instant and normal withdrawals are sent to the strategy contract (IdleCreditVault)
contract IdleCDOEpochVariant is IdleCDO {
  using SafeERC20Upgradeable for IERC20Detailed;

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
  /// @notice flag for enabling anyone to request a withdraw (needed for liquidations)
  bool public keyringAllowWithdraw;

  event AccrueInterest(uint256 interest, uint256 fees);
  event BorrowerDefault(uint256 funds);

  function _additionalInit() internal virtual override {
    // no unlent perc
    unlentPerc = 0;

    // Set the contract with monotranche as default (can still be changed if needed)
    // losses are split according to tvl, senior has no priority
    lossToleranceBps = FULL_ALLOC;
    // all yield to senior
    isAYSActive = false;
    // deposit directly in the strategy
    directDeposit = true;

    // set epoch params
    epochDuration = 30 days;
    bufferPeriod = 5 days;

    // allow requests for withdrawals
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;

    // default no instant withdraw allowed
    disableInstantWithdraw = true;

    // scale the apr to include the buffer period
    _setScaledApr(IdleCreditVault(strategy).getApr());
  }

  /// @notice Check if msg sender is owner or manager
  function _checkOnlyOwnerOrManager() internal view {
    if (msg.sender != owner() && msg.sender != IdleCreditVault(strategy).manager()) {
      revert NotAllowed();
    }
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
    if (isEpochRunning || _epochDuration == 0 || epochDuration == 0) {
      revert NotAllowed();
    }
    epochDuration = _epochDuration;
    bufferPeriod = _bufferPeriod;
  }

  /// @notice update instant withdraw params
  /// @param _delay delay in seconds
  /// @param _aprDelta min apr delta to trigger instant withdraw
  /// @param _disable flag to disable instant withdraw
  function setInstantWithdrawParams(uint256 _delay, uint256 _aprDelta, bool _disable) external {
    _checkOnlyOwnerOrManager();
    if (isEpochRunning) {
      revert EpochRunning();
    }
    instantWithdrawDelay = _delay;
    instantWithdrawAprDelta = _aprDelta;
    disableInstantWithdraw = _disable;
  }

  /// @notice update keyring address
  /// @param _keyring address of the keyring contract
  /// @param _keyringPolicyId policyId to check for wallet
  /// @param _keyringAllowWithdraw flag to allow anyone to request a withdraw
  function setKeyringParams(address _keyring, uint256 _keyringPolicyId, bool _keyringAllowWithdraw) external {
    _checkOnlyOwnerOrManager();
    keyring = _keyring;
    keyringPolicyId = _keyringPolicyId;
    keyringAllowWithdraw = _keyringAllowWithdraw;
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
    if (block.timestamp < (epochEndDate + bufferPeriod) || _epochDuration == 0) {
      revert NotAllowed();
    }

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
    expectedEpochInterest = _calcInterest(getContractValue()) + pendingWithdrawFees;

    // set expected epoch end date
    epochEndDate = block.timestamp + _epochDuration;
    // set instant withdraw deadline
    instantWithdrawDeadline = block.timestamp + instantWithdrawDelay;

    // transfer in this contract funds from interest payment, that were sent to the strategy in stopEpoch
    _strategy.sendInterestAndDeposits(lastEpochInterest + _strategy.totEpochDeposits());

    // we should first check if there are *instant* redeem requests pending 
    // and if yes we should send as much underlyings as possible to the IdleCreditVault contract
    // if there is any surplus then we send those to the borrower
    uint256 pendingInstant = _strategy.pendingInstantWithdraws();
    uint256 totUnderlyings = _contractTokenBalance(token);

    // if there are more requests than the current underlyings we simply send all underlyings
    // to the IdleCreditVault contract
    if (pendingInstant > totUnderlyings) {
      // transfer funds to strategy
      _strategy.collectInstantWithdrawFunds(totUnderlyings);
      return;
    }
    // otherwise we send the amount needed to satisfy the requests to the strategy 
    _strategy.collectInstantWithdrawFunds(pendingInstant);
    // allow instant withdraws right away without waiting for the deadline
    allowInstantWithdraw = true;
    // and transfer the surplus to the borrower
    try this.sendFundsToBorrower(totUnderlyings - pendingInstant) {
      // funds transferred correctly
    } catch {
      _handleBorrowerDefault(totUnderlyings - pendingInstant);
    }
  }

  /// @notice workaround to have safeTransfer to borrower as external and use it in a try/catch block
  /// @param _amount Amount of underlyings to transfer
  function sendFundsToBorrower(uint256 _amount) external {
     if (msg.sender != address(this)) {
      revert NotAllowed();
    }
    IERC20Detailed(token).safeTransfer(IdleCreditVault(strategy).borrower(), _amount);
  }

  /// @notice Stop epoch, accrue interest to the vault and get funds to fullfill normal
  /// (ie non-instant) withdraw requests from the prev epoch.
  /// @param _newApr New apr to set for the next epoch
  /// @param _interest Interest gained in the epoch. This will overwrite the expected interest
  /// must be 0 if there is no need to overwrite the expected interest and if > 0 then it should
  /// be greater than the pending withdraw fees and newApr must be 0. If `_interest` is 1 then
  /// it is interpreted as a special case where we request everything back from the borrower
  /// @dev Only owner or manager can call this function. Borrower MUST approve this contract
  function stopEpoch(uint256 _newApr, uint256 _interest) public {
    _checkOnlyOwnerOrManager();

    IdleCreditVault _strategy = IdleCreditVault(strategy);
    uint256 _pendingWithdraws = _strategy.pendingWithdraws();
    uint256 _pendingWithdrawFees = pendingWithdrawFees;

    if (
      // Check that epoch is running
      !isEpochRunning || 
      // Check that end date is passed
      block.timestamp < epochEndDate || 
      // Check that there are no pending instant withdraws, ie `getInstantWithdrawFunds` was called
      // before closing the epoch
      _strategy.pendingInstantWithdraws() > 0 ||
      // Check that overridden interest, if passed (ie > 1), is greater than pending withdraw fees and the apr is 0 
      // otherwise withdrawal requests may not be fullfilled as they consider also the interest gained in the next epoch 
      (_interest > 1 && (_interest < _pendingWithdrawFees || _newApr != 0))
    ) {
      revert NotAllowed();
    }

    uint256 _expectedInterest = _interest > 1 ? _interest : expectedEpochInterest;
    uint256 _totBorrowed;
    bool _isRequestingAllFunds = _interest == 1;
    // special case where we get everything back from the borrower
    if (_isRequestingAllFunds) {
      // do not consider underlyings already in this contract
      _totBorrowed = getContractValue() - _contractTokenBalance(token);
      _expectedInterest += _totBorrowed;
    }

    // accrue interest to idleCDO, this will increase tranche prices.
    // Send also tot withdraw requests amount to the IdleCreditVault contract
    try this.getFundsFromBorrower(_expectedInterest, _pendingWithdraws, 0) {
      // transfer in strategy and decrease pendingWithdraws
      if (_pendingWithdraws > 0) {
        _strategy.collectWithdrawFunds(_pendingWithdraws);
      }

      // Transfer pending withdraw fees to feeReceiver before update accounting
      // NOTE: Fees are sent with 2 different transfer calls, here and after updateAccounting, to avoid complicated calculations
      if (_pendingWithdrawFees > 0) {
        IERC20Detailed(token).safeTransfer(feeReceiver, _pendingWithdrawFees);
      }

      if (_isRequestingAllFunds) {
        // we already have strategyTokens equal to _totBorrowed in this contract
        // so we simply transfer _totBorrowed to the strategy to avoid double counting
        // for getContractValue
        IERC20Detailed(token).safeTransfer(address(_strategy), _totBorrowed);
      }

      // update tranche prices and unclaimed fees
      _updateAccounting();

      // transfer fees
      uint256 _fees = unclaimedFees;
      IERC20Detailed(token).safeTransfer(feeReceiver, _fees);
      unclaimedFees = 0;

      // save net gain (this does not include interest gained for pending withdrawals)
      uint256 netInterest = (_isRequestingAllFunds ? _expectedInterest - _totBorrowed : _expectedInterest) - _fees - _pendingWithdrawFees;
      lastEpochInterest = netInterest;
      // mint strategyTokens equal to interest and send underlying to strategy to avoid double counting for NAV
      _strategy.deposit(netInterest);

      // save last apr, unscaled
      lastEpochApr = _strategy.unscaledApr();
      // set apr for next epoch
      _setScaledApr(_newApr);

      // stop epoch
      isEpochRunning = false;
      expectedEpochInterest = 0;
      pendingWithdrawFees = 0;

      // allow deposits
      _unpause();
      // allow withdrawals requests
      allowAAWithdrawRequest = true;
      allowBBWithdrawRequest = true;
      // block instant withdraws claims as these can be done only after the deadline
      // or only if borrower is repaying all funds
      allowInstantWithdraw = _isRequestingAllFunds;

      if (_isRequestingAllFunds) {
        // user will request only normal withdraw and can claim right after
        disableInstantWithdraw = true;
        epochDuration = 0;
        epochEndDate = 0;
      }

      emit AccrueInterest(_expectedInterest - _totBorrowed, _fees + _pendingWithdrawFees);
    } catch {
      isEpochRunning = false;
      // if borrower defaults, prev instant withdraw requests can still be withdrawn
      // as were already fullfilled prior to the default (all funds already sent to the strategy)
      allowInstantWithdraw = true;
      _handleBorrowerDefault(_expectedInterest + _pendingWithdraws);
    }
  }

  /// @notice Stop epoch and set new duration
  /// @dev see stopEpoch and setEpochParams for more details, bufferPeriod is not modified
  /// @param _newApr New apr to set for the next epoch
  /// @param _interest Interest gained in the epoch
  /// @param _duration New epoch duration
  function stopEpochWithDuration(uint256 _newApr, uint256 _interest, uint256 _duration) external {
    // stop epoch checks that msg.sender is allowed
    stopEpoch(_newApr, _interest);
    // buffer period is not changed
    setEpochParams(_duration, bufferPeriod);

    // scale the apr with the new durantion and buffer
    _setScaledApr(_newApr);
  }

  /// @notice The apr should be increased by an amount proportional to the buffer period in this 
  /// way during a buffer period lenders will still get interest. Eg if epoch is 30 days and buffer 
  /// is 5 days and the apr lenders should receive is 10% then _newApr should be 10% * 35/30 = 11.67%.
  /// @param _apr Apr to scale
  function _scaleAprWithBuffer(uint256 _apr) internal view returns (uint256) {
    uint256 _duration = epochDuration;
    return _duration == 0 ? _apr : _apr * (_duration + bufferPeriod) / _duration;
  }

  /// @notice Set the scaled apr for the next epoch
  /// @param _newApr New apr to set for the next epoch
  function _setScaledApr(uint256 _newApr) internal {
    IdleCreditVault(strategy).setAprs(_newApr, _scaleAprWithBuffer(_newApr));
  }

  /// @dev Get interest and funds for fullfill withdraw requests (normal and instant) from borrower,
  /// method is external so it can be used in the try/catch blocks
  /// @param _amount Amount of interest to transfer
  /// @param _withdrawRequests Total withdraw requests
  /// @param _instantWithdrawRequests Total instant withdraw requests
  function getFundsFromBorrower(uint256 _amount, uint256 _withdrawRequests, uint256 _instantWithdrawRequests) external {
    if (msg.sender != address(this)) {
      revert NotAllowed();
    }

    uint256 _tot = _amount + _withdrawRequests + _instantWithdrawRequests;
    if (_tot == 0) {
      return;
    }
    IERC20Detailed(token).safeTransferFrom(IdleCreditVault(strategy).borrower(), address(this), _tot);
  }

  /// @notice Get funds from borrower to fullfill instant withdraw requests
  /// Manager should call this method after instantWithdrawDeadline (when epoch is running)
  function getInstantWithdrawFunds() external {
    _checkOnlyOwnerOrManager();

    // Check that epoch is running and that current time is after the deadline
    if (!isEpochRunning || block.timestamp < instantWithdrawDeadline) {
      revert NotAllowed();
    }

    IdleCreditVault _strategy = IdleCreditVault(strategy);
    uint256 _instantWithdraws = _strategy.pendingInstantWithdraws();
    // transfer funds for instant withdraw to this contract
    try this.getFundsFromBorrower(0, 0, _instantWithdraws) {
      // transfer funds to IdleCreditVault and decrease pendingInstantWithdraws
      if (_instantWithdraws > 0) {
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

    // deposits should be already prevented
    if (!paused()) {
      _pause();
    }

    // stop the current epoch
    isEpochRunning = false;

    // prevent withdrawals requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;

    // allow strategyTokens transfers 
    IdleCreditVault(strategy).allowTransfers();

    emit BorrowerDefault(funds);
  }

  /// @notice Prevent deposits and redeems for all classes of tranches
  function _emergencyShutdown(bool) internal override {
    // prevent deposits
    if (!paused()) {
      _pause();
    }
    // prevent withdraws requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;
    // Allow deposits/withdraws (once selectively re-enabled, eg for AA holders)
    // without checking for lending protocol default
    skipDefaultCheck = true;
  }

  /// @notice allow deposits and redeems for all classes of tranches
  /// @dev can be called by the owner only
  function restoreOperations() external override {
    _checkOnlyOwner();
    // Check if the pool was defaulted
    if (defaulted) {
      revert NotAllowed();
    }
    // restore deposits
    if (paused()) {
      _unpause();
    }
    // restore withdraws
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;
    // Allow deposits/withdraws but checks for lending protocol default
    skipDefaultCheck = false;
  }

  /// 
  /// User methods
  ///

  /// @notice Deposit funds in the vault. Overrides the parent method and adds a check for wallet 
  function _deposit(uint256 _amount, address _tranche, address _referral) internal override whenNotPaused returns (uint256) {
    if (!isWalletAllowed(msg.sender)) {
      revert NotAllowed();
    }
    return super._deposit(_amount, _tranche, _referral);
  }

  /// @notice Request a withdraw from the vault
  /// @param _amount Amount of tranche tokens 
  /// @param _tranche Tranche to withdraw from
  /// @return Amount of underlyings requested
  function requestWithdraw(uint256 _amount, address _tranche) external returns (uint256) {
    address aa = AATranche;
    address bb = BBTranche;
    // check if _tranche is valid and if withdraws for that tranche are allowed and if user is allowed
    if (!(_tranche == aa || _tranche == bb) || 
      (!allowAAWithdrawRequest && _tranche == aa) || 
      (!allowBBWithdrawRequest && _tranche == bb) ||
      (!keyringAllowWithdraw && !isWalletAllowed(msg.sender))
    ) {
      revert NotAllowed();
    }
  
    // we trigger an update accounting to check for eventual losses
    _updateAccounting();

    IdleCreditVault creditVault = IdleCreditVault(strategy);
    uint256 _underlyings = _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    uint256 _userTrancheTokens = IERC20Detailed(_tranche).balanceOf(msg.sender);

    if (!disableInstantWithdraw) {
      // If apr decresed wrt last epoch, request instant withdraw and burn tranche tokens directly
      // we compare unscaled aprs
      if (lastEpochApr > (creditVault.unscaledApr() + instantWithdrawAprDelta)) {
        // Calc max withdrawable if amount passed is 0
        _underlyings = _amount == 0 ? maxWithdrawableInstant(msg.sender, _tranche) : _underlyings;
        // burn strategy tokens from cdo and mint an equal amount to msg.sender as receipt
        creditVault.requestInstantWithdraw(_underlyings, msg.sender);

        // burn tranche tokens and decrease NAV
        if (_amount == 0) {
          _amount = _userTrancheTokens;
        }
        _withdrawOps(_amount, _underlyings, _tranche);
        return _underlyings;
      }
    }

    // recalculate underlyings considering also interest accrued in the epoch as normal withdraws
    // will still accrue interest for the next epoch
    if (_amount == 0) {
      _underlyings = _userTrancheTokens * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
      _amount = _userTrancheTokens;
    }

    uint256 interest = _calcInterestWithdrawRequest(_underlyings) * _trancheAprRatio(_tranche) / FULL_ALLOC;
    uint256 fees = interest * fee / FULL_ALLOC;
    uint256 netInterest = interest - fees;
    // user is requesting principal + interest of next epoch minus fees
    _underlyings += netInterest;
    // add expected fees to pending withdraw fees counter
    pendingWithdrawFees += fees;
    
    // request normal withdraw, we burn strategy tokens without interest for the new epoch and mint and eq amount to msg.sender
    creditVault.requestWithdraw(_underlyings, msg.sender, netInterest);
    // burn tranche tokens and decrease NAV without interest for the next epoch as it was not yet counted in NAV
    _withdrawOps(_amount, _underlyings - netInterest, _tranche);
    return _underlyings;
  }

  /// @notice Get the tranche apr split ratio
  /// @param _tranche address
  /// @return _aprRatio apr split ratio for the tranche
  function _trancheAprRatio(address _tranche) internal view returns (uint256 _aprRatio) {
    _aprRatio = _tranche == AATranche ? trancheAPRSplitRatio : FULL_ALLOC - trancheAPRSplitRatio;
  }

  /// @notice Calculate the interest of an epoch for the given amount
  /// @param _amount Amount of underlyings
  function _calcInterest(uint256 _amount) internal view returns (uint256) {
    return _amount * (IdleCreditVault(strategy).getApr() / 100) * epochDuration / (365 days * ONE_TRANCHE_TOKEN);
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
  function _calcInterestWithdrawRequest(uint256 _amount) internal view returns (uint256) {
    uint256 _duration = epochDuration;
    return _duration == 0 ? 0 : _calcInterest(_amount) * _duration / (_duration + bufferPeriod);
  }

  /// @notice Get the max amount of underlyings that can be withdrawn by user
  /// @param _user User address
  /// @param _tranche Tranche to withdraw from
  function maxWithdrawable(address _user, address _tranche) external view returns (uint256) {
    uint256 currentUnderlyings = IERC20Detailed(_tranche).balanceOf(_user) * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    // add interest for one epoch
    uint256 interest = _calcInterestWithdrawRequest(currentUnderlyings) * _trancheAprRatio(_tranche) / FULL_ALLOC;
    // sum and remove fees
    return currentUnderlyings + interest - (interest * fee / FULL_ALLOC);
  }

  /// @notice Get the max amount of underlyings that can be withdrawn instantly by user
  /// @param _user User address
  /// @param _tranche Tranche to withdraw from
  function maxWithdrawableInstant(address _user, address _tranche) public view returns (uint256) {
    return IERC20Detailed(_tranche).balanceOf(_user) * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice Burn tranche tokens and update NAV and trancheAPRSplitRatio
  /// @param _amount Amount of tranche tokens
  /// @param _underlyings Amount of underlyings
  /// @param _tranche Tranche to withdraw from
  function _withdrawOps(uint256 _amount, uint256 _underlyings, address _tranche) internal {
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= _underlyings;
    } else {
      lastNAVBB -= _underlyings;
    }

    // update trancheAPRSplitRatio
    _updateSplitRatio(_getAARatio(true));
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
    if (!allowInstantWithdraw) {
      revert NotAllowed();
    }
    IdleCreditVault(strategy).claimInstantWithdrawRequest(msg.sender);
  }

  /// @notice Check if wallet is allowed to interact with the contract
  /// @param _user User address
  /// @return true if wallet is allowed or keyring address is not set
  function isWalletAllowed(address _user) public view returns (bool) {
    address _keyring = keyring;
    return _keyring == address(0) || IKeyring(_keyring).checkCredential(keyringPolicyId, _user);
  }

  /// 
  /// Overridden method not used in this contract (to reduce bytcode size)
  ///

  /// NOTE: normal withdraw are not allowed
  function withdrawAA(uint256) external override returns (uint256) {}
  function withdrawBB(uint256) external override returns (uint256) {}
  function _withdraw(uint256, address) override pure internal returns (uint256) {}
  function setAllowAAWithdraw(bool) external override {}
  function setAllowBBWithdraw(bool) external override {}
  function liquidate(uint256, bool) external override returns (uint256) {}
  function _liquidate(uint256, bool) internal override returns (uint256) {}
  function setRevertIfTooLow(bool) external override {}
  function setLiquidationTolerance(uint256) external override {}

  /// NOTE: strategy price is alway equal to 1 underlying
  function _checkDefault() override internal {}
  function setSkipDefaultCheck(bool) external override {}
  function setMaxDecreaseDefault(uint256) external override {}

  /// NOTE: harvest is not performed to transfer funds to the strategy (startEpoch is used)
  function harvest(
    bool[] calldata,
    bool[] calldata,
    uint256[] calldata,
    uint256[] calldata,
    bytes[] calldata
  ) public override returns (uint256[][] memory) {}

  /// NOTE: there are no rewards to sell nor incentives
  function _sellAllRewards(IIdleCDOStrategy, uint256[] memory, uint256[] memory, bool[] memory, bytes memory)
    internal override returns (uint256[] memory, uint256[] memory, uint256) {}
  function _sellReward(address, bytes memory, uint256, uint256)
    internal override returns (uint256, uint256) {}
  function setReleaseBlocksPeriod(uint256) external override {}
  function _lockedRewards() internal view override returns (uint256) {}

  /// NOTE: stkIDLE gating is not used
  function toggleStkIDLEForTranche(address) external override {}
  function _checkStkIDLEBal(address, uint256) internal view override {}
  function setStkIDLEPerUnderlying(uint256) external override {}

  /// NOTE: fees are not deposited in this contract
  function _depositFees() internal override {}
  function depositBBRef(uint256, address) external override returns (uint256) {}

  /// NOTE: unlent perc should always be 0 and set in additionalInit
  function setUnlentPerc(uint256) external override {}

  /// NOTE: the vault is either a single tranche (ie all interest to senior and set in additionalInit) or AYS is active
  function setTrancheAPRSplitRatio(uint256) external override {}
}