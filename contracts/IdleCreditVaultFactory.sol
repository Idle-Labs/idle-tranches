// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCDOEpochVariantPrefunded} from "./IdleCDOEpochVariantPrefunded.sol";
import {IdleCDOEpochQueue} from "./IdleCDOEpochQueue.sol";
import {IdleCreditVaultWriteOffEscrow} from "./IdleCreditVaultWriteOffEscrow.sol";
import {KeyringIdleWhitelist} from "./KeyringIdleWhitelist.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";
import {ProgrammableBorrower} from "./strategies/idle/ProgrammableBorrower.sol";

contract IdleCreditVaultFactory is Initializable {
  address public treasury;

  event CreditVaultDeployed(address proxy);
  event StrategyDeployed(address proxy);
  event QueueDeployed(address proxy);
  event ProgrammableBorrowerDeployed(address proxy);
  event KeyringWhitelistDeployed(address keyringWhitelist);
  event WriteOffEscrowDeployed(address proxy);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _treasury) external initializer {
    require(_treasury != address(0), "IS_0");
    treasury = _treasury;
  }

  struct TransparentProxyData {
    address implementation;
    address proxyAdmin;
    bytes initializeData;
  }

  struct CreditVaultParams {
    uint256 apr;
    uint256 epochDuration;
    uint256 bufferPeriod;
    uint256 instantWithdrawDelay;
    uint256 instantWithdrawAprDelta;
    bool disableInstantWithdraw;
    address keyring;
    uint256 keyringPolicy;
    uint256 fees;
    uint256 managementFee;
    bool isInterestMinted;
    bool isDepositDuringEpochDisabled;
  }

  struct AncillaryParams {
    address keyringContract;
    address queueImplementation;
    bool whitelistQueue;
    uint256 prefundedDepositWindow;
  }

  struct ProgrammableBorrowerProxyData {
    address implementation;
    address proxyAdmin;
  }

  struct ProgrammableBorrowerParams {
    address vault;
    address borrower;
    uint256 borrowerApr;
  }

  function deployCreditVault(
    TransparentProxyData memory cvData,
    TransparentProxyData memory strategyData,
    CreditVaultParams memory cvParams,
    AncillaryParams memory ancillaryParams,
    address writeOffImplementation
  ) external {
    require(_getStrategyManager(strategyData.initializeData) != address(0), "IS_0");
    (IdleCDOEpochVariant cv, IdleCreditVault strategy, address guardian) =
      _deployBaseCreditVault(cvData, strategyData);

    (bool deployedKeyring, address keyring) =
      _prepareKeyring(cvParams.keyring, ancillaryParams);
    cvParams.keyring = keyring;
    _setCVParams(cv, strategy, cvParams);

    _deployAndConfigureQueue(ancillaryParams, strategyData.proxyAdmin, cv, keyring, treasury);
    _deployWriteOffEscrow(writeOffImplementation, strategyData.proxyAdmin, cv, treasury);

    _setFeeParams(cv, treasury, cvParams);
    cv.setGuardian(guardian);
    _finalizeKeyringAdmin(keyring, deployedKeyring);
    // Transfer ownership of strategy and credit vault to treasury
    strategy.transferOwnership(treasury);
    cv.transferOwnership(treasury);
  }

  function deployRevolvingCreditVault(
    TransparentProxyData memory cvData,
    TransparentProxyData memory strategyData,
    CreditVaultParams memory cvParams,
    ProgrammableBorrowerProxyData memory programmableBorrowerData,
    ProgrammableBorrowerParams memory programmableBorrowerParams,
    AncillaryParams memory ancillaryParams
  ) external {
    address manager = _getStrategyManager(strategyData.initializeData);
    require(manager != address(0), "IS_0");
    (IdleCDOEpochVariant cv, IdleCreditVault strategy, address guardian) =
      _deployBaseCreditVault(cvData, strategyData);

    cvParams.apr = 0;
    cvParams.isInterestMinted = true;
    cvParams.disableInstantWithdraw = true;
    (bool deployedKeyring, address keyring) =
      _prepareKeyring(cvParams.keyring, ancillaryParams);
    cvParams.keyring = keyring;
    _setCVParams(cv, strategy, cvParams);

    ProgrammableBorrower programmableBorrower = _deployProgrammableBorrower(
      programmableBorrowerData,
      programmableBorrowerParams,
      cv,
      strategy,
      manager
    );

    _deployAndConfigureQueue(ancillaryParams, strategyData.proxyAdmin, cv, keyring, treasury);

    _setFeeParams(cv, treasury, cvParams);
    cv.setGuardian(guardian);
    _finalizeKeyringAdmin(keyring, deployedKeyring);
    strategy.transferOwnership(treasury);
    cv.transferOwnership(treasury);
    programmableBorrower.transferOwnership(treasury);
  }

  function _prepareKeyring(
    address currentKeyring,
    AncillaryParams memory ancillaryParams
  ) internal returns (bool deployedKeyring, address keyring) {
    if (ancillaryParams.keyringContract == address(0)) {
      return (false, currentKeyring);
    }

    KeyringIdleWhitelist keyringWhitelist = new KeyringIdleWhitelist(ancillaryParams.keyringContract, address(this));
    keyring = address(keyringWhitelist);
    emit KeyringWhitelistDeployed(address(keyringWhitelist));
    return (true, keyring);
  }

  function _deployBaseCreditVault(
    TransparentProxyData memory cvData,
    TransparentProxyData memory strategyData
  ) internal returns (
    IdleCDOEpochVariant cv, 
    IdleCreditVault strategy, 
    address guardian
  ) {
    // Force ownership through this factory while keeping the encoded manager unchanged.
    strategyData.initializeData = _replaceStrategyInitializeData(strategyData.initializeData);
    // Deploy and initialize strategy
    strategy = IdleCreditVault(_deployProxy(strategyData));
    emit StrategyDeployed(address(strategy));

    // get guardian address from cvData because it will be overwritten in _replaceInitializeData
    // and we need to set it after deploying the credit vault
    guardian = _getGuardian(cvData.initializeData);
    // Replace strategy address with the deployed strategy address
    // and owner address with address(this) in the CV initialize data
    cvData.initializeData = _replaceInitializeData(cvData.initializeData, address(strategy));

    // Deploy and initialize credit vault
    cv = IdleCDOEpochVariant(_deployProxy(cvData));
    emit CreditVaultDeployed(address(cv));
  }

  function _deployProgrammableBorrower(
    ProgrammableBorrowerProxyData memory programmableBorrowerData,
    ProgrammableBorrowerParams memory programmableBorrowerParams,
    IdleCDOEpochVariant cv,
    IdleCreditVault strategy,
    address manager
  ) internal returns (ProgrammableBorrower programmableBorrower) {
    programmableBorrower = ProgrammableBorrower(_deployProxy(
      TransparentProxyData({
        implementation: programmableBorrowerData.implementation,
        proxyAdmin: programmableBorrowerData.proxyAdmin,
        initializeData: abi.encodeWithSelector(
          ProgrammableBorrower.initialize.selector,
          programmableBorrowerParams.vault,
          address(cv),
          address(this),
          manager,
          programmableBorrowerParams.borrower,
          programmableBorrowerParams.borrowerApr
        )
      })
    ));
    emit ProgrammableBorrowerDeployed(address(programmableBorrower));

    strategy.setBorrower(address(programmableBorrower));
    // Programmable mode is explicit and should always be enabled on the revolving path.
    cv.setIsProgrammableBorrower(true);
  }

  function _deployQueue(
    address queueImplementation,
    address proxyAdmin,
    IdleCDOEpochVariant cv
  ) internal returns (IdleCDOEpochQueue queue) {
    if (queueImplementation == address(0)) {
      return queue;
    }

    queue = IdleCDOEpochQueue(_deployProxy(
      TransparentProxyData({
        implementation: queueImplementation,
        proxyAdmin: proxyAdmin,
        initializeData: abi.encodeWithSelector(
          IdleCDOEpochQueue.initialize.selector,
          address(cv),
          address(this),
          true
        )
      })
    ));
    emit QueueDeployed(address(queue));
  }

  function _deployAndConfigureQueue(
    AncillaryParams memory ancillaryParams,
    address proxyAdmin,
    IdleCDOEpochVariant cv,
    address keyring,
    address owner
  ) internal {
    IdleCDOEpochQueue queue = _deployQueue(ancillaryParams.queueImplementation, proxyAdmin, cv);
    _configureQueue(queue, cv, keyring, ancillaryParams, owner);
  }

  function _configureQueue(
    IdleCDOEpochQueue queue,
    IdleCDOEpochVariant cv,
    address keyring,
    AncillaryParams memory ancillaryParams,
    address owner
  ) internal {
    if (address(queue) == address(0)) {
      return;
    }

    if (ancillaryParams.prefundedDepositWindow != 0) {
      IdleCDOEpochVariantPrefunded(address(cv)).setEpochQueue(address(queue));
      queue.setPrefundedDepositWindow(ancillaryParams.prefundedDepositWindow);
    }
    if (ancillaryParams.whitelistQueue && keyring != address(0)) {
      KeyringIdleWhitelist(keyring).setWhitelistStatus(address(queue), true);
    }
    queue.transferOwnership(owner);
  }

  function _deployWriteOffEscrow(
    address writeOffImplementation,
    address proxyAdmin,
    IdleCDOEpochVariant cv,
    address owner
  ) internal returns (IdleCreditVaultWriteOffEscrow writeOffEscrow) {
    if (writeOffImplementation == address(0)) {
      return writeOffEscrow;
    }

    writeOffEscrow = IdleCreditVaultWriteOffEscrow(_deployProxy(
      TransparentProxyData({
        implementation: writeOffImplementation,
        proxyAdmin: proxyAdmin,
        initializeData: abi.encodeWithSelector(
          IdleCreditVaultWriteOffEscrow.initialize.selector,
          address(cv),
          owner,
          true
        )
      })
    ));
    emit WriteOffEscrowDeployed(address(writeOffEscrow));
  }

  function _deployProxy(TransparentProxyData memory data) internal returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      data.implementation,
      data.proxyAdmin,
      data.initializeData
    );
    return address(proxy);
  }

  function _setCVParams(
    IdleCDOEpochVariant cv,
    IdleCreditVault strategy,
    CreditVaultParams memory par
  ) internal {
    cv.setEpochParams(par.epochDuration, par.bufferPeriod);
    cv.setInstantWithdrawParams(par.instantWithdrawDelay, par.instantWithdrawAprDelta, par.disableInstantWithdraw);
    cv.setKeyringParams(par.keyring, par.keyringPolicy, false);
    if (par.isInterestMinted) {
      cv.setIsInterestMinted(par.isInterestMinted);
    }
    cv.setIsDepositDuringEpochDisabled(par.isDepositDuringEpochDisabled);
    // setAprs should be done before setWhitelistedCDO
    strategy.setAprs(par.apr, par.apr * (par.epochDuration + par.bufferPeriod) / par.epochDuration);
    strategy.setWhitelistedCDO(address(cv));
  }

  function _setFeeParams(IdleCDOEpochVariant cv, address owner, CreditVaultParams memory cvParams) internal {
    cv.setFeeParams(owner, cvParams.fees);
    if (cvParams.managementFee != 0) {
      cv.setFeeParams(address(0), cvParams.managementFee);
    }
  }

  function _finalizeKeyringAdmin(address keyring, bool deployedKeyring) internal {
    if (deployedKeyring) {
      KeyringIdleWhitelist(keyring).changeAdmin(treasury);
    }
  }

  function _getGuardian(bytes memory cvData) internal pure returns (address guardian) {
    assembly {
      // The guardian address is the 4th argument in the initialize function.
      // It is located at offset 0x64 (4 bytes for selector + 3 * 32 bytes for previous arguments).
      // The memory address is `cvData` + 0x20 (content start) + 0x64 = `cvData` + 0x84.
      guardian := mload(add(cvData, 0x84))
    }
  }

  function _replaceInitializeData(bytes memory data, address strategyAddress) internal view returns (bytes memory) {
    // The data is ABI encoded calldata for `initialize(uint256, address, address, address, address, address, uint256)`
    // We want to replace two arguments:
    // 1. The 4th argument (owner) with `address(this)`.
    // 2. The 6th argument (strategy) with `strategyAddress`.
    //
    // Memory layout of `data`:
    // - 0x00: data length (32 bytes)
    // - 0x20: data content starts here
    //
    // Content layout:
    // - 0x20: function selector (4 bytes)
    // - 0x24: 1st argument (_limit)
    // - 0x44: 2nd argument (_guardedToken)
    // - 0x64: 3rd argument (_governanceFund)
    // - 0x84: 4th argument (owner) <--- TARGET 1
    // - 0xa4: 5th argument (rebalancer)
    // - 0xc4: 6th argument (strategy) <--- TARGET 2
    assembly {
      // Replace the owner (4th argument) with this contract's address.
      // The 4th argument is after the selector (4 bytes) and 3 preceding arguments (3 * 32 bytes).
      // Offset = 4 + 96 = 100 bytes from the start of the content.
      // The memory address is `data` + 0x20 (content start) + 100 = `data` + 0x84.
      // The `address` opcode returns the address of the current contract.
      mstore(add(data, 0x84), address())

      // Replace the strategy address (6th argument).
      // The 6th argument is after the selector (4 bytes) and 5 preceding arguments (5 * 32 bytes).
      // Offset = 4 + 160 = 164 bytes from the start of the content.
      // The memory address is `data` + 0x20 + 164 = `data` + 0xc4.
      mstore(add(data, 0xc4), strategyAddress)
    }

    return data;
  }

  function _getStrategyManager(bytes memory data) internal pure returns (address manager) {
    assembly {
      // Read manager (3rd argument): content start + selector (4 bytes) + 2 * 32 bytes.
      manager := mload(add(data, 0x64))
    }
  }

  function _replaceStrategyInitializeData(bytes memory data) internal view returns (bytes memory) {
    // The data is ABI encoded calldata for
    // `initialize(address,address,address,address,string,uint256)`.
    // We force the 2nd argument (owner) to `address(this)`.
    assembly {
      // Replace owner (2nd argument): content start + selector (4 bytes) + 1 * 32 bytes.
      mstore(add(data, 0x44), address())
    }

    return data;
  }
}
