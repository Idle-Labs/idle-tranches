// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IIdleCDOEpochVariant {
  function isEpochRunning() external view returns (bool);
  function epochEndDate() external view returns (uint256);
  function expectedEpochInterest() external view returns (uint256);
  function pendingWithdrawFees() external view returns (uint256);
  function fee() external view returns (uint256);
  function isInterestMinted() external view returns (bool);
  function getContractValue() external view returns (uint256);
  function lastNAVAA() external view returns (uint256);
  function lastNAVBB() external view returns (uint256);
  function trancheAPRSplitRatio() external view returns (uint256);
  function defaulted() external view returns (bool);
}

error NotAllowed();

contract IdleCreditVault is
  Initializable,
  OwnableUpgradeable,
  ERC20Upgradeable,
  ReentrancyGuardUpgradeable,
  IIdleCDOStrategy
{
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice underlying token address (pool currency for Clearpool)
  address public override token;
  /// @notice decimals of the underlying asset
  uint256 public override tokenDecimals;
  /// @notice one underlying token
  uint256 public override oneToken;
  /// @notice underlying ERC20 token contract (pool currency for Clearpool)
  IERC20Detailed public underlyingToken;
  /// @notice address of the IdleCDO
  address public idleCDO;
  /// @notice one year, used to calculate the APR
  uint256 public constant YEAR = 365 days;
  /// @notice latest saved apr, already scaled to include the buffer period
  uint256 public lastApr;
  /// @notice address of the borrower
  address public borrower;
  /// @notice address of the manager
  address public manager;
  /// @notice user withdraw requests
  mapping (address => uint256) public withdrawsRequests;
  /// @notice user instant withdraw requests
  mapping (address => uint256) public instantWithdrawsRequests;
  /// @notice total withdraw requests
  uint256 public pendingWithdraws;
  /// @notice pending instant withdraw requests
  uint256 public pendingInstantWithdraws;
  /// @notice counter for epoch deposits
  uint256 public totEpochDeposits;
  /// @notice deprecated transfer flag retained for storage compatibility
  bool public canTransfer;
  /// @notice last withdraw request epoch for a user
  mapping (address => uint256) public lastWithdrawRequest;
  /// @notice current epoch number
  uint256 public epochNumber;
  /// @notice unscaled apr
  uint256 public unscaledApr;
  /// @notice constant representing a 100% fee used for accounting
  uint256 private constant FULL_ALLOC = 100_000;
  /// @notice total principal for APR=0 requests in the current epoch
  uint256 public apr0TotalPrincipal;
  struct Apr0UserData {
    uint256 principal;
    uint256 principalEpoch;
    uint256 settledPrincipal;
    uint256 settledInterest;
  }
  /// @notice APR=0 withdraw data per user
  mapping (address => Apr0UserData) public apr0Users;
  /// @notice net APR=0 interest rate per epoch, scaled by 1e18
  mapping (uint256 => uint256) public apr0RateByEpoch;
  /// @notice default maximum allowed scaled apr
  uint256 public constant DEFAULT_MAX_APR = 20e18;
  /// @notice maximum allowed scaled apr, 0 disables the cap
  uint256 public maxApr;
  /// @notice underlying reserved for finalized post-default recovery claims
  uint256 public defaultRecoveryReserve;
  /// @notice post-default recovery ratio, scaled by 1e18
  uint256 public defaultRecoveryPrice;
  /// @notice strategy epoch that defaulted and was finalized for recovery
  uint256 public defaultRecoveryEpoch;
  /// @notice true once the CDO finalized default recovery accounting
  bool public defaultRecoveryFinalized;
  /// @notice true when unfunded default-epoch instant receipts were included in recovery accounting
  bool public defaultInstantWithdrawsFinalized;
  /// @notice normal withdraw receipt basis by user and request epoch
  mapping(address => mapping(uint256 => uint256)) public withdrawsRequestsByEpoch;
  /// @notice post-default withdraw requests that are already backed by default recovery reserve
  mapping(address => uint256) public postDefaultRequests;
  /// @notice instant withdraw receipt basis by user and request epoch
  mapping(address => mapping(uint256 => uint256)) public instantWithdrawsRequestsByEpoch;
  /// @notice total outstanding instant-withdraw receipt basis per request epoch
  mapping(uint256 => uint256) public instantWithdrawClaimsByEpoch;
  /// @notice funded recovery ratio for pending withdraw receipts haircutted by stopEpochWithDuration loss
  mapping(uint256 => uint256) public lossRecoveryPriceByEpoch;
  /// @notice true once default-recovery request accounting is initialized for this strategy
  bool public defaultRecoveryInitialized;
  /// @notice full recovery ratio scale
  uint256 private constant RECOVERY_FULL = 1e18;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    token = address(1);
  }

  /// @notice can be only called once
  /// @param _underlyingToken address of the underlying token (pool currency)
  function initialize(
    address _underlyingToken,
    address _owner,
    address _manager,
    address _borrower,
    string memory borrowerName,
    uint256 _apr
  ) public virtual initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    require(token == address(0), "Token is already initialized");

    //----- // -------//
    token = _underlyingToken;
    underlyingToken = IERC20Detailed(token);
    tokenDecimals = underlyingToken.decimals();
    oneToken = 10**(tokenDecimals);
    borrower = _borrower;
    manager = _manager;
    maxApr = DEFAULT_MAX_APR;
    // on the first setup we set the lastApr equal to the unscaledApr
    lastApr = _apr;
    unscaledApr = _apr;
    defaultRecoveryInitialized = true;

    // name will be like: Pareto Credit Vault Borrower
    // symbol will be like: Borrower
    ERC20Upgradeable.__ERC20_init(
      _concat(string("Pareto Credit Vault "), borrowerName),
      borrowerName
    );
    //------//-------//

    transferOwnership(_owner);
  }

  /// @notice strategy token decimals
  /// @dev equal to underlying token decimals
  /// @return number of decimals
  function decimals() public view override returns (uint8) {
    return uint8(tokenDecimals);
  }

  /// @notice strategy token address
  function strategyToken() external view override returns (address) {
    return address(this);
  }

  /// @notice return strategy token price which is always 1
  /// @return price in underlyings
  function price() public view virtual override returns (uint256) {
    return oneToken;
  }

  /// @notice current fixed apr for the epoch
  function getApr() external view returns (uint256) {
    return lastApr;
  }

  /// @notice set manager address
  /// @param _manager address of the new manager
  function setManager(address _manager) external onlyOwner {
    manager = _manager;
  }

  /// @notice set borrower address
  /// @param _borrower address of the new borrower
  function setBorrower(address _borrower) external onlyOwner {
    require(_borrower != address(0), "IS_0");
    borrower = _borrower;
  }

  /// @notice set maximum allowed scaled apr, 0 disables the cap
  /// @param _maxApr new max apr
  function setMaxApr(uint256 _maxApr) external onlyOwner {
    maxApr = _maxApr;
  }

  /// @notice set both the scaled and unscaled apr
  /// @dev only cdo and manager can set the apr.
  /// @param _unscaledApr unscaled apr
  /// @param _apr scaled apr
  function setAprs(uint256 _unscaledApr, uint256 _apr) external {
    unscaledApr = _unscaledApr;
    // here we also check that msg.sender is allowed
    setApr(_apr);
  }

  /// @notice set both the unscaled APR and APR scaled by epoch plus buffer duration.
  /// @dev only CDO and manager can set the APR through `setApr`.
  /// @param _unscaledApr unscaled APR
  /// @param _duration epoch duration
  /// @param _buffer buffer duration
  function setAprsWithBuffer(uint256 _unscaledApr, uint256 _duration, uint256 _buffer) external {
    unscaledApr = _unscaledApr;
    setApr(_duration == 0 ? _unscaledApr : _unscaledApr * (_duration + _buffer) / _duration);
  }

  /// @notice set the fixed apr
  /// @dev only cdo and manager can set the apr. If manager manually set apr from 
  /// here it will not be scaled to include the buffer period
  function setApr(uint256 _apr) public {
    address _cdo = idleCDO;

    // if cdo is not yet set we skip the check (this can happen only during the setup)
    if (_cdo != address(0)) {
      if (msg.sender != _cdo && msg.sender != manager) revert NotAllowed();
    }
    uint256 _maxApr = maxApr;
    if (_maxApr != 0 && _apr > _maxApr) revert NotAllowed();
    lastApr = _apr;
  }

  /// @notice request withdraw of underlying token from the vault
  /// @dev We don't burn strategy tokens here, but we increase the withdraw requests. A user must
  /// claim a loss-adjusted receipt before opening a later request so its recovery epoch is preserved.
  /// @param _amount number of tokens claimable by the user
  /// @param _user address of the user
  /// @param _principal principal amount backing the withdraw request
  function requestWithdraw(uint256 _amount, address _user, uint256 _principal) external {
    _onlyIdleCDO();
    _ensureDefaultRecoveryInitialized();
    if (_amount == 0) return;
    if (defaultRecoveryFinalized) {
      // user should first claim old already-funded withdraw requests before requesting new ones after default
      if (_hasWithdrawRequest(_user) || instantWithdrawsRequests[_user] != 0 || postDefaultRequests[_user] != 0) {
        revert NotAllowed();
      }
      // Preserve request/claim UX after default without increasing borrower-facing pendingWithdraws.
      // The CDO passes an already-haircut amount because finalization lowered virtualPrice first.
      _burn(msg.sender, _amount);
      _mint(_user, _amount);
      postDefaultRequests[_user] = _amount;
      return;
    }
    bool isClosed = IIdleCDOEpochVariant(idleCDO).epochEndDate() == 0;
    uint256 currentEpoch = epochNumber;
    uint256 lossEpoch = lastWithdrawRequest[_user];
    uint256 lossRecoveryPrice = lossRecoveryPriceByEpoch[lossEpoch];
    if (
      lossRecoveryPrice != 0 &&
      (withdrawsRequestsByEpoch[_user][lossEpoch] != 0 ||
      (apr0Users[_user].principal != 0 && apr0Users[_user].principalEpoch == lossEpoch))
    ) {
      // A loss-adjusted receipt must be claimed before opening a later request, otherwise
      // `lastWithdrawRequest` would stop pointing to the epoch that stores its haircut.
      revert NotAllowed();
    }
    // burn strategy tokens from cdo (we don't burn future interest here, only the principal)
    _burn(msg.sender, _principal);
    // mint equal amount of strategy tokens to the user as receipt (interest included), useful in case of default
    _mint(_user, _amount);
    // A successfully closed pool already recalled all funds and has no later stopEpoch.
    if (!isClosed) {
      // Global amount that stopEpoch must source from borrower/strategy for all pending receipts.
      pendingWithdraws += _amount;
    }
    // save the epoch of the last withdraw request (buffer + epochDuration is 1 epoch)
    lastWithdrawRequest[_user] = currentEpoch;
    // APR=0 requests keep separate accounting and settle interest at stopEpoch.
    // `_amount` here is the post-management-fee principal bucket for that flow.
    if (unscaledApr == 0 && !isClosed) {
      _requestWithdrawApr0(_amount, _user);
    } else {
      // increase the withdraw requests for the user
      // we record both per-user (old, kept for compatibility) and per-epoch so
      // on finalization we can distinguish "default-epoch pending receipts"
      // from old funded receipts.
      withdrawsRequests[_user] += _amount;
      withdrawsRequestsByEpoch[_user][currentEpoch] += _amount;
    }
  }

  /// @notice claim the withdraw request
  /// @dev we burn the strategy tokens and transfer the underlying tokens
  /// @param _user address of the user
  /// @return amount number of tokens claimed
  function claimWithdrawRequest(address _user) external returns (uint256 amount) {
    _onlyIdleCDO();
    if (defaultRecoveryFinalized) {
      // Post-default requests are already priced after the haircut and backed by the reserve,
      // so they must not fall through to the defaulted-epoch receipt logic.
      amount = _claimPostDefaultWithdrawRequest(_user);
      if (amount != 0) return amount;
      // Only receipts created in the defaulted epoch are haircutted here; old fulfilled
      // receipts are handled below at par if they were already funded before default.
      amount = _claimDefaultedWithdrawRequest(_user);
    }
    amount += _claimLossAdjustedWithdrawRequest(_user);
    return amount + _claimFundedWithdrawRequest(_user);
  }

  /// @notice Claim a funded non-default withdraw request at par.
  /// @param _user address of the user
  /// @return amount amount claimed
  function _claimFundedWithdrawRequest(address _user) internal returns (uint256 amount) {
    // User should wait at least an epoch before claiming the withdraw. Once the epoch is over user can withdraw 
    // at any time even if a new epoch started. 
    // So if epochNumber is the same as the last withdraw request then we revert. Epoch number is increased at stopEpoch
    // NOTE: If a user does not claim a withdraw request and instead requests another withdraw, he will have to wait
    // for another epoch to claim both requests.
    // NOTE 2: if borrower defaults, old withdraw requests can still be claimed
    if (IIdleCDOEpochVariant(idleCDO).epochEndDate() != 0 && (epochNumber <= lastWithdrawRequest[_user])) {
      revert NotAllowed();
    }
    // settle APR=0 requests once the related epoch has ended
    _settleApr0(_user);
    Apr0UserData storage _apr0User = apr0Users[_user];
    // Claim includes:
    // - settled APR0 principal from finalized epochs
    // - still-open APR0 principal: if pool-close mode was used (_interest == 1), IdleCDO sets
    //   epochEndDate = 0 and claims can be immediate, while _settleApr0 can still skip settlement
    //   for the current request epoch (reqEpoch >= epochNumber).
    // - settled APR0 interest
    uint256 normalAmount = withdrawsRequests[_user];
    uint256 apr0PrincipalAmount = _apr0User.settledPrincipal + _apr0User.principal;
    uint256 apr0InterestAmount = _apr0User.settledInterest;
    amount = normalAmount + apr0PrincipalAmount + apr0InterestAmount;
    // burn strategy tokens 1:1 with the principal only (normal amount already includes interest)
    _burn(_user, normalAmount + apr0PrincipalAmount);
    withdrawsRequests[_user] = 0;
    lastWithdrawRequest[_user] = 0;
    if (apr0PrincipalAmount != 0 || apr0InterestAmount != 0) {
      delete apr0Users[_user];
    }
    _transferFundedClaim(_user, amount);
  }

  /// @notice request instant withdraw of underlying token from the vault
  /// @dev we burn strategy tokens here, and we increase the instant withdraw requests
  /// @param _amount number of tokens to withdraw
  /// @param _user address of the user
  function requestInstantWithdraw(uint256 _amount, address _user) external {
    _onlyIdleCDO();
    _ensureDefaultRecoveryInitialized();
    // burn strategy tokens from cdo
    _burn(msg.sender, _amount);
  
    // mint equal amount of strategy tokens to the user as receipt, useful in case of default
    _mint(_user, _amount);

    // increase the instant withdraw requests for the user
    instantWithdrawsRequests[_user] += _amount;
    uint256 currentEpoch = epochNumber;
    // we record both per-user (old, kept for compatibility) and per-epoch so on
    // finalization we can distinguish "default-epoch pending instant receipts"
    // from old funded instant receipts.
    instantWithdrawsRequestsByEpoch[_user][currentEpoch] += _amount;
    instantWithdrawClaimsByEpoch[currentEpoch] += _amount;
    // increase the total instant withdraw requests
    pendingInstantWithdraws += _amount;
  }

  /// @notice claim the instant withdraw request
  /// @dev we transfer the underlying tokens
  /// @param _user address of the user
  function claimInstantWithdrawRequest(address _user) external {
    _onlyIdleCDO();
    if (defaultRecoveryFinalized && defaultInstantWithdrawsFinalized) {
      // Clear the defaulted-epoch instant receipt first, then continue so the same call can
      // also pay any older instant receipt that was already funded before default finalization.
      _claimDefaultedInstantWithdrawRequest(_user);
    }
    uint256 amount = instantWithdrawsRequests[_user];
    // burn strategy tokens from user
    _burn(_user, amount);

    instantWithdrawsRequests[_user] = 0;
    _transferFundedClaim(_user, amount);
  }

  /// @notice collect the instant withdraw funds
  /// @dev only IdleCDO can call this function
  /// @param _amount number of tokens to collect
  function collectInstantWithdrawFunds(uint256 _amount) external {
    _onlyIdleCDO();
    pendingInstantWithdraws -= _amount;
    underlyingToken.safeTransferFrom(idleCDO, address(this), _amount);
  }

  /// @notice collect borrower-funded withdraw receipt funds
  /// @dev Only IdleCDO can call this function. When `_amount` is lower than the
  /// pending basis, the difference is a stopEpochWithDuration loss assigned to
  /// pending receipts and users later claim through `lossRecoveryPriceByEpoch`.
  /// Reverts if the resulting recovery price rounds to zero at `RECOVERY_FULL` precision.
  /// @param _amount number of funded tokens to collect
  function collectWithdrawFunds(uint256 _amount) external {
    _onlyIdleCDO();
    uint256 pendingBasis = pendingWithdraws;
    if (_amount < pendingBasis) {
      // Legacy receipts do not have per-epoch ownership data, so they can only be fully funded.
      if (!defaultRecoveryInitialized) revert NotAllowed();
      uint256 lossRecoveryPrice = _amount * RECOVERY_FULL / pendingBasis;
      // Avoid storing a zero price, which is indistinguishable from "no loss-adjusted epoch".
      if (lossRecoveryPrice == 0) revert NotAllowed();
      pendingWithdraws = 0;
      lossRecoveryPriceByEpoch[epochNumber] = lossRecoveryPrice;
    } else {
      // A plain implementation upgrade may leave legacy normal receipts pending. Their next
      // successful stop can fully fund the aggregate before lazy initialization occurs.
      pendingWithdraws = pendingBasis - _amount;
    }
    if (_amount != 0) {
      underlyingToken.safeTransferFrom(idleCDO, address(this), _amount);
    }
  }

  /// @notice Preview how a realized stop-epoch loss is split between active LPs and pending receipts.
  /// @dev Without pending receipts, a loss cannot exceed its active basis. When pending receipts
  /// exist, all pending receipts share their aggregate portion of the loss pro rata because the
  /// pending bucket does not retain tranche identity. The remaining active loss is later applied
  /// by the CDO through its ordinary BB-first waterfall.
  /// @param _lossAmount realized loss amount
  /// @return pendingToFund amount of pending withdrawals that should be funded by the borrower
  /// @return activeLoss amount of loss that remains assigned to active LPs
  function previewLossAdjustedWithdrawFunds(uint256 _lossAmount) external view returns (uint256 pendingToFund, uint256 activeLoss) {
    uint256 pendingBasis = pendingWithdraws;
    // Full zero-loss funding is safe for legacy aggregate receipts and needs no migration call.
    if (_lossAmount == 0) return (pendingBasis, _lossAmount);

    IIdleCDOEpochVariant cdo = IIdleCDOEpochVariant(idleCDO);
    uint256 activeBasis = _lossActiveBasis(cdo);
    if (pendingBasis == 0) {
      if (_lossAmount > activeBasis) revert NotAllowed();
      return (0, _lossAmount);
    }

    // Legacy pending receipts do not have the per-epoch ownership data needed to store a haircut.
    if (!defaultRecoveryInitialized) revert NotAllowed();
    uint256 totalBasis = activeBasis + pendingBasis;
    if (_lossAmount >= totalBasis) revert NotAllowed();

    uint256 pendingLoss = _lossAmount * pendingBasis / totalBasis;
    pendingToFund = pendingBasis - pendingLoss;
    activeLoss = _lossAmount - pendingLoss;
  }

  /// @notice Calculate the active basis used to split a successful stop-epoch loss.
  /// @dev Minted fee shares remain backed by CDO-held strategy tokens and therefore join the
  /// active-side loss. Cash mode mirrors CDO accounting: management fees are already accrued,
  /// then performance fees apply only to gain above the last saved AA plus BB NAV.
  /// @param _cdo epoch CDO interface
  /// @return activeBasis active strategy-token basis participating in the loss
  function _lossActiveBasis(IIdleCDOEpochVariant _cdo) internal view returns (uint256 activeBasis) {
    if (_cdo.isInterestMinted()) {
      // Accrued fees become AA shares before the loss burn, so the full CDO strategy-token
      // balance plus gross minted interest participates on the active side.
      return balanceOf(idleCDO) + _cdo.expectedEpochInterest();
    }
    uint256 activeBasisBeforePerfFee = _cdo.getContractValue();
    uint256 expectedInterest = _cdo.expectedEpochInterest();
    uint256 pendingFees = _cdo.pendingWithdrawFees();
    if (expectedInterest > pendingFees) {
      activeBasisBeforePerfFee += expectedInterest - pendingFees;
    }
    uint256 savedNAV = _cdo.lastNAVAA() + _cdo.lastNAVBB();
    activeBasis = activeBasisBeforePerfFee > savedNAV ? 
      activeBasisBeforePerfFee - ((activeBasisBeforePerfFee - savedNAV) * _cdo.fee() / FULL_ALLOC) : 
      activeBasisBeforePerfFee;
  }

  /// @notice compute and apply APR=0 epoch deltas for stopEpoch
  /// @param _interest stopEpoch override interest (0 = expected epoch interest, 1 = repay all)
  /// @return _expInterest stopEpoch interest after APR0 adjustments
  /// @return _adjPendingWithdrawFees pending withdraw fees after APR0 adjustments
  function prepareStopEpochWithApr0(uint256 _interest) external returns (uint256 _expInterest, uint256 _adjPendingWithdrawFees) {
    _onlyIdleCDO();
    IIdleCDOEpochVariant _cdo = IIdleCDOEpochVariant(idleCDO);
    uint256 _pendingFees = _cdo.pendingWithdrawFees();
    uint256 _tvl = _cdo.getContractValue();
    _expInterest = _interest > 1 ? _interest : _cdo.expectedEpochInterest();
    _adjPendingWithdrawFees = _pendingFees;
    // Principal currently waiting for withdraw that was requested while APR was 0,
    // net of the upfront management fee charged at request time.
    uint256 _principal = apr0TotalPrincipal;

    // Fast path: no APR0 accounting needed.
    if (_principal == 0) {
      return (_expInterest, _adjPendingWithdrawFees);
    }
    // APR0 principal is only valid while APR is 0 for that request lifecycle.
    if (unscaledApr != 0) {
      revert NotAllowed();
    }

    uint256 _apr0NetInterest;
    // APR0 allocation is computed only when stopEpoch receives a real override interest.
    // _expectedInterest == 1 is the "request all funds back" sentinel and is handled in IdleCDO.
    if (_expInterest > 1 && _expInterest > _pendingFees) {
      // Remove already booked withdraw fees from the interest base before splitting.
      uint256 _interestNetOfFees = _expInterest - _pendingFees;
      // Total principal used for the pro-rata split:
      // IdleCDO TVL (which excludes APR0 requested principal) + APR0 principal bucket.
      uint256 _totalPrincipalForSplit = _tvl + _principal;
      if (_totalPrincipalForSplit != 0) {
        // APR0 users get a pro-rata share of realized interest.
        uint256 _apr0InterestGross = _interestNetOfFees * _principal / _totalPrincipalForSplit;
        if (_apr0InterestGross != 0) {
          // Same fee model as normal withdraw interest.
          uint256 _apr0Fee = _apr0InterestGross * _cdo.fee() / FULL_ALLOC;
          _apr0NetInterest = _apr0InterestGross - _apr0Fee;
          _adjPendingWithdrawFees += _apr0Fee;
          _expInterest -= _apr0NetInterest;
        }
      }
    }

    // Finalize one-epoch APR0 interest for current epoch only.
    if (_apr0NetInterest != 0) {
      // Funds owed to withdraw requesters increase by APR0 net interest.
      pendingWithdraws += _apr0NetInterest;
      // Save per-epoch net rate; each APR0 request accrues exactly once on its request epoch.
      apr0RateByEpoch[epochNumber] = (_apr0NetInterest * 1e18) / _principal;
    }
    // Close current APR0 bucket so it cannot accrue again on later stopEpoch calls.
    apr0TotalPrincipal = 0;
  }

  /// @notice settle APR=0 requests for a user once their epoch is finalized
  /// @param _user address of the user
  function _settleApr0(address _user) internal {
    Apr0UserData storage _apr0User = apr0Users[_user];
    uint256 _principal = _apr0User.principal;
    if (_principal == 0) {
      return;
    }
    uint256 _reqEpoch = _apr0User.principalEpoch;
    // Settle only after stopEpoch bumped epochNumber (ie after one full wait epoch).
    if (_reqEpoch >= epochNumber) {
      return;
    }
    // Move principal from "open APR0 bucket" to "settled bucket" (same principal, not duplicated).
    _apr0User.settledPrincipal += _principal;
    uint256 _rate = apr0RateByEpoch[_reqEpoch];
    if (_rate != 0) {
      // Convert per-epoch rate to claimable underlying interest.
      _apr0User.settledInterest += (_principal * _rate) / 1e18;
    }
    _apr0User.principal = 0;
    _apr0User.principalEpoch = 0;
  }

  function _requestWithdrawApr0(uint256 _amount, address _user) internal {
    // Settle any previous APR0 request first, then start/update current epoch bucket.
    _settleApr0(_user);
    Apr0UserData storage _apr0User = apr0Users[_user];
    if (_apr0User.principal == 0) {
      _apr0User.principalEpoch = epochNumber;
    }
    _apr0User.principal += _amount;
    // Epoch-level APR0 principal used only to compute stopEpoch APR0 pro-rata interest.
    apr0TotalPrincipal += _amount;
  }

  /// @notice Send funds to the IdleCDO
  /// @param _amount number of underlyings to transfer
  function sendInterestAndDeposits(uint256 _amount) external {
    _onlyIdleCDO();
    IERC20Detailed(token).safeTransfer(idleCDO, _amount);
  }

  /// @notice Burn strategy tokens from the CDO
  /// @param _amount number of strategy tokens (1:1 with underlyings) to burn
  function burnStrategyTokens(uint256 _amount) external {
    _onlyIdleCDO();
    _burn(msg.sender, _amount);
  }

  /// @notice Get funds from IdleCDO and mint strategy tokens. Funds are not sent to the borrower here
  /// @param _amount number of underlyings to transfer
  function deposit(uint256 _amount)
    external
    virtual
    override
    returns (uint256) {
    _onlyIdleCDO();
    if (_amount > 0) {
      underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
      _mint(msg.sender, _amount);
    }

    if (IIdleCDOEpochVariant(idleCDO).isEpochRunning()) {
      // deposit done on stopEpoch (before setting the var to false) so we reset the counter
      totEpochDeposits = 0;
      epochNumber += 1;
    } else {
      // deposit done between epochs so we increase the counter
      totEpochDeposits += _amount;
    }

    return _amount;
  }

  /// @notice Mint strategy tokens to the CDO without moving underlyings
  /// @dev Used for mid-epoch deposits that send funds directly to the borrower
  function mintStrategyTokens(uint256 _amount) external {
    _onlyIdleCDO();
    _mint(msg.sender, _amount);
  }

  /// @notice Reserve already-held underlying for a later finalized default recovery.
  /// @dev Called by the CDO when borrower funding fails after funds were already returned here.
  /// @param _amount amount of underlying already held by this strategy for default recovery
  function reserveDefaultRecovery(uint256 _amount) external {
    _onlyIdleCDO();
    if (defaultRecoveryFinalized) revert NotAllowed();
    defaultRecoveryReserve += _amount;
  }

  /// @notice Total claim basis that should be haircut by default finalization.
  /// @dev Normal pending withdraws are already tracked globally. Current-epoch instant receipts
  /// join recovery only if `pendingInstantWithdraws` is still non-zero at finalization. This can
  /// happen when startEpoch moved the CDO's available cash to the strategy but that cash covered
  /// only part of the instant queue. The full current-epoch instant claim is included as basis,
  /// while the already-funded part is added to the reserve by `_defaultPrefundedInstantReserve()`.
  /// Receipt accounting is aggregate and does not retain AA/BB identity. IdleCDOEpochVariant
  /// therefore applies one recovery multiplier to both tranche classes.
  /// @return basis amount of defaulted receipt claims in underlying units
  function defaultPendingClaimBasis() public view returns (uint256 basis) {
    basis = pendingWithdraws;
    if (pendingInstantWithdraws != 0) {
      basis += instantWithdrawClaimsByEpoch[epochNumber];
    }
  }

  /// @notice Finalize strategy-side default recovery accounting.
  /// @dev Called by the CDO. `_recoverySource` must approve this strategy for `_recoveredAmount`.
  /// `_recoveredAmount` is the exact external recovery to pull; already-held strategy funds
  /// are added separately because they should not be pulled from `_recoverySource` again.
  /// A zero or subprecision aggregate recovery finalizes at price zero. Active tranche prices are
  /// then zero and pending receipts can be cleared without a payout; any positive reserve too small
  /// to represent at `RECOVERY_FULL` precision remains isolated as recovery dust.
  /// @param _recoveredAmount exact amount of recovered underlying supplied by `_recoverySource`
  /// @param _recoverySource address that supplies recovered underlying
  /// @return defaultBBNav BB's final recovered active NAV
  function finalizeDefaultRecovery(uint256 _recoveredAmount, address _recoverySource) external returns (uint256 defaultBBNav) {
    _onlyIdleCDO();
    _ensureDefaultRecoveryInitialized();

    IIdleCDOEpochVariant cdo = IIdleCDOEpochVariant(idleCDO);
    if (defaultRecoveryFinalized || !cdo.defaulted()) revert NotAllowed();
    if (_recoveredAmount != 0 && _recoverySource == address(0)) revert NotAllowed();

    // Active holders are still represented by strategy tokens owned by the CDO. Add the
    // default-epoch net interest so they use the same claim basis as pending redeemers.
    // Split gross backing by saved NAV and default interest by the configured APR split.
    // The CDO strategy-token balance is its gross active value before `unclaimedFees`.
    // Using it directly restores those waived unpaid fees to active recovery basis.
    uint256 activeBalance = balanceOf(idleCDO);
    uint256 activeInterest = _defaultActiveInterestBasis(cdo);
    uint256 activeBasis = activeBalance + activeInterest;
    defaultBBNav = _defaultBBBasis(cdo, activeBalance, activeInterest);
    // Pending receipts have already left active CDO NAV, so they are added as a separate basis.
    uint256 pendingBasis = defaultPendingClaimBasis();
    uint256 totalBasis = activeBasis + pendingBasis;
    if (totalBasis == 0) revert NotAllowed();

    // Some recovery funds may already be in this strategy: partially prefunded instant requests
    // and borrower-send funds that failed at epoch start. Count both without pulling them again.
    uint256 prefundedReserve = _defaultPrefundedInstantReserve();
    uint256 reserveAmount = _recoveredAmount + prefundedReserve + defaultRecoveryReserve;
    // Recovery can be above par if the recovered funds exceed the computed basis.
    uint256 recoveryPrice = reserveAmount * RECOVERY_FULL / totalBasis;

    defaultRecoveryFinalized = true;
    defaultRecoveryReserve = reserveAmount;
    defaultRecoveryPrice = recoveryPrice;
    defaultRecoveryEpoch = epochNumber;
    // A non-zero pending instant bucket means current-epoch instant receipts were not fully funded
    // and must be paid through the same recovery ratio as normal pending receipts.
    defaultInstantWithdrawsFinalized = pendingInstantWithdraws != 0;
    // Bring active CDO NAV to the same recovery ratio. IdleCDOEpochVariant then calls
    // _forceUpdateAccounting so tranche prices/virtualPrice expose the crystallized loss.
    uint256 activeFinalNAV = (activeBasis * recoveryPrice) / RECOVERY_FULL;
    defaultBBNav = defaultBBNav * recoveryPrice / RECOVERY_FULL;
    if (activeBalance > activeFinalNAV) {
      _burn(idleCDO, activeBalance - activeFinalNAV);
    } else if (activeFinalNAV > activeBalance) {
      _mint(idleCDO, activeFinalNAV - activeBalance);
    }
    if (_recoveredAmount != 0) {
      // Pull external recovery last: if the transfer fails, the whole finalization reverts.
      underlyingToken.safeTransferFrom(_recoverySource, address(this), _recoveredAmount);
    }
  }

  /// @notice Get current-epoch instant-withdraw funds already collected before default finalization.
  /// @dev `pendingInstantWithdraws` is the still-unfunded remainder. If it is lower than the
  /// current-epoch claim basis, the difference is already-held underlying reserved for those claims.
  /// @return prefundedReserve amount of current instant claims already backed by strategy underlyings
  function _defaultPrefundedInstantReserve() internal view returns (uint256 prefundedReserve) {
    uint256 pendingInstant = pendingInstantWithdraws;
    if (pendingInstant == 0) return prefundedReserve;
    uint256 instantBasis = instantWithdrawClaimsByEpoch[epochNumber];
    if (instantBasis > pendingInstant) {
      prefundedReserve = instantBasis - pendingInstant;
    }
  }

  /// @notice Calculate default-epoch net interest basis for active LPs.
  /// @param _cdo epoch CDO interface
  /// @return activeInterest net interest basis for active LPs
  function _defaultActiveInterestBasis(IIdleCDOEpochVariant _cdo) internal view returns (uint256 activeInterest) {
    uint256 expectedInterest = _cdo.expectedEpochInterest();
    uint256 pendingFees = _cdo.pendingWithdrawFees();
    if (expectedInterest <= pendingFees) return activeInterest;
    // Pending redeemers already include their net interest in pendingWithdraws; active LPs need
    // the same borrower-owed interest basis, net of performance fees, before applying recovery.
    activeInterest = expectedInterest - pendingFees;
    activeInterest -= activeInterest * _cdo.fee() / FULL_ALLOC;
  }

  /// @notice Calculate BB's active claim basis before applying the default recovery multiplier.
  /// @dev Gross active backing is split by saved NAV, while interest follows the configured APR split.
  /// @param _cdo epoch CDO interface
  /// @param _activeBalance gross active strategy-token backing
  /// @param _activeInterest net active default-epoch interest
  /// @return bbBasis BB's active claim basis before recovery
  function _defaultBBBasis(IIdleCDOEpochVariant _cdo, uint256 _activeBalance, uint256 _activeInterest) internal view returns (uint256 bbBasis) {
    uint256 savedAA = _cdo.lastNAVAA();
    uint256 savedBB = _cdo.lastNAVBB();
    uint256 activeBasis = _activeBalance + _activeInterest;
    if (savedBB == 0 || activeBasis == 0) return bbBasis;
    if (savedAA == 0) return activeBasis;

    uint256 savedNAV = savedAA + savedBB;
    uint256 grossBBBasis = _activeBalance * savedBB / savedNAV;
    uint256 bbInterest = _activeInterest * (FULL_ALLOC - _cdo.trancheAPRSplitRatio()) / FULL_ALLOC;
    bbBasis = grossBBBasis + bbInterest;
  }

  /// @notice Claim an already-funded post-default withdraw request.
  /// @param _user address of the user
  /// @return amount amount claimed from default recovery reserve
  function _claimPostDefaultWithdrawRequest(address _user) internal returns (uint256 amount) {
    amount = postDefaultRequests[_user];
    if (amount == 0) return amount;
    postDefaultRequests[_user] = 0;
    // Post-default receipts are paid 1:1 because the haircut was applied when the request was made.
    _burn(_user, amount);
    _transferDefaultRecovery(_user, amount);
  }

  /// @notice Claim a defaulted normal withdraw receipt with the finalized recovery haircut.
  /// @param _user address of the user
  /// @return amount amount paid from default recovery reserve
  function _claimDefaultedWithdrawRequest(address _user) internal returns (uint256 amount) {
    uint256 defaultEpoch = defaultRecoveryEpoch;
    (uint256 claimBasis, uint256 burnAmount) = _clearWithdrawClaimForEpoch(_user, defaultEpoch, true);
    if (claimBasis == 0) return amount;

    // pendingWithdraws stores the claim basis owed by the borrower, including APR0 interest.
    pendingWithdraws -= claimBasis;
    // Only receipt principal exists as strategy tokens. APR0 interest is included in claimBasis
    // but was never minted as a user strategy-token receipt.
    _burn(_user, burnAmount);
    amount = (claimBasis * defaultRecoveryPrice) / RECOVERY_FULL;
    _transferDefaultRecovery(_user, amount);
  }

  /// @notice Claim a stopEpochWithDuration loss-adjusted withdraw receipt.
  /// @param _user address of the user
  /// @return amount amount paid from funded strategy underlyings
  function _claimLossAdjustedWithdrawRequest(address _user) internal returns (uint256 amount) {
    uint256 lossEpoch = lastWithdrawRequest[_user];
    uint256 lossRecoveryPrice = lossRecoveryPriceByEpoch[lossEpoch];
    if (lossRecoveryPrice == 0) return amount;

    (uint256 claimBasis, uint256 burnAmount) = _clearWithdrawClaimForEpoch(_user, lossEpoch, false);
    if (claimBasis == 0) return amount;

    // pendingWithdraws was already cleared when the borrower funded the loss-adjusted amount.
    _burn(_user, burnAmount);
    amount = (claimBasis * lossRecoveryPrice) / RECOVERY_FULL;
    _transferFundedClaim(_user, amount);
  }

  /// @notice Clear a normal/APR0 withdraw receipt for one request epoch.
  /// @dev This does not move funds or burn receipt tokens. Default claims also decrease
  /// `apr0TotalPrincipal`; loss-adjusted claims do not because stopEpoch already closed that bucket.
  /// @param _user address of the user
  /// @param _claimEpoch epoch whose receipt should be cleared
  /// @param _isClearingApr0 true when clearing an open APR0 default claim
  /// @return claimBasis claim amount before applying the recovery ratio
  /// @return burnAmount strategy-token receipt amount to burn
  function _clearWithdrawClaimForEpoch(address _user, uint256 _claimEpoch, bool _isClearingApr0) internal returns (uint256 claimBasis, uint256 burnAmount) {
    (claimBasis, burnAmount) = _withdrawClaimAmountsForEpoch(_user, _claimEpoch);
    if (claimBasis == 0) return (claimBasis, burnAmount);

    uint256 normalAmount = withdrawsRequestsByEpoch[_user][_claimEpoch];
    if (normalAmount != 0) {
      withdrawsRequestsByEpoch[_user][_claimEpoch] = 0;
      // The aggregate may also include older funded receipts; clear only this epoch's piece.
      withdrawsRequests[_user] -= normalAmount;
    }
    Apr0UserData storage apr0User = apr0Users[_user];
    if (apr0User.principal != 0 && apr0User.principalEpoch == _claimEpoch) {
      if (_isClearingApr0) {
        uint256 apr0Principal = apr0User.principal;
        uint256 totalApr0Principal = apr0TotalPrincipal;
        // prepareStopEpochWithApr0 may already close the global APR0 bucket before default finalization.
        apr0TotalPrincipal = apr0Principal >= totalApr0Principal ? 0 : totalApr0Principal - apr0Principal;
      }
      apr0User.principal = 0;
      apr0User.principalEpoch = 0;
    }
    if (lastWithdrawRequest[_user] == _claimEpoch) {
      // The cleared epoch was the latest request marker. Any remaining normal/APR0 receipt
      // is older and already funded, so it can continue to the funded-claim path.
      lastWithdrawRequest[_user] = 0;
    }
  }

  /// @notice Claim a defaulted instant-withdraw receipt with the finalized recovery haircut.
  /// @param _user address of the user
  /// @return claimBasis amount of instant-withdraw basis cleared
  function _claimDefaultedInstantWithdrawRequest(address _user) internal returns (uint256 claimBasis) {
    uint256 defaultEpoch = defaultRecoveryEpoch;
    claimBasis = instantWithdrawsRequestsByEpoch[_user][defaultEpoch];
    if (claimBasis == 0) return claimBasis;

    instantWithdrawsRequestsByEpoch[_user][defaultEpoch] = 0;
    instantWithdrawsRequests[_user] -= claimBasis;
    uint256 pending = pendingInstantWithdraws;
    // `pendingInstantWithdraws` is only the unfunded remainder. If this user's claim is larger,
    // the extra amount was already counted as prefunded reserve during default finalization.
    pendingInstantWithdraws = claimBasis >= pending ? 0 : pending - claimBasis;
    instantWithdrawClaimsByEpoch[defaultEpoch] -= claimBasis;
    _burn(_user, claimBasis);
    _transferDefaultRecovery(_user, (claimBasis * defaultRecoveryPrice) / RECOVERY_FULL);
  }

  /// @notice Get defaulted normal/APR0 withdraw claim basis and receipt burn amount.
  /// @param _user address of the user
  /// @return claimBasis claim amount before recovery haircut
  /// @return burnAmount strategy-token receipt amount to burn
  function _withdrawClaimAmountsForEpoch(address _user, uint256 _claimEpoch) internal view returns (uint256 claimBasis, uint256 burnAmount) {
    // We calculate what the user is owed in underlyings (claimBasis) and how many strategy tokens to burn (burnAmount).
    // the amount owned is the sum of the normal withdraw request and the APR0 principal and interest if any.
    uint256 normalAmount = withdrawsRequestsByEpoch[_user][_claimEpoch];
    Apr0UserData storage _apr0User = apr0Users[_user];
    uint256 apr0PrincipalAmount;
    uint256 apr0InterestAmount;
    uint256 principal = _apr0User.principal;
    uint256 principalEpoch = _apr0User.principalEpoch;
    if (principal != 0 && principalEpoch == _claimEpoch) {
      apr0PrincipalAmount = principal;
      uint256 rate = apr0RateByEpoch[principalEpoch];
      if (rate != 0) {
        // APR0 interest increases the user's default claim basis, but not the receipt burn amount.
        apr0InterestAmount += (principal * rate) / RECOVERY_FULL;
      }
    }
    claimBasis = normalAmount + apr0PrincipalAmount + apr0InterestAmount;
    burnAmount = normalAmount + apr0PrincipalAmount;
  }

  /// @notice Check if a user has a normal or APR0 withdraw request.
  /// @param _user address of the user
  /// @return true if a normal or APR0 request exists
  function _hasWithdrawRequest(address _user) internal view returns (bool) {
    Apr0UserData storage data = apr0Users[_user];
    return withdrawsRequests[_user] != 0 ||
      data.principal != 0 ||
      data.settledPrincipal != 0 ||
      data.settledInterest != 0;
  }

  /// @notice Transfer a funded claim without spending default recovery reserve.
  /// @param _user claim receiver
  /// @param _amount amount to transfer
  function _transferFundedClaim(address _user, uint256 _amount) internal {
    if (_amount == 0) return;
    uint256 reserve = defaultRecoveryReserve;
    if (reserve != 0) {
      uint256 balance = underlyingToken.balanceOf(address(this));
      // This should be unreachable when accounting is consistent. Keep the guard so old funded
      // receipts can never spend underlyings reserved for default recovery claimants.
      if (balance < reserve || balance - reserve < _amount) revert NotAllowed();
    }
    underlyingToken.safeTransfer(_user, _amount);
  }

  /// @notice Transfer default recovery reserve to a user.
  /// @param _user claim receiver
  /// @param _amount amount to transfer
  function _transferDefaultRecovery(address _user, uint256 _amount) internal {
    if (_amount == 0) return;
    // Every defaulted or post-default claim consumes the isolated recovery reserve.
    defaultRecoveryReserve -= _amount;
    underlyingToken.safeTransfer(_user, _amount);
  }

  /// @notice Lazily initialize recovery accounting for an upgraded strategy.
  /// @dev Legacy pending receipts must first be fully funded because their per-epoch ownership
  /// cannot be reconstructed after an implementation upgrade. A successfully closed vault has
  /// already recalled all funds, so stale normal/APR0 aggregate counters can be normalized there.
  /// Pending instant withdrawals are never cleared automatically.
  function _ensureDefaultRecoveryInitialized() internal {
    if (defaultRecoveryInitialized) return;
    if (pendingInstantWithdraws != 0) revert NotAllowed();
    if (pendingWithdraws != 0) {
      IIdleCDOEpochVariant cdo = IIdleCDOEpochVariant(idleCDO);
      if (cdo.epochEndDate() != 0 || cdo.defaulted()) revert NotAllowed();
      pendingWithdraws = 0;
      apr0TotalPrincipal = 0;
    }
    defaultRecoveryInitialized = true;
    canTransfer = false;
  }

  /// @inheritdoc ERC20Upgradeable
  /// @dev Receipt claims are address-bound, so only the IdleCDO can move strategy tokens.
  function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
    if (msg.sender != idleCDO) revert NotAllowed();
    super._transfer(sender, recipient, amount);
  }

  /// @notice Clear the deprecated receipt-token transfer flag.
  /// @dev Kept for upgrade compatibility. Enabling transfers is permanently disabled because
  /// receipt claims are address-bound; the manager may only clear a legacy `true` value.
  /// @param _canTransfer must be false
  function setCanTransfer(bool _canTransfer) external {
    if (msg.sender != manager || _canTransfer) revert NotAllowed();
    canTransfer = false;
  }

  /// @notice allow to update whitelisted address
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    idleCDO = _cdo;
  }

  /// @notice Emergency method to rescue funds
  /// @param _token address of the token to transfer
  /// @param value amount of `_token` to transfer
  /// @param _to receiver address
  function transferToken(address _token, uint256 value, address _to) external onlyOwner {
    IERC20Detailed(_token).safeTransfer(_to, value);
  }

  /// @notice Modifier to make sure that caller os only the idleCDO contract
  function _onlyIdleCDO() internal view {
    if (msg.sender != idleCDO) {
      revert NotAllowed();
    }
  }

  /// @notice concat 2 strings in a single one
  /// @param a first string
  /// @param b second string
  /// @return new string with a and b concatenated
  function _concat(string memory a, string memory b) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b));
  }

  /// @notice Not used as redeems happens only via requestWithdraw and requestInstantWithdraw
  function redeem(uint256 _amount)
    external
    override
    returns (uint256) {}

  /// @notice Not used as redeems happens only via requestWithdraw and requestInstantWithdraw
  function redeemUnderlying(uint256)
    external
    returns (uint256) {}

  /// @notice not used in this strategy
  function pullStkAAVE()
    external
    pure
    override
    returns (uint256) {}

  /// @notice not used for this strategy
  function getRewardTokens()
    external
    view
    override
    returns (address[] memory) {}

  /// @notice not used for this strategy
  function redeemRewards(bytes calldata)
    external
    override
    returns (uint256[] memory rewards) {}
}
