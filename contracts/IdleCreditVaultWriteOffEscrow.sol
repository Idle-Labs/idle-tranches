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

/// @title IdleCreditVaultWriteOffEscrow
/// @dev Contract that collects write off requests of a credit vault deposit from a lender and underlyings from a borrower 
/// and allow them to trustlessly exchange debt between borrower and lender. Borrower will then be able to write off the debt
/// by burning tranches tokens (via IdleCDOEpochVariant writeOffDebt method)
contract IdleCreditVaultWriteOffEscrow is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Detailed;

  struct WriteOffRequest {
    /// @notice tranche tokens provided by the lender
    uint256 tranches;
    /// @notice underlyings requested by the lender
    uint256 underlyings;
  }

  /// @notice constant representing a 100% fee used for accounting
  uint256 public constant FULL_VALUE = 100_000; // 100_000 = 100%
  /// @notice maximum exit fee percentage
  uint256 public constant MAX_EXIT_FEE = 1_000; // 1_000 = 1%
  /// @notice address of the TL multisig that will receive exit fees
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

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
  /// @notice address of the borrower
  address public borrower;
  /// @notice mapping of user to their write-off requests
  mapping(address => WriteOffRequest) public userRequests;
  /// @notice exit fee percentage (value between 0 and 1000, where 1000 = 1%)
  uint256 public exitFee;
  /// @notice address of the fee receiver (where exit fee is sent)
  address public feeReceiver;

  /// @notice disable initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice initialize the contract
  /// @param _idleCDOEpoch address of the IdleCDOEpochVariant contract
  /// @param _owner address of the owner of the contract
  /// @param _isAATranche true if the tranche is the AA one
  function initialize(address _idleCDOEpoch, address _owner, bool _isAATranche) external initializer {
    if (idleCDOEpoch != address(0)) revert NotAllowed();
    // initialize the parent contracts
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    // set basic storage variables
    IdleCDOEpochVariant _cdo = IdleCDOEpochVariant(_idleCDOEpoch);
    idleCDOEpoch = _idleCDOEpoch;
    strategy = _cdo.strategy();
    underlying = _cdo.token();
    tranche = _isAATranche ? _cdo.AATranche() : _cdo.BBTranche();
    borrower = IdleCreditVault(strategy).borrower();
    exitFee = 100; // 0.1%
    feeReceiver = TL_MULTISIG; // set fee receiver to TL multisig
    // transfer ownership to the owner
    transferOwnership(_owner);
  }

  /// @notice create a write-off request by depositing tranche tokens and setting the amount of underlyings requested
  /// @param amount of tranche tokens to deposit
  function createWriteOffRequest(uint256 amount, uint256 underlyingsRequested) external nonReentrant {
    // can request write off only when epoch is running
    if (!IdleCDOEpochVariant(idleCDOEpoch).isEpochRunning()) revert EpochNotRunning();
    // cannot request write off with 0 tranche tokens
    if (amount == 0) revert NotAllowed();

    // check if the wallet is allowed to deposit (ie epoch is running and keyring KYC completed)
    _checkAllowed(msg.sender);
    // get tranche tokens from user
    IERC20Detailed(tranche).safeTransferFrom(msg.sender, address(this), amount);
    // get current write-off request
    WriteOffRequest memory currentRequest = userRequests[msg.sender];
    // update user requests
    userRequests[msg.sender] = WriteOffRequest({
      tranches: currentRequest.tranches + amount,
      underlyings: currentRequest.underlyings + underlyingsRequested
    });
  }

  /// @notice delete the write-off request and transfer tranche tokens back to the user
  function deleteWriteOffRequest() external nonReentrant {
    // check if the wallet is allowed to deposit (ie epoch is running and keyring KYC completed)
    _checkAllowed(msg.sender);
    // get current write-off request
    WriteOffRequest memory currentRequest = userRequests[msg.sender];
    // check if the user has a write-off request
    if (currentRequest.tranches == 0) revert Is0();

    // delete user request
    delete userRequests[msg.sender];
    // transfer tranche tokens back to the user
    IERC20Detailed(tranche).safeTransfer(msg.sender, currentRequest.tranches);
  }

  /// @notice fulfill the write-off request by the borrower
  /// @param _user address of the user that made the write-off request
  /// @dev this function can only be called by the borrower
  function fullfillWriteOffRequest(address _user) external nonReentrant {
    address _borrower = borrower;
    // Only borrower can call this function
    if (msg.sender != _borrower) revert NotAllowed();

    // get current write-off request
    WriteOffRequest memory currentRequest = userRequests[_user];
    // check if the user has a write-off request
    if (currentRequest.tranches == 0) revert Is0();

    // delete user request
    delete userRequests[_user];

    IERC20Detailed underlyingToken = IERC20Detailed(underlying);
    // transfer underlyings requested from the borrower to this contract
    underlyingToken.safeTransferFrom(_borrower, address(this), currentRequest.underlyings);
    // check if the exit fee is set and if so, apply it
    uint256 _exitFee = exitFee;
    uint256 _totFee;
    if (_exitFee > 0) {
      _totFee = (currentRequest.underlyings * _exitFee) / FULL_VALUE;
      // transfer exit fee to the feeReceiver
      underlyingToken.safeTransfer(feeReceiver, _totFee);
    }
    // transfer the remaining underlyings to the user
    underlyingToken.safeTransfer(_user, currentRequest.underlyings - _totFee);
    // transfer tranche tokens to borrower
    IERC20Detailed(tranche).safeTransfer(_borrower, currentRequest.tranches);

    // borrower can then choose to either keep the tranche tokens or write it off via 
    // IdleCDOEpochVariant.writeOffDebt method
  }

  function setExitFee(uint256 _exitFee) external {
    _checkOnlyOwner();
    // check if the exit fee is valid
    if (_exitFee > MAX_EXIT_FEE) revert NotAllowed();
    exitFee = _exitFee;
  }

  /// @notice emergency withdraw function to allow the owner to withdraw tokens from the contract
  /// @param _token address of the token to withdraw
  /// @param _to address to withdraw the tokens to
  /// @param _amount amount of tokens to withdraw
  function emergencyWithdraw(address _token, address _to, uint256 _amount) external {
    _checkOnlyOwner();
    // do not allow to withdraw to the zero address
    if (_to == address(0)) revert Is0();

    IERC20Detailed(_token).safeTransfer(_to, _amount);
  }

  /// @notice check if the wallet is allowed to deposit
  /// @param wallet address to check
  function _checkAllowed(address wallet) internal view {
    if (!IdleCDOEpochVariant(idleCDOEpoch).isWalletAllowed(wallet)) revert NotAllowed();
  }

  /// @notice check if msg.sender is the owner
  function _checkOnlyOwner() internal view {
    if (msg.sender != owner()) revert NotAllowed();
  }
}