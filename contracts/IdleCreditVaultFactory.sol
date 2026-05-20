// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IdleCDOCreditVault} from "./IdleCDOCreditVault.sol";
import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCDOEpochVariantPrefunded} from "./IdleCDOEpochVariantPrefunded.sol";
import {IdleCDOEpochQueue} from "./IdleCDOEpochQueue.sol";
import {IdleCreditVaultWriteOffEscrow} from "./IdleCreditVaultWriteOffEscrow.sol";
import {KeyringIdleWhitelist} from "./KeyringIdleWhitelist.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";
import {ProgrammableBorrower} from "./strategies/idle/ProgrammableBorrower.sol";

contract IdleCreditVaultFactory is Initializable {
  uint256 public constant FULL_ALLOC = 100_000;
  uint256 public constant DEFAULT_FEE_SPLIT = 50_000;
  uint256 public constant MIN_PERFORMANCE_FEE = 10_000;
  uint256 public constant MIN_MANAGEMENT_FEE = 500;

  address public treasury;
  uint256 public feeSplit;
  address public proxyAdmin;

  event CreditVaultDeployed(
    address creditVault,
    address strategy,
    address queue,
    address programmableBorrower,
    address keyringWhitelist,
    address writeOffEscrow
  );

  error AmountTooHigh();
  error FeesTooLow();
  error Is0();
  error OnlyTreasury();
  error WriteOffUnsupported();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _treasury, address _proxyAdmin) external initializer {
    if (_treasury == address(0) || _proxyAdmin == address(0)) revert Is0();
    treasury = _treasury;
    proxyAdmin = _proxyAdmin;
    _setFeeSplit(DEFAULT_FEE_SPLIT);
  }

  struct StrategyData {
    address implementation;
    address manager;
    address borrower;
    string borrowerName;
  }

  struct CreditVaultParams {
    address implementation;
    uint256 limit;
    address underlying;
    uint256 apr;
    uint256 epochDuration;
    uint256 bufferPeriod;
    uint256 instantWithdrawDelay;
    uint256 instantWithdrawAprDelta;
    bool disableInstantWithdraw;
    uint256 keyringPolicy;
    address feeReceiver;
    uint256 fees;
    uint256 managementFee;
    bool isInterestMinted;
    bool isDepositDuringEpochDisabled;
  }

  struct AncillaryParams {
    // Underlying Keyring credential contract. address(0) disables Keyring for the deployed vault.
    address keyring;
    address queueImplementation;
    uint256 prefundedDepositWindow;
    address writeOffImplementation;
  }

  struct ProgrammableBorrowerParams {
    address implementation;
    address vault;
    address borrower;
    uint256 borrowerApr;
  }

  function deployCreditVault(
    CreditVaultParams memory cvParams,
    StrategyData memory strategyData,
    AncillaryParams memory ancillaryParams
  ) external {
    _checkMinimumFees(cvParams);
    address manager = strategyData.manager;
    if (manager == address(0)) revert Is0();

    (IdleCDOEpochVariant cv, IdleCreditVault strategy) =
      _deployBaseCreditVault(strategyData, cvParams);

    address keyringWhitelist = _deployKeyring(ancillaryParams);
    _configureCreditVault(cv, strategy, cvParams, keyringWhitelist, manager);

    IdleCDOEpochQueue queue = _deployQueue(ancillaryParams, cv, keyringWhitelist);
    IdleCreditVaultWriteOffEscrow writeOffEscrow =
      _deployWriteOffEscrow(ancillaryParams.writeOffImplementation, cv, treasury);

    _finalizeKeyringAdmin(keyringWhitelist, manager);
    // Transfer ownership of strategy and credit vault to treasury
    strategy.transferOwnership(treasury);
    cv.transferOwnership(treasury);

    emit CreditVaultDeployed(
      address(cv),
      address(strategy),
      address(queue),
      address(0),
      keyringWhitelist,
      address(writeOffEscrow)
    );
  }

  function deployRevolvingCreditVault(
    CreditVaultParams memory cvParams,
    StrategyData memory strategyData,
    ProgrammableBorrowerParams memory programmableBorrowerParams,
    AncillaryParams memory ancillaryParams
  ) external {
    if (ancillaryParams.writeOffImplementation != address(0)) revert WriteOffUnsupported();
    _checkMinimumFees(cvParams);
    address manager = strategyData.manager;
    if (manager == address(0)) revert Is0();

    cvParams.apr = 0;
    cvParams.isInterestMinted = true;
    cvParams.disableInstantWithdraw = true;
    cvParams.isDepositDuringEpochDisabled = true;
    (IdleCDOEpochVariant cv, IdleCreditVault strategy) = _deployBaseCreditVault(strategyData, cvParams);
    address keyringWhitelist = _deployKeyring(ancillaryParams);
    _configureCreditVault(cv, strategy, cvParams, keyringWhitelist, manager);

    ProgrammableBorrower programmableBorrower = _deployProgrammableBorrower(
      programmableBorrowerParams,
      cv,
      strategy,
      manager
    );

    IdleCDOEpochQueue queue = _deployQueue(ancillaryParams, cv, keyringWhitelist);

    _finalizeKeyringAdmin(keyringWhitelist, manager);
    strategy.transferOwnership(treasury);
    cv.transferOwnership(treasury);

    emit CreditVaultDeployed(
      address(cv),
      address(strategy),
      address(queue),
      address(programmableBorrower),
      keyringWhitelist,
      address(0)
    );
  }

  function _deployKeyring(AncillaryParams memory ancillaryParams) internal returns (address) {
    if (ancillaryParams.keyring == address(0)) return address(0);

    KeyringIdleWhitelist keyringWhitelist = new KeyringIdleWhitelist(ancillaryParams.keyring, address(this));
    return address(keyringWhitelist);
  }

  function _deployBaseCreditVault(
    StrategyData memory strategyData,
    CreditVaultParams memory cvParams
  ) internal returns (
    IdleCDOEpochVariant cv,
    IdleCreditVault strategy
  ) {
    strategy = IdleCreditVault(_deployProxy(
      strategyData.implementation,
      abi.encodeWithSelector(
        IdleCreditVault.initialize.selector,
        cvParams.underlying,
        address(this),
        strategyData.manager,
        strategyData.borrower,
        strategyData.borrowerName,
        cvParams.apr
      )
    ));

    cv = IdleCDOEpochVariant(_deployProxy(
      cvParams.implementation,
      abi.encodeWithSelector(
        IdleCDOCreditVault.initialize.selector,
        cvParams.limit,
        cvParams.underlying,
        treasury,
        address(this),
        address(0),
        address(strategy),
        FULL_ALLOC
      )
    ));
  }

  function _deployProgrammableBorrower(
    ProgrammableBorrowerParams memory programmableBorrowerParams,
    IdleCDOEpochVariant cv,
    IdleCreditVault strategy,
    address manager
  ) internal returns (ProgrammableBorrower programmableBorrower) {
    programmableBorrower = ProgrammableBorrower(_deployProxy(
      programmableBorrowerParams.implementation,
      abi.encodeWithSelector(
        ProgrammableBorrower.initialize.selector,
        programmableBorrowerParams.vault,
        address(cv),
        address(this),
        manager,
        programmableBorrowerParams.borrower,
        programmableBorrowerParams.borrowerApr
      )
    ));

    strategy.setBorrower(address(programmableBorrower));
    // Programmable mode is explicit and should always be enabled on the revolving path.
    cv.setIsProgrammableBorrower(true);
    programmableBorrower.transferOwnership(treasury);
  }

  function _deployQueue(
    AncillaryParams memory ancillaryParams,
    IdleCDOEpochVariant cv,
    address keyringWhitelist
  ) internal returns (IdleCDOEpochQueue queue) {
    if (ancillaryParams.queueImplementation == address(0)) return queue;

    queue = IdleCDOEpochQueue(_deployProxy(
      ancillaryParams.queueImplementation,
      abi.encodeWithSelector(
        IdleCDOEpochQueue.initialize.selector,
        address(cv),
        address(this),
        true
      )
    ));

    if (ancillaryParams.prefundedDepositWindow != 0) {
      IdleCDOEpochVariantPrefunded(address(cv)).setEpochQueue(address(queue));
      queue.setPrefundedDepositWindow(ancillaryParams.prefundedDepositWindow);
    }
    if (keyringWhitelist != address(0)) {
      KeyringIdleWhitelist(keyringWhitelist).setWhitelistStatus(address(queue), true);
    }
    queue.transferOwnership(treasury);
  }

  function _deployWriteOffEscrow(
    address writeOffImplementation,
    IdleCDOEpochVariant cv,
    address owner
  ) internal returns (IdleCreditVaultWriteOffEscrow writeOffEscrow) {
    if (writeOffImplementation == address(0)) return writeOffEscrow;

    writeOffEscrow = IdleCreditVaultWriteOffEscrow(_deployProxy(
      writeOffImplementation,
      abi.encodeWithSelector(
        IdleCreditVaultWriteOffEscrow.initialize.selector,
        address(cv),
        owner,
        true
      )
    ));
  }

  function _deployProxy(address implementation, bytes memory data) internal returns (address) {
    return address(new TransparentUpgradeableProxy(
      implementation,
      proxyAdmin,
      data
    ));
  }

  function _configureCreditVault(
    IdleCDOEpochVariant cv,
    IdleCreditVault strategy,
    CreditVaultParams memory par,
    address keyringWhitelist,
    address manager
  ) internal {
    cv.setEpochParams(par.epochDuration, par.bufferPeriod);
    cv.setInstantWithdrawParams(par.instantWithdrawDelay, par.instantWithdrawAprDelta, par.disableInstantWithdraw);
    cv.setKeyringParams(keyringWhitelist, par.keyringPolicy);
    if (par.isInterestMinted) {
      cv.setIsInterestMinted(par.isInterestMinted);
    }
    cv.setIsDepositDuringEpochDisabled(par.isDepositDuringEpochDisabled);
    cv.setFeeParams(par.feeReceiver, par.fees, feeSplit, par.managementFee);
    cv.setGuardian(manager);
    // setAprs should be done before setWhitelistedCDO
    strategy.setAprs(par.apr, par.apr * (par.epochDuration + par.bufferPeriod) / par.epochDuration);
    strategy.setWhitelistedCDO(address(cv));
  }

  function _checkMinimumFees(CreditVaultParams memory cvParams) internal pure {
    if (cvParams.fees < MIN_PERFORMANCE_FEE && cvParams.managementFee < MIN_MANAGEMENT_FEE) revert FeesTooLow();
  }

  function setFeeSplit(uint256 _feeSplit) external {
    if (msg.sender != treasury) revert OnlyTreasury();
    _setFeeSplit(_feeSplit);
  }

  function _setFeeSplit(uint256 _feeSplit) internal {
    if (_feeSplit > FULL_ALLOC) revert AmountTooHigh();
    feeSplit = _feeSplit;
  }

  function _finalizeKeyringAdmin(address keyringWhitelist, address admin) internal {
    if (keyringWhitelist != address(0)) {
      KeyringIdleWhitelist(keyringWhitelist).changeAdmin(admin);
    }
  }
}
