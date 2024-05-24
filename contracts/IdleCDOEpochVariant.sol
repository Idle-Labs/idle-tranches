// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IdleCDO} from "./IdleCDO.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";
import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

error EpochRunning();
error EpochNotRunning();
error DeadlineNotMet();
error NotAllowed();
error BorrowerDefault();
error AmountTooHigh();

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
  /// @notice total deposits in the current epoch
  uint256 public totEpochDeposits;
  /// @notice flag to allow instant withdraws
  bool public allowInstantWithdraw;
  /// @notice flag to disable instant withdraw
  bool public disableInstantWithdraw;
  /// @notice flag to check if borrower defaulted
  bool public defaulted;

  event AccrueInterest(uint256 interest, uint256 fees);

  function _additionalInit() internal override {
    // no unlent perc
    unlentPerc = 0;

    // Set the contract with monotranche as default (can still be changed if needed)
    // losses are split according to tvl, senior has no priority
    lossToleranceBps = FULL_ALLOC;
    // all yield to senior
    isAYSActive = false;
    trancheAPRSplitRatio = FULL_ALLOC;

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
    instantWithdrawAprDelta = 1e18; // 1%
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

  /// @notice update instant withdraw delay
  /// @param _instantWithdrawDelay delay in seconds
  function setInstantWithdrawDelay(uint256 _instantWithdrawDelay) external {
    _checkOnlyOwnerOrManager();
    instantWithdrawDelay = _instantWithdrawDelay;
  }

  /// @notice update instant withdraw apr delta
  /// @param _instantWithdrawAprDelta min apr change to trigger instant withdraw
  function setInstantWithdrawAprDelta(uint256 _instantWithdrawAprDelta) external {
    _checkOnlyOwnerOrManager();
    instantWithdrawAprDelta = _instantWithdrawAprDelta;
  }

  /// @notice update disable instant withdraw flag
  /// @param _disableInstantWithdraw flag to disable instant withdraw
  function setDisableInstantWithdraw(bool _disableInstantWithdraw) external {
    _checkOnlyOwnerOrManager();
    disableInstantWithdraw = _disableInstantWithdraw;
  }

  /// @notice Start the epoch. No deposits or withdrawals are allowed after this.
  /// @dev We calculate the total funds that the borrower should return at the end of the epoch
  /// ie interests + withdraw requests. We send to the borrower underlyings amounts ie interests + 
  /// new deposits - instant withdraw requests if any. If funds are not enough to satisfy all requests
  /// then borrower should return the difference before instantWithdrawDeadline. After epoch start there
  /// should be no underlyings in this contract
  function startEpoch() external {
    _checkOnlyOwnerOrManager();

    isEpochRunning = true;
    // prevent deposits
    _pause();

    // prevent withdrawals requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;

    IdleCreditVault _strategy = IdleCreditVault(strategy);

    // calculate expected interest 
    // NOTE: all instant withdrawal requests, that burn tranche tokens and decrease getContractValue,
    // this can be done only prior to the start of the epoch so getContractValue() is the total amount net
    // of all instant withdrawal requests
    uint256 expectedAnnualInterest = _strategy.getApr() * getContractValue() / ONE_TRANCHE_TOKEN;
    expectedEpochInterest = expectedAnnualInterest * epochDuration / 365 days;
    // set expected epoch end date
    epochEndDate = block.timestamp + epochDuration;
    // set instant withdraw deadline
    instantWithdrawDeadline = block.timestamp + instantWithdrawDelay;
    // we should first check if there are *instant* redeem requests pending 
    // and if yes we should send as much underlyings as possible to the IdleCreditVault contract
    // if there is any surplus then we send those to the borrower
    uint256 pendingInstant = _strategy.pendingInstantWithdraws();
    uint256 totUnderlyings = _contractTokenBalance(token);
    // for new deposits in the epoch we should mint strategy tokens 1:1 even if those funds
    // are used for instant withdrawals
    _strategy.mintStrategyTokens(totEpochDeposits);
    totEpochDeposits = 0;
    // if there are more requests than the current underlyings we simply send all underlyings
    // to the IdleCreditVault contract
    if (pendingInstant > totUnderlyings) {
      _strategy.collectInstantWithdrawFunds(totUnderlyings);
      return;
    }
    // otherwise we send the amount needed to satisfy the requests to the strategy 
    _strategy.collectInstantWithdrawFunds(pendingInstant);
    // and transfer the surplus to the borrower
    IERC20Detailed(token).safeTransfer(_strategy.borrower(), totUnderlyings - pendingInstant);
  }

  /// @notice Stop epoch, accrue interest to the vault and get funds to fullfill normal
  /// (ie non-instant) withdraw requests from the prev epoch.
  /// @dev normal withdraw requests do not burn tranche tokens so tranche prices are increased
  /// only thanks to the interest accrued
  /// @param _newApr New apr to set for the next epoch
  /// @dev Only owner or manager can call this function. Borrower MUST approve this contract
  function stopEpoch(uint256 _newApr) external {
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
    uint256 _expectedInterest = expectedEpochInterest;
    uint256 _pendingWithdraws = _strategy.pendingWithdraws();

    // accrue interest to idleCDO, this will increase tranche prices.
    // Send also tot withdraw requests amount to the IdleCreditVault contract
    try this.getFundsFromBorrower(_expectedInterest, _pendingWithdraws, 0) {
      // transfer in strategy and decrease pendingWithdraws
      _collectFundsInStrategy(_pendingWithdraws, 0);

      // update tranche prices and unclaimed fees
      _updateAccounting();

      // transfer fees
      uint256 _fees = unclaimedFees;
      IERC20Detailed(token).safeTransfer(feeReceiver, _fees);
      unclaimedFees = 0;

      // save last apr
      lastEpochApr = _strategy.getApr();
      // set apr for next epoch
      _strategy.setApr(_newApr);

      // stop epoch
      isEpochRunning = false;
      expectedEpochInterest = 0;

      // allow deposits
      _unpause();
      // allow withdrawals requests
      allowAAWithdrawRequest = true;
      allowBBWithdrawRequest = true;
      // block instant withdraws as these can be done only after the deadline
      allowInstantWithdraw = false;

      emit AccrueInterest(_expectedInterest, _fees);
    } catch {
      // if borrower defaults, prev instant withdraw requests can still be withdrawn
      // as were already fullfilled prior to the default (all funds already sent to the strategy)
      allowInstantWithdraw = true;
      _handleBorrowerDefault();
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
    IERC20Detailed(token).safeTransferFrom(
      IdleCreditVault(strategy).borrower(), 
      address(this), 
      _amount + _withdrawRequests + _instantWithdrawRequests
    );
  }

  /// @dev Transfer funds to the IdleCreditVault contract and updated relative vars
  /// @param _withdrawRequest Amount of withdraw requests
  /// @param _instantWithdrawRequest Amount of instant withdraw requests
  function _collectFundsInStrategy(uint256 _withdrawRequest, uint256 _instantWithdrawRequest) internal {
    // transfer funds for withdraw to the IdleCreditVault contract
    if (_withdrawRequest > 0) {
      IdleCreditVault(strategy).collectWithdrawFunds(_withdrawRequest);
    }
    // transfer funds for instant withdraw to the IdleCreditVault contract
    if (_instantWithdrawRequest > 0) {
      IdleCreditVault(strategy).collectInstantWithdrawFunds(_instantWithdrawRequest);
    }
  }

  /// @notice Get funds from borrower to fullfill instant withdraw requests
  /// Manager should call this method after instantWithdrawDeadline (when epoch is running)
  function getInstantWithdrawFunds() external {
    _checkOnlyOwnerOrManager();

    if (block.timestamp < instantWithdrawDeadline) {
      revert EpochRunning();
    }

    IdleCreditVault _strategy = IdleCreditVault(strategy);
    uint256 _instantWithdraws = _strategy.pendingInstantWithdraws();
    // transfer funds for instant withdraw to the IdleCreditVault contract
    try this.getFundsFromBorrower(0, 0, _instantWithdraws) {
      // transfer in strategy and decrease pendingInstantWithdraws
      _collectFundsInStrategy(0, _instantWithdraws);
      // allow instant withdraws
      allowInstantWithdraw = true;
    } catch {
      _handleBorrowerDefault();
    }
  }

  /// @notice Handle borrower default
  function _handleBorrowerDefault() internal {
    defaulted = true;
    // prevent deposits
    _pause();

    // prevent withdrawals requests
    allowAAWithdrawRequest = false;
    allowBBWithdrawRequest = false;
  }

  /// 
  /// User methods
  ///

  /// @dev See {IdleCDO-_deposit}. In addition we update totEpochDeposits
  function _deposit(uint256 _amount, address _tranche, address _referral) internal override whenNotPaused returns (uint256 _minted) {
    totEpochDeposits += _amount;
    return super._deposit(_amount, _tranche, _referral);
  }

  /// @notice Request a withdraw from the vault of AA tranche
  /// @param _amount Amount of tranche tokens 
  function requestWithdrawAA(uint256 _amount) external {
    if (!allowAAWithdrawRequest) {
      revert NotAllowed();
    }
    _requestWithdraw(_amount, AATranche);
  }

  /// @notice Request a withdraw from the vault of BB tranche
  /// @param _amount Amount of tranche tokens 
  function requestWithdrawBB(uint256 _amount) external {
    if (!allowBBWithdrawRequest) {
      revert NotAllowed();
    }
    _requestWithdraw(_amount, BBTranche);
  }

  /// @notice Request a withdraw from the vault
  /// @param _amount Amount of tranche tokens 
  /// @param _tranche Tranche to withdraw from
  function _requestWithdraw(uint256 _amount, address _tranche) internal {
    if (isEpochRunning) {
      revert EpochRunning();
    }

    IdleCreditVault creditVault = IdleCreditVault(strategy);
    uint256 _underlyings = _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;

    if (!disableInstantWithdraw) {
      // If apr decresed wrt last epoch, request instant withdraw and burn tranche tokens directly
      if (lastEpochApr > (creditVault.getApr() + instantWithdrawAprDelta)) {
        // Check that user is not requesting too much instant withdraw
        if (maxWitdrawableInstant(msg.sender, _tranche) < _underlyings) {
          revert AmountTooHigh();
        }
        creditVault.requestInstantWithdraw(_underlyings, msg.sender);
        _withdrawOps(_amount, _underlyings, _tranche);
        return;
      }
    }

    // Check that user is not requesting too much withdraw
    if (maxWitdrawable(msg.sender, _tranche) < _underlyings) {
      revert AmountTooHigh();
    }
    // otherwise request normal withdraw, without burning tranche tokens yet
    creditVault.requestWithdraw(_underlyings, msg.sender);
  }

  /// @notice Get the max amount of underlyings that can be withdrawn by user
  /// @param _user User address
  /// @param _tranche Tranche to withdraw from
  function maxWitdrawable(address _user, address _tranche) public view returns (uint256) {
    uint256 currentUnderlyings = IERC20Detailed(_tranche).balanceOf(_user) * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    // add interest for one epoch
    uint256 interest = currentUnderlyings * IdleCreditVault(strategy).getApr() * epochDuration / 365 days;
    // sum and remove fees
    return currentUnderlyings + interest - (interest * fee / FULL_ALLOC);
  }

  /// @notice Get the max amount of underlyings that can be withdrawn instantly by user
  /// @param _user User address
  /// @param _tranche Tranche to withdraw from
  function maxWitdrawableInstant(address _user, address _tranche) public view returns (uint256) {
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

  /// @notice Claim a withdraw request from the vault for AA tranche
  function claimWithdrawRequestAA() external {
    return _claimWithdrawRequest(AATranche);
  }

  /// @notice Claim a withdraw request from the vault for BB tranche
  function claimWithdrawRequestBB() external {
    return _claimWithdrawRequest(BBTranche);
  }

  /// @notice Claim a withdraw request from the vault. Can be done when epoch is not running
  /// as funds will get transferred from borrower when epoch ends
  function _claimWithdrawRequest(address _tranche) internal {
    // Check that epoch is not running
    if (isEpochRunning) {
      revert EpochRunning();
    }

    IdleCreditVault _strategy = IdleCreditVault(strategy);

    // if borrower did not paid prev withdraw requests, revert. if instead he defaulted
    // only on instant withdraw requests but prev normal withdraws were fullfilled, we can still
    // allow normal withdraws
    if (defaulted && _strategy.pendingWithdraws() != 0) {
      revert BorrowerDefault();
    }

    uint256 requested = IdleCreditVault(strategy).claimWithdrawRequest(msg.sender);
    // calc tranche tokens to burn.
    uint256 _amount = requested * ONE_TRANCHE_TOKEN / _tranchePrice(_tranche);
    // burn tranche tokens and do last nav updates
    _withdrawOps(_amount, requested, _tranche);
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
}