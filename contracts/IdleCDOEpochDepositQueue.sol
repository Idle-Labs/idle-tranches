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

/// @title IdleCDOEpochDepositQueue
/// @dev Contract that collects deposits during an epoch to be processed in the next
/// buffer period (ie between two epochs)
contract IdleCDOEpochDepositQueue is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
  /// @notice amount of pending deposits
  uint256 public pendingDeposits;
  /// @notice mapping of deposits per user per epoch
  mapping(address => mapping (uint256 => uint256)) public userDepositsEpochs;
  /// @notice mapping of tranche price per epoch
  mapping(uint256 => uint256) public epochPrice;

  /// @notice initialize the implementation contract to avoid malicious initialization
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
    pendingDeposits += amount;
  }

  /// @notice delete a deposit request
  /// @param _requestEpoch epoch of the deposit request
  function deleteRequest(uint256 _requestEpoch) external {
    // if the epoch price is already set, deposits were already processed so
    // the deposit request can't be deleted
    if (epochPrice[_requestEpoch] != 0) {
      revert NotAllowed();
    }

    uint256 amount = userDepositsEpochs[msg.sender][_requestEpoch];
    if (amount == 0) {
      return;
    }
    // reset user deposit for the epoch
    userDepositsEpochs[msg.sender][_requestEpoch] = 0;
    // update pending deposits
    pendingDeposits -= amount;
    // transfer underlyings back to the user
    IERC20Detailed(underlying).safeTransfer(msg.sender, amount);
  }

  /// @notice process deposits during buffer period. Anyone can call this
  /// @dev will revert in IdleCDOEpochVariant if called when epoch running
  function processDeposits() external {
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(idleCDOEpoch);
    uint256 _pending = pendingDeposits;

    if (_pending == 0) {
      return;
    }
    // deposit underlyings in the CDO contract
    uint256 _trancheMinted;
    if (tranche == _cdo.AATranche()) {
      _trancheMinted = _cdo.depositAA(_pending);
    } else {
      _trancheMinted = _cdo.depositBB(_pending);
    }
    // save current implied tranche price for this epoch based on underlyings deposited and tranche tokens minted
    epochPrice[IdleCreditVault(strategy).epochNumber()] = _pending * ONE_TRANCHE / _trancheMinted;
    pendingDeposits = 0;
  }

  /// @notice claim deposit request
  /// @param _epoch epoch of the deposit request
  function claimDepositRequest(uint256 _epoch) external {
    uint256 amount = userDepositsEpochs[msg.sender][_epoch];
    if (amount == 0) {
      return;
    }
    // reset user deposit for the epoch
    userDepositsEpochs[msg.sender][_epoch] = 0;
    // transfer tranche tokens to user based on the price of that epoch
    IERC20Detailed(tranche).safeTransfer(msg.sender, amount * ONE_TRANCHE / epochPrice[_epoch]);
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