// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IdleCDOCreditVault} from "./IdleCDOCreditVault.sol";
import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCDOEpochVariantPrefunded} from "./IdleCDOEpochVariantPrefunded.sol";
import {IdleCDOEpochQueue} from "./IdleCDOEpochQueue.sol";
import {IdleCreditVaultWriteOffEscrow} from "./IdleCreditVaultWriteOffEscrow.sol";
import {KeyringIdleWhitelist} from "./KeyringIdleWhitelist.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";
import {ProgrammableBorrower} from "./strategies/idle/ProgrammableBorrower.sol";

contract IdleCreditVaultFactory is Initializable {
  using SafeERC20 for IERC20;

  uint256 public constant FULL_ALLOC = 100_000;
  uint256 public constant DEFAULT_FEE_SPLIT = 0;
  /// @notice Deployment allowance that is never decremented.
  uint256 public constant UNLIMITED_DEPLOYMENTS = type(uint256).max;
  /// @notice Pareto deployer wallet authorized to manage deployment permissions alongside treasury.
  address public constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  /// @notice Initial fee for an unlisted deployment on a supported USDC network.
  uint256 public constant DEFAULT_DEPLOYMENT_FEE = 5_000e6;
  /// @notice Pass this value for either wallet fee to use the factory default for that fee.
  uint256 public constant USE_DEFAULT_FEE = type(uint256).max;
  /// @notice Duration of one paid subscription month.
  uint256 public constant SUBSCRIPTION_PERIOD = 30 days;
  /// @notice Monthly subscription fee for wallets without an override: 500 USDC in six-decimal units.
  uint256 public constant DEFAULT_MONTHLY_SUBSCRIPTION_FEE = 500e6;

  address public treasury;
  /// @notice Share of collected fees sent to the vault's configured feeReceiver (100000 = 100%).
  /// @dev The remainder goes to the vault owner, initially treasury. The feeReceiver need not be the manager.
  uint256 public feeSplit;
  address public proxyAdmin;
  /// @notice Wallets that use a deployment allowance in either deployment flow.
  mapping(address => bool) public whitelist;
  uint256 private minPerformanceFee;
  uint256 private minManagementFee;
  // Unconfigured proxies use the default floors after a plain implementation upgrade.
  bool private minimumFeesSet;
  /// @notice Remaining deployments shared by both flows; UNLIMITED_DEPLOYMENTS never decreases.
  mapping(address => uint256) public remainingDeployments;
  /// @notice Default fee per unlisted deployment in six-decimal USDC units. Zero disables all unlisted deployments.
  uint256 public deploymentFee;
  /// @notice Timestamp until which each wallet's subscription is paid; zero if never paid.
  mapping(address => uint256) public subscriptionPaidUntil;
  // Each stored price is zero for the default, or the custom price plus one (one is a waiver).
  mapping(address => WalletFees) private walletFeeOverrides;

  /// @notice Both prices for one wallet, in six-decimal USDC units. Zero waives a fee.
  struct WalletFees {
    uint256 deploymentFee;
    uint256 monthlyFee;
  }

  event CreditVaultDeployed(
    address creditVault,
    address strategy,
    address queue,
    address programmableBorrower,
    address keyringWhitelist,
    address writeOffEscrow
  );

  event DeploymentFeeSet(uint256 fee);
  event WalletFeesSet(address indexed wallet, uint256 deploymentFee, uint256 monthlyFee);
  event SubscriptionPaid(address indexed wallet, uint256 months, uint256 amount, uint256 paidUntil);

  error AmountTooHigh();
  error FeesTooLow();
  error Is0();
  error OnlyTreasury();
  error OnlyTreasuryOrDeployer();
  error NotWhitelisted();
  error DeploymentLimitReached();
  error UnsupportedDeploymentFeeNetwork();
  error LengthMismatch();
  error WriteOffUnsupported();

  /// @notice Restrict wallet permission and pricing changes to treasury or the Pareto deployer.
  modifier onlyTreasuryOrDeployer() {
    if (msg.sender != treasury && msg.sender != DEPLOYER) revert OnlyTreasuryOrDeployer();
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _treasury, address _proxyAdmin) external initializer {
    if (_treasury == address(0) || _proxyAdmin == address(0)) revert Is0();
    treasury = _treasury;
    proxyAdmin = _proxyAdmin;
    _setFeeSplit(DEFAULT_FEE_SPLIT);
    if (address(deploymentFeeToken()) != address(0)) {
      deploymentFee = DEFAULT_DEPLOYMENT_FEE;
      emit DeploymentFeeSet(DEFAULT_DEPLOYMENT_FEE);
    }
    whitelist[_treasury] = true;
    whitelist[DEPLOYER] = true;
    remainingDeployments[_treasury] = UNLIMITED_DEPLOYMENTS;
    remainingDeployments[DEPLOYER] = UNLIMITED_DEPLOYMENTS;
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
  ) public {
    _authorizeDeployment();
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
  ) public {
    _authorizeDeployment();
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

  /// @notice Pay `months` of the caller's subscription, then deploy a standard credit vault in the same transaction.
  /// @dev The caller approves the subscription amount plus any deployment fee; any failure reverts both payments.
  /// Whitelisted callers pay no subscription and only use their deployment quota.
  /// @param cvParams Credit vault parameters, as in `deployCreditVault`.
  /// @param strategyData Strategy parameters, as in `deployCreditVault`.
  /// @param ancillaryParams Optional contract parameters, as in `deployCreditVault`.
  /// @param months Number of subscription months to pay; must be nonzero for an unlisted wallet with a nonzero rate.
  function deployCreditVaultWithSubscription(
    CreditVaultParams memory cvParams,
    StrategyData memory strategyData,
    AncillaryParams memory ancillaryParams,
    uint256 months
  ) external {
    _paySubscription(months);
    deployCreditVault(cvParams, strategyData, ancillaryParams);
  }

  /// @notice Pay `months` of the caller's subscription, then deploy a revolving credit vault in the same transaction.
  /// @dev The caller approves the subscription amount plus any deployment fee; any failure reverts both payments.
  /// Whitelisted callers pay no subscription and only use their deployment quota.
  /// @param cvParams Credit vault parameters, as in `deployRevolvingCreditVault`.
  /// @param strategyData Strategy parameters, as in `deployRevolvingCreditVault`.
  /// @param programmableBorrowerParams Programmable borrower parameters, as in `deployRevolvingCreditVault`.
  /// @param ancillaryParams Optional contract parameters, as in `deployRevolvingCreditVault`.
  /// @param months Number of subscription months to pay; must be nonzero for an unlisted wallet with a nonzero rate.
  function deployRevolvingCreditVaultWithSubscription(
    CreditVaultParams memory cvParams,
    StrategyData memory strategyData,
    ProgrammableBorrowerParams memory programmableBorrowerParams,
    AncillaryParams memory ancillaryParams,
    uint256 months
  ) external {
    _paySubscription(months);
    deployRevolvingCreditVault(cvParams, strategyData, programmableBorrowerParams, ancillaryParams);
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

  /// @notice Require at least one fee to meet its configured minimum.
  function _checkMinimumFees(CreditVaultParams memory cvParams) internal view {
    if (cvParams.fees < MIN_PERFORMANCE_FEE() && cvParams.managementFee < MIN_MANAGEMENT_FEE()) revert FeesTooLow();
  }

  /// @notice Effective minimum performance fee, with 100000 representing 100%.
  /// @dev Preserves the legacy getter and defaults to 5% until treasury configures the floors.
  function MIN_PERFORMANCE_FEE() public view returns (uint256) {
    return minimumFeesSet ? minPerformanceFee : 5_000;
  }

  /// @notice Effective minimum annual management fee, with 100000 representing 100%.
  /// @dev Preserves the legacy getter and defaults to 0.2% until treasury configures the floors.
  function MIN_MANAGEMENT_FEE() public view returns (uint256) {
    return minimumFeesSet ? minManagementFee : 200;
  }

  /// @notice Update the deployment fee floors; only treasury may call this function.
  /// @dev Either floor suffices, so setting either to zero permits deployments with both fees zero.
  /// @param performanceFee Minimum performance fee, capped at the vault maximum of 20%.
  /// @param managementFee Minimum annual management fee, capped at the vault maximum of 2%.
  function setMinimumFees(uint256 performanceFee, uint256 managementFee) external {
    if (msg.sender != treasury) revert OnlyTreasury();
    if (performanceFee > 20_000 || managementFee > 2_000) revert AmountTooHigh();
    minPerformanceFee = performanceFee;
    minManagementFee = managementFee;
    minimumFeesSet = true;
  }

  /// @notice Set remaining deployment allowances and whitelist status for multiple wallets.
  /// @dev Only treasury or the Pareto deployer may call this. Values replace remaining allowances, not add to them.
  /// @param wallets Wallets whose deployment permissions are updated.
  /// @param allowances Remaining deployments per wallet; zero removes the wallet from the whitelist.
  function setDeploymentAllowances(address[] calldata wallets, uint256[] calldata allowances) external onlyTreasuryOrDeployer {
    if (wallets.length != allowances.length) revert LengthMismatch();
    for (uint256 i = 0; i < wallets.length; i++) {
      remainingDeployments[wallets[i]] = allowances[i];
      whitelist[wallets[i]] = allowances[i] != 0;
    }
  }

  /// @notice Replace both prices for each wallet. Only treasury or the Pareto deployer may call this.
  /// @dev Zero waives the individual fee. USE_DEFAULT_FEE clears its override. Paid periods keep their expiry.
  /// @param wallets Wallets to update, in the same order as fees.
  /// @param fees Deployment and monthly prices in six-decimal USDC units, one pair per wallet.
  function setWalletFees(address[] calldata wallets, WalletFees[] calldata fees) external onlyTreasuryOrDeployer {
    if (wallets.length != fees.length) revert LengthMismatch();
    bool supported = address(deploymentFeeToken()) != address(0);
    for (uint256 i = 0; i < wallets.length; i++) {
      address wallet = wallets[i];
      WalletFees calldata terms = fees[i];
      walletFeeOverrides[wallet] = WalletFees(
        _encodeWalletFee(terms.deploymentFee, supported),
        _encodeWalletFee(terms.monthlyFee, supported)
      );
      emit WalletFeesSet(wallet, terms.deploymentFee, terms.monthlyFee);
    }
  }

  /// @notice Encode a price so an untouched storage slot inherits the default and zero USDC is an explicit waiver.
  /// @param price Custom USDC price or USE_DEFAULT_FEE to inherit the default.
  /// @param supported Whether the network has a fee token.
  function _encodeWalletFee(uint256 price, bool supported) internal pure returns (uint256) {
    if (price == USE_DEFAULT_FEE) return 0;
    if (!supported && price != 0) revert UnsupportedDeploymentFeeNetwork();
    return price + 1;
  }

  /// @notice Resolve an encoded wallet price, including an explicit zero waiver.
  /// @param stored Price as stored in walletFeeOverrides.
  /// @param defaultFee Value to return when the wallet inherits the default.
  function _decodeWalletFee(uint256 stored, uint256 defaultFee) internal pure returns (uint256) {
    return stored == 0 ? defaultFee : stored - 1;
  }

  /// @notice Read both configured prices, returning USE_DEFAULT_FEE for each price that follows its default.
  /// @param wallet Wallet whose pricing terms are requested.
  function walletFees(address wallet) external view returns (WalletFees memory terms) {
    terms = walletFeeOverrides[wallet];
    terms.deploymentFee = _decodeWalletFee(terms.deploymentFee, USE_DEFAULT_FEE);
    terms.monthlyFee = _decodeWalletFee(terms.monthlyFee, USE_DEFAULT_FEE);
  }

  /// @notice Effective monthly subscription fee for `wallet`, in six-decimal USDC units.
  /// @dev Wallets without an override pay DEFAULT_MONTHLY_SUBSCRIPTION_FEE. Returns zero on networks without
  /// a fee token, where subscriptions cannot be paid.
  /// @param wallet Wallet to check.
  function monthlySubscriptionFee(address wallet) public view returns (uint256) {
    if (address(deploymentFeeToken()) == address(0)) return 0;
    return _decodeWalletFee(walletFeeOverrides[wallet].monthlyFee, DEFAULT_MONTHLY_SUBSCRIPTION_FEE);
  }

  /// @notice Pay `months` subscription months for the caller in `deploymentFeeToken()`.
  /// @dev An early renewal adds `months * SUBSCRIPTION_PERIOD` to the current `subscriptionPaidUntil`; a late
  /// payment adds it to the payment time. Whitelisted callers are exempt: the call returns without charging,
  /// extending, or emitting. Otherwise reverts with `Is0` when `months` or the caller's rate is zero.
  /// @param months Number of `SUBSCRIPTION_PERIOD` months to pay.
  function paySubscription(uint256 months) external {
    _paySubscription(months);
  }

  /// @notice Return whether the UI should prompt `wallet` to pay its subscription.
  /// @dev False for whitelisted wallets and zero-rate wallets; otherwise true once `subscriptionPaidUntil` is reached.
  /// @param wallet Wallet to check.
  function isSubscriptionDue(address wallet) external view returns (bool) {
    return !whitelist[wallet] &&
      monthlySubscriptionFee(wallet) != 0 &&
      subscriptionPaidUntil[wallet] <= block.timestamp;
  }

  /// @notice Set the default USDC fee for unlisted callers. Only treasury may call this function.
  /// @param fee USDC in six-decimal units. Set to zero to disable paid deployments.
  function setDeploymentFee(uint256 fee) external {
    if (msg.sender != treasury) revert OnlyTreasury();
    if (fee != 0 && address(deploymentFeeToken()) == address(0)) revert UnsupportedDeploymentFeeNetwork();
    deploymentFee = fee;
    emit DeploymentFeeSet(fee);
  }

  /// @notice Quote the deployment fee for a wallet in six-decimal USDC units.
  /// @dev Returns zero for whitelist quota deployments and when unlisted deployments are disabled.
  /// @param wallet The wallet that will call the factory.
  function deploymentFeeFor(address wallet) public view returns (uint256) {
    if (deploymentFee == 0 || whitelist[wallet]) return 0;
    return _decodeWalletFee(walletFeeOverrides[wallet].deploymentFee, deploymentFee);
  }

  /// @notice Return native USDC on supported factory networks, or zero on other networks.
  function deploymentFeeToken() public view returns (IERC20) {
    if (block.chainid == 1) return IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    if (block.chainid == 8453) return IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    if (block.chainid == 42161) return IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    return IERC20(address(0));
  }

  /// @notice Consume a whitelisted caller's quota or collect one USDC fee from an unlisted caller.
  /// @dev Both flows authorize once. A reverted deployment rolls back quota consumption and payment.
  function _authorizeDeployment() internal {
    if (!whitelist[msg.sender]) {
      if (deploymentFee == 0) revert NotWhitelisted();
      uint256 fee = deploymentFeeFor(msg.sender);
      if (fee != 0) deploymentFeeToken().safeTransferFrom(msg.sender, treasury, fee);
      return;
    }
    uint256 remaining = remainingDeployments[msg.sender];
    if (remaining == 0) revert DeploymentLimitReached();
    if (remaining != UNLIMITED_DEPLOYMENTS) remainingDeployments[msg.sender] = remaining - 1;
  }

  /// @notice Charge the caller `months` times its monthly rate and extend its paid-through timestamp.
  /// @dev Whitelisted callers are exempt and return early, keeping their configured rate for use after delisting.
  /// Paying before expiry extends from the current expiry, so no paid time is lost: with an expiry of March 30,
  /// one month paid on March 20 runs to about April 29. Paying on or after expiry adds the months from the
  /// payment time; the lapsed gap is not charged.
  /// @param months Number of `SUBSCRIPTION_PERIOD` months to pay.
  function _paySubscription(uint256 months) internal {
    if (whitelist[msg.sender]) return;
    uint256 amount = monthlySubscriptionFee(msg.sender) * months;
    if (amount == 0) revert Is0();
    uint256 paidUntil = subscriptionPaidUntil[msg.sender];
    uint256 start = paidUntil > block.timestamp ? paidUntil : block.timestamp;
    uint256 newPaidUntil = start + months * SUBSCRIPTION_PERIOD;
    subscriptionPaidUntil[msg.sender] = newPaidUntil;
    deploymentFeeToken().safeTransferFrom(msg.sender, treasury, amount);
    emit SubscriptionPaid(msg.sender, months, amount, newPaidUntil);
  }

  /// @notice Set the fee receiver's share for future vault deployments; only treasury may call this.
  /// @param _feeSplit Share sent to feeReceiver; e.g. 70000 sends 70% to feeReceiver and 30% to the vault owner.
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
