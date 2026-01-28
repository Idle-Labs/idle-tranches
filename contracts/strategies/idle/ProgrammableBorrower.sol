// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import {IERC4626} from "../../interfaces/IERC4626.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

error NotAllowed();
error InvalidAddress();
error InvalidAmount();
error AlreadyInitialized();
error InsufficientBorrowable();

/// @title ProgrammableBorrower
/// @dev Simple borrower contract that can park funds into an ERC4626 vault (eg. Morpho Supply vault)
/// and pull them back when the credit vault needs liquidity.
contract ProgrammableBorrower is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Detailed;

  uint256 internal constant ONE_TRANCHE_TOKEN = 1e18;
  uint256 internal constant YEAR = 365 days;

  /// @notice underlying token (must match the vault asset)
  IERC20Detailed public underlyingToken;
  /// @notice ERC4626 vault where funds are deployed (eg Morpho supply vault)
  IERC4626 public morphoVault;
  /// @notice IdleCDOEpochVariant address allowed to pull funds
  address public idleCDO;
  /// @notice real borrower address allowed to draw/repay
  address public borrower;

  /// @notice fixed APR charged to borrower debt (100e18 = 100% APR)
  uint256 public borrowerApr;
  /// @notice outstanding borrower principal
  uint256 public borrowerPrincipal;
  /// @notice borrower interest accrued since last epoch start / reset
  uint256 public borrowerInterestAccrued;
  /// @notice last timestamp borrower interest was accrued
  uint256 public lastBorrowerAccrual;

  /// @notice Morpho assets held at epoch start (baseline)
  uint256 public epochStartMorphoAssets;
  /// @notice cumulative assets deposited to Morpho during epoch
  uint256 public epochDepositedToMorpho;
  /// @notice cumulative assets withdrawn from Morpho during epoch
  uint256 public epochWithdrawnFromMorpho;
  /// @notice whether epoch accounting is active
  bool public epochAccountingActive;
  /// @notice pending withdraw requests amount reserved for the epoch
  uint256 public epochPendingWithdraws;

  event DepositedIntoMorpho(uint256 assets, uint256 shares);
  event WithdrawnFromMorpho(uint256 assets, uint256 shares, address indexed receiver);
  event RedeemedFromMorpho(uint256 shares, uint256 assets, address indexed receiver);
  event MorphoVaultSet(address indexed newMorphoVault);
  event BorrowerSet(address indexed newBorrower);
  event BorrowerAprSet(uint256 newApr);
  event Borrowed(uint256 assets);
  event Repaid(uint256 assets, uint256 interestPaid, uint256 principalPaid);
  event EpochAccountingStarted(uint256 startAssets);
  event EpochAccountingStopped();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    underlyingToken = IERC20Detailed(address(1));
  }

  /// @notice initialize the contract
  /// @param _underlyingToken address of the underlying token
  /// @param _morphoVault ERC4626 vault where funds will be deployed
  /// @param _idleCDO IdleCDOEpochVariant contract allowed to pull funds (can be address(0) and set later)
  /// @param _owner owner address
  function initialize(
    address _underlyingToken,
    address _morphoVault,
    address _idleCDO,
    address _owner
  ) external initializer {
    if (address(underlyingToken) != address(0)) revert AlreadyInitialized();
    if (
      _underlyingToken == address(0) ||
      _morphoVault == address(0) ||
      _owner == address(0) ||
      _idleCDO == address(0) ||
      IERC4626(_morphoVault).asset() != _underlyingToken
    ) {
      revert InvalidAddress();
    }

    __Ownable_init();
    __ReentrancyGuard_init();
    transferOwnership(_owner);

    IERC4626 _vault = IERC4626(_morphoVault);
    underlyingToken = IERC20Detailed(_underlyingToken);
    morphoVault = _vault;
    idleCDO = _idleCDO;

    // Set approvals for morpho vault and IdleCDO
    _allowUnlimitedSpend(_underlyingToken, _morphoVault);
    _allowUnlimitedSpend(_underlyingToken, _idleCDO);
  }

  /// @notice set the vault used to deploy funds
  /// @notice ensure that funds have been withdrawn from the previous vault before changing
  /// @param _morphoVault new ERC4626 vault address
  function setMorphoVault(address _morphoVault) external onlyOwner {
    if (_morphoVault == address(0) || IERC4626(_morphoVault).asset() != address(underlyingToken)) {
      revert InvalidAddress();
    }
    underlyingToken.safeApprove(address(morphoVault), 0);
    morphoVault = IERC4626(_morphoVault);
    _allowUnlimitedSpend(address(underlyingToken), _morphoVault);
    emit MorphoVaultSet(_morphoVault);
  }

  /// @notice set the real borrower address
  function setBorrower(address _borrower) external onlyOwner {
    if (_borrower == address(0)) {
      revert InvalidAddress();
    }
    borrower = _borrower;
    emit BorrowerSet(_borrower);
  }

  /// @notice set the fixed APR for borrower debt (100e18 = 100% APR)
  function setBorrowerApr(uint256 _apr) external onlyOwner {
    borrowerApr = _apr;
    emit BorrowerAprSet(_apr);
  }

  /// @notice Hook called by IdleCDOEpochVariant when a new epoch starts.
  /// It deposits all on-hand assets into Morpho and starts accounting.
  /// @param _pendingWithdraws pending withdraw requests amount to reserve for epoch end.
  function onStartEpoch(uint256 _pendingWithdraws) external nonReentrant {
    _checkOnlyIdleCDO();
    epochPendingWithdraws = _pendingWithdraws;
    _depositAllToMorphoInternal(false);
    _startEpochAccountingInternal();
  }

  /// @notice Hook called by IdleCDOEpochVariant before stopping an epoch.
  /// Withdraws enough liquidity from Morpho so IdleCDO can pull funds.
  /// @param _amountRequired total amount IdleCDO will pull via transferFrom.
  function onStopEpoch(uint256 _amountRequired) external nonReentrant {
    _checkOnlyIdleCDO();
    _accrueBorrowerInterest();

    uint256 onHand = underlyingToken.balanceOf(address(this));
    if (_amountRequired > onHand) {
      uint256 shortfall = _amountRequired - onHand;
      uint256 shares = morphoVault.withdraw(shortfall, address(this), address(this));
      if (epochAccountingActive) {
        epochWithdrawnFromMorpho += shortfall;
      }
      emit WithdrawnFromMorpho(shortfall, shares, address(this));
    }

    epochPendingWithdraws = 0;
    _stopEpochAccountingInternal();
  }

  /// @notice start epoch accounting for Morpho yield and borrower interest.
  /// Call after deploying epoch funds into Morpho.
  function startEpochAccounting() external {
    _checkOnlyOwnerOrIdleCDO();
    _startEpochAccountingInternal();
  }

  /// @notice stop epoch accounting
  function stopEpochAccounting() external {
    _checkOnlyOwnerOrIdleCDO();
    _stopEpochAccountingInternal();
  }

  function _startEpochAccountingInternal() internal {
    epochStartMorphoAssets = _currentMorphoAssets();
    epochDepositedToMorpho = 0;
    epochWithdrawnFromMorpho = 0;
    epochAccountingActive = true;
    borrowerInterestAccrued = 0;
    lastBorrowerAccrual = block.timestamp;
    emit EpochAccountingStarted(epochStartMorphoAssets);
  }

  function _stopEpochAccountingInternal() internal {
    epochAccountingActive = false;
    emit EpochAccountingStopped();
  }

  /// @notice interest accrued in Morpho since the last `startEpochAccounting`
  function morphoInterestAccrued() public view returns (uint256) {
    if (!epochAccountingActive) return 0;
    uint256 earnedAssets = _currentMorphoAssets() + epochWithdrawnFromMorpho;
    uint256 principalAssets = epochStartMorphoAssets + epochDepositedToMorpho;
    return earnedAssets > principalAssets ? earnedAssets - principalAssets : 0;
  }

  /// @notice borrower interest accrued since epoch start up to now (includes uncheckpointed interest)
  function borrowerInterestAccruedNow() public view returns (uint256) {
    uint256 principal = borrowerPrincipal;
    uint256 accrued = borrowerInterestAccrued;
    uint256 last = lastBorrowerAccrual;
    if (principal == 0 || last == 0 || borrowerApr == 0) return accrued;
    uint256 elapsed = block.timestamp - last;
    uint256 additional = elapsed == 0
      ? 0
      : principal * (borrowerApr / 100) * elapsed / (YEAR * ONE_TRANCHE_TOKEN);
    return accrued + additional;
  }

  /// @notice total interest due at epoch stop (Morpho yield + borrower interest)
  function totalInterestDueNow() external view returns (uint256) {
    return morphoInterestAccrued() + borrowerInterestAccruedNow();
  }

  /// @notice total amount reserved and not borrowable by the real borrower
  function reservedUnderlyingNow() public view returns (uint256) {
    return epochPendingWithdraws + morphoInterestAccrued() + borrowerInterestAccruedNow();
  }

  /// @notice current borrowable liquidity excluding reserved interest and withdraw requests
  function availableToBorrow() public view returns (uint256) {
    uint256 totalAssets = underlyingToken.balanceOf(address(this)) + _currentMorphoAssets();
    uint256 reservedAssets = reservedUnderlyingNow();
    return totalAssets <= reservedAssets ? 0 : totalAssets - reservedAssets;
  }

  /// @notice deposit a specific amount of underlyings into the vault
  /// @param assets amount of underlying to deposit
  /// @return shares amount of vault shares received
  function depositToMorpho(uint256 assets) external nonReentrant onlyOwner returns (uint256 shares) {
    if (assets == 0) {
      revert InvalidAmount();
    }
    shares = morphoVault.deposit(assets, address(this));
    if (epochAccountingActive) {
      epochDepositedToMorpho += assets;
    }
    emit DepositedIntoMorpho(assets, shares);
  }

  /// @notice deposit the full underlying balance held by this contract into Morpho
  function depositAllToMorpho() external nonReentrant onlyOwner returns (uint256 shares) {
    (shares, ) = _depositAllToMorphoInternal(true);
  }

  function _depositAllToMorphoInternal(bool revertOnZero) internal returns (uint256 shares, uint256 assets) {
    assets = underlyingToken.balanceOf(address(this));
    if (assets == 0) {
      if (revertOnZero) {
        revert InvalidAmount();
      }
      return (0, 0);
    }
    shares = morphoVault.deposit(assets, address(this));
    if (epochAccountingActive) {
      epochDepositedToMorpho += assets;
    }
    emit DepositedIntoMorpho(assets, shares);
  }

  /// @notice withdraw underlying from the vault
  /// @param assets amount of underlying to withdraw
  /// @param receiver address receiving the underlyings
  /// @return shares burned to fulfill the withdrawal
  function withdrawFromMorpho(uint256 assets, address receiver)
    external
    nonReentrant
    returns (uint256 shares)
  {
    _checkOnlyOwnerOrIdleCDO();
    if (assets == 0 || receiver == address(0)) {
      revert InvalidAmount();
    }
    if (msg.sender == idleCDO && receiver != idleCDO) {
      revert NotAllowed();
    }
    shares = morphoVault.withdraw(assets, receiver, address(this));
    if (epochAccountingActive) {
      epochWithdrawnFromMorpho += assets;
    }
    emit WithdrawnFromMorpho(assets, shares, receiver);
  }

  /// @notice redeem a specific amount of vault shares
  function redeemFromMorpho(uint256 shares, address receiver)
    external
    nonReentrant
    returns (uint256 assets)
  {
    _checkOnlyOwnerOrIdleCDO();
    if (shares == 0 || receiver == address(0)) {
      revert InvalidAmount();
    }
    if (msg.sender == idleCDO && receiver != idleCDO) {
      revert NotAllowed();
    }
    assets = morphoVault.redeem(shares, receiver, address(this));
    if (epochAccountingActive) {
      epochWithdrawnFromMorpho += assets;
    }
    emit RedeemedFromMorpho(shares, assets, receiver);
  }

  /// @notice withdraw the entire position from Morpho
  function withdrawAllFromMorpho(address receiver)
    external
    nonReentrant
    returns (uint256 assets)
  {
    _checkOnlyOwnerOrIdleCDO();
    if (receiver == address(0)) {
      revert InvalidAddress();
    }
    if (msg.sender == idleCDO && receiver != idleCDO) {
      revert NotAllowed();
    }
    uint256 shares = morphoVault.balanceOf(address(this));
    if (shares == 0) {
      revert InvalidAmount();
    }
    assets = morphoVault.redeem(shares, receiver, address(this));
    if (epochAccountingActive) {
      epochWithdrawnFromMorpho += assets;
    }
    emit RedeemedFromMorpho(shares, assets, receiver);
  }

  /// @notice borrower draws funds from the facility.
  /// If not enough on-hand liquidity, withdraw the shortfall from Morpho.
  function borrow(uint256 assets) external nonReentrant returns (uint256 withdrawnShares) {
    if (msg.sender != borrower || !epochAccountingActive) revert NotAllowed();
    if (assets == 0) {
      revert InvalidAmount();
    }
    if (assets > availableToBorrow()) {
      revert InsufficientBorrowable();
    }

    _accrueBorrowerInterest();

    uint256 onHand = underlyingToken.balanceOf(address(this));
    if (onHand < assets) {
      uint256 shortfall = assets - onHand;
      withdrawnShares = morphoVault.withdraw(shortfall, address(this), address(this));
      if (epochAccountingActive) {
        epochWithdrawnFromMorpho += shortfall;
      }
      emit WithdrawnFromMorpho(shortfall, withdrawnShares, address(this));
    }

    borrowerPrincipal += assets;
    underlyingToken.safeTransfer(borrower, assets);
    emit Borrowed(assets);
  }

  /// @notice borrower repays funds to the facility.
  /// Repayments are applied to accrued interest first, then principal.
  function repay(uint256 assets) external nonReentrant returns (uint256 interestPaid, uint256 principalPaid) {
    if (msg.sender != borrower) revert NotAllowed();
    if (assets == 0) {
      revert InvalidAmount();
    }

    _accrueBorrowerInterest();

    underlyingToken.safeTransferFrom(borrower, address(this), assets);

    uint256 interestDue = borrowerInterestAccrued;
    if (assets >= interestDue) {
      interestPaid = interestDue;
      borrowerInterestAccrued = 0;
      assets -= interestDue;

      uint256 principalDue = borrowerPrincipal;
      principalPaid = assets > principalDue ? principalDue : assets;
      borrowerPrincipal = principalDue - principalPaid;
    } else {
      interestPaid = assets;
      borrowerInterestAccrued = interestDue - assets;
    }

    emit Repaid(interestPaid + principalPaid, interestPaid, principalPaid);
  }

  /// @notice view the total exposure in underlying terms (on-hand + deployed)
  function totalUnderlying() external view returns (uint256) {
    return underlyingToken.balanceOf(address(this)) + _currentMorphoAssets();
  }

  /// @notice view the current vault share balance
  function morphoSharesBalance() external view returns (uint256) {
    return morphoVault.balanceOf(address(this));
  }

  function _currentMorphoAssets() internal view returns (uint256) {
    uint256 shares = morphoVault.balanceOf(address(this));
    return shares == 0 ? 0 : morphoVault.convertToAssets(shares);
  }

  function _accrueBorrowerInterest() internal {
    uint256 last = lastBorrowerAccrual;
    uint256 principal = borrowerPrincipal;
    if (last == 0) {
      lastBorrowerAccrual = block.timestamp;
      return;
    }
    if (principal == 0 || borrowerApr == 0) {
      lastBorrowerAccrual = block.timestamp;
      return;
    }
    uint256 elapsed = block.timestamp - last;
    if (elapsed == 0) {
      return;
    }
    uint256 interest = principal * (borrowerApr / 100) * elapsed / (YEAR * ONE_TRANCHE_TOKEN);
    borrowerInterestAccrued += interest;
    lastBorrowerAccrual = block.timestamp;
  }

  function _checkOnlyIdleCDO() internal view {
    if (msg.sender != idleCDO) revert NotAllowed();
  }

  function _checkOnlyOwnerOrIdleCDO() internal view {
    if (msg.sender != owner() && msg.sender != idleCDO) revert NotAllowed();
  }

  /// @notice emergency token rescue
  /// @param _token token address to transfer
  /// @param _to recipient
  /// @param _amount amount to transfer
  function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
    if (_to == address(0)) {
      revert InvalidAddress();
    }
    IERC20Detailed(_token).safeTransfer(_to, _amount);
  }

  /// @dev Set allowance for _token to unlimited for _spender
  /// @param _token token address
  /// @param _spender spender address
  function _allowUnlimitedSpend(address _token, address _spender) internal {
    IERC20Detailed(_token).safeIncreaseAllowance(_spender, type(uint256).max);
  }
}
