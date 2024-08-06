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
error EpochNotRunning();
error DeadlineNotMet();
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
  /// @notice apr of the last epoch
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
    trancheAPRSplitRatio = FULL_ALLOC;
    // deposit directly in the strategy
    directDeposit = true;

    // set epoch params
    epochDuration = 30 days;
    instantWithdrawDelay = 3 days;
    // prevent normal withdrawals, only requests for withdrawal are allowed
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    // allow requests for withdrawals
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;
    // min apr delta to trigger instant withdraw
    instantWithdrawAprDelta = 1.5e18; // 1.5%

    // set keyring address
    keyring = 0xD18d17791f2071Bf3C855bA770420a9EdEa0728d;
    keyringPolicyId = 4;
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
  /// @param _epochDuration duration in seconds
  function setEpochDuration(uint256 _epochDuration) external {
    _checkOnlyOwnerOrManager();
    epochDuration = _epochDuration;
  }

  /// @notice update instant withdraw params
  /// @param _delay delay in seconds
  /// @param _aprDelta min apr delta to trigger instant withdraw
  /// @param _disable flag to disable instant withdraw
  function setInstantWithdrawParams(uint256 _delay, uint256 _aprDelta, bool _disable) external {
    _checkOnlyOwnerOrManager();
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

  /// @notice Start the epoch. No deposits or withdrawals are allowed after this.
  /// @dev We calculate the total funds that the borrower should return at the end of the epoch
  /// ie interests + fees from normal withdraw requests. We send to the borrower underlyings amounts ie interests + 
  /// new deposits - instant withdraw requests if any. If funds are not enough to satisfy all requests
  /// then borrower should return the difference before instantWithdrawDeadline. After epoch start there
  /// should be no underlyings in this contract
  function startEpoch() external {
    _checkOnlyOwnerOrManager();

    // Check that epoch is not running
    if (isEpochRunning) {
      revert EpochRunning();
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
    epochEndDate = block.timestamp + epochDuration;
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
  /// be greater than the pending withdraw fees and newApr must be 0
  /// @dev Only owner or manager can call this function. Borrower MUST approve this contract
  function stopEpoch(uint256 _newApr, uint256 _interest) external {
    _checkOnlyOwnerOrManager();

    // Check that epoch is running
    if (!isEpochRunning) {
      revert EpochNotRunning();
    }
    // Check that end date is passed
    if (block.timestamp < epochEndDate) {
      revert EpochRunning();
    }

    IdleCreditVault _strategy = IdleCreditVault(strategy);

    // Check that there are no pending instant withdraws, ie `getInstantWithdrawFunds` was called
    // before closing the epoch
    if (_strategy.pendingInstantWithdraws() > 0) {
      revert NotAllowed();
    }

    uint256 _pendingWithdrawFees = pendingWithdrawFees;
    uint256 _pendingWithdraws = _strategy.pendingWithdraws();

    // overridden interest should be greater than pending withdraw fees and the apr should be 
    // 0 otherwise withdrawal requests may not be fullfilled as they consider also the interest
    // gained in the next epoch 
    if (_interest > 0 && (_interest < _pendingWithdrawFees || _newApr != 0)) {
      revert NotAllowed();
    }

    uint256 _expectedInterest = _interest > 0 ? _interest : expectedEpochInterest;

    // accrue interest to idleCDO, this will increase tranche prices.
    // Send also tot withdraw requests amount to the IdleCreditVault contract
    try this.getFundsFromBorrower(_expectedInterest, _pendingWithdraws, 0) {
      // transfer in strategy and decrease pendingWithdraws
      if (_pendingWithdraws > 0) {
        _strategy.collectWithdrawFunds(_pendingWithdraws);
      }

      // Transfer pending withdraw fees to feeReceiver before update accounting
      // NOTE: Fees are sent with 2 different transfer calls to avoid complicated calculations
      if (_pendingWithdrawFees > 0) {
        IERC20Detailed(token).safeTransfer(feeReceiver, _pendingWithdrawFees);
      }

      // update tranche prices and unclaimed fees
      _updateAccounting();

      // transfer fees
      uint256 _fees = unclaimedFees;
      IERC20Detailed(token).safeTransfer(feeReceiver, _fees);
      unclaimedFees = 0;

      // save net gain (this does not include interest gained for pending withdrawals)
      uint256 netInterest = _expectedInterest - _fees - _pendingWithdrawFees;
      lastEpochInterest = netInterest;
      // mint strategyTokens equal to interest and send underlying to strategy to avoid double counting for NAV
      _strategy.deposit(netInterest);

      // save last apr
      lastEpochApr = _strategy.getApr();
      // set apr for next epoch
      _strategy.setApr(_newApr);

      // stop epoch
      isEpochRunning = false;
      expectedEpochInterest = 0;
      pendingWithdrawFees = 0;

      // allow deposits
      _unpause();
      // allow withdrawals requests
      allowAAWithdrawRequest = true;
      allowBBWithdrawRequest = true;
      // block instant withdraws as these can be done only after the deadline
      allowInstantWithdraw = false;

      emit AccrueInterest(_expectedInterest, _fees + _pendingWithdrawFees);
    } catch {
      isEpochRunning = false;
      // if borrower defaults, prev instant withdraw requests can still be withdrawn
      // as were already fullfilled prior to the default (all funds already sent to the strategy)
      allowInstantWithdraw = true;
      _handleBorrowerDefault(_expectedInterest + _pendingWithdraws);
    }
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

    if (!isEpochRunning) {
      revert EpochNotRunning();
    }

    if (block.timestamp < instantWithdrawDeadline) {
      revert DeadlineNotMet();
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
    _pause();
    // prevent withdraws requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;
    // Allow deposits/withdraws (once selectively re-enabled, eg for AA holders)
    // without checking for lending protocol default
    skipDefaultCheck = true;
    revertIfTooLow = true;
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
    _unpause();
    // restore withdraws
    allowAAWithdrawRequest = true;
    allowBBWithdrawRequest = true;
    // Allow deposits/withdraws but checks for lending protocol default
    skipDefaultCheck = false;
    revertIfTooLow = true;
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
    // check if _tranche is valid and if withdraws for that tranche are allowed 
    if (!(_tranche == aa || _tranche == bb) || 
      (!allowAAWithdrawRequest && _tranche == aa) || 
      (!allowBBWithdrawRequest && _tranche == bb) ||
      !isWalletAllowed(msg.sender)
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
      if (lastEpochApr > (creditVault.getApr() + instantWithdrawAprDelta)) {
        // Calc max withdrawable if amount passed is 0
        _underlyings = _amount == 0 ? maxWithdrawableInstant(msg.sender, _tranche) : _underlyings;
        // burn strategy tokens from cdo
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

    uint256 interest = _calcInterest(_underlyings) * trancheAPRSplitRatio / FULL_ALLOC;
    uint256 fees = interest * fee / FULL_ALLOC;
    uint256 netInterest = interest - fees;
    // user is requesting principal + interest of next epoch minus fees
    _underlyings += netInterest;
    // add expected fees to pending withdraw fees counter
    pendingWithdrawFees += fees;
    
    // request normal withdraw, we burn strategy tokens without interest for the new epoch
    creditVault.requestWithdraw(_underlyings, msg.sender, netInterest);
    // burn tranche tokens and decrease NAV without interest for the next epoch as it was not yet counted in NAV
    _withdrawOps(_amount, _underlyings - netInterest, _tranche);
    return _underlyings;
  }

  /// @notice Calculate the interest of an epoch for the given amount
  /// @param _amount Amount of underlyings
  function _calcInterest(uint256 _amount) internal view returns (uint256) {
    return _amount * (IdleCreditVault(strategy).getApr() / 100) * epochDuration / (365 days * ONE_TRANCHE_TOKEN);
  }

  /// @notice Get the max amount of underlyings that can be withdrawn by user
  /// @param _user User address
  /// @param _tranche Tranche to withdraw from
  function maxWithdrawable(address _user, address _tranche) external view returns (uint256) {
    uint256 currentUnderlyings = IERC20Detailed(_tranche).balanceOf(_user) * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    // add interest for one epoch
    uint256 interest = _calcInterest(currentUnderlyings) * trancheAPRSplitRatio / FULL_ALLOC;
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

  /// @notice Claim a withdraw request from the vault. Can be done when epoch is not running
  /// as funds will get transferred from borrower when epoch ends
  function claimWithdrawRequest() external {
    // Check that epoch is not running
    if (isEpochRunning) {
      revert EpochRunning();
    }

    IdleCreditVault _strategy = IdleCreditVault(strategy);

    // if borrower did not paid prev withdraw requests, revert. if instead he defaulted
    // only on instant withdraw requests but prev normal withdraws were fullfilled, we can still
    // allow normal withdraws
    if (defaulted && _strategy.pendingWithdraws() != 0) {
      revert Default();
    }

    // underlyings requested
    _strategy.claimWithdrawRequest(msg.sender);
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
  /// @return true if wallet is allowed
  function isWalletAllowed(address _user) public view returns (bool) {
    address _keyring = keyring;
    if (_keyring == address(0)) {
      return true;
    }
    return IKeyring(_keyring).checkCredential(keyringPolicyId, _user);
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
  function getIncentiveTokens() external view override returns (address[] memory) {}
  function setReleaseBlocksPeriod(uint256) external override {}
  function _lockedRewards() internal view override returns (uint256) {}

  /// NOTE: stkIDLE gating is not used
  function toggleStkIDLEForTranche(address) external override {}
  function _checkStkIDLEBal(address, uint256) internal view override {}
  function setStkIDLEPerUnderlying(uint256) external override {}

  /// NOTE: fees are not deposited in this contract
  function _depositFees() internal override {}
}