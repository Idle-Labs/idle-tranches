// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IdleCDOEpochVariantPrefunded} from "../../contracts/IdleCDOEpochVariantPrefunded.sol";
import {IdleCDOEpochQueue} from "../../contracts/IdleCDOEpochQueue.sol";
import {IdleCreditVaultFactory} from "../../contracts/IdleCreditVaultFactory.sol";
import {IdleCreditVaultWriteOffEscrow} from "../../contracts/IdleCreditVaultWriteOffEscrow.sol";
import {KeyringIdleWhitelist} from "../../contracts/KeyringIdleWhitelist.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {ProgrammableBorrower} from "../../contracts/strategies/idle/ProgrammableBorrower.sol";

contract MockFactoryERC20 is ERC20 {
  uint8 private immutable tokenDecimals;

  constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
    tokenDecimals = decimals_;
  }

  function decimals() public view override returns (uint8) {
    return tokenDecimals;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract MockFactoryCDO {
  address public token;

  constructor(address token_) {
    token = token_;
  }
}

contract MockFactoryKeyring {
  function checkCredential(uint256, address) external pure returns (bool) {
    return false;
  }
}

contract MockFactoryVault is ERC20 {
  MockFactoryERC20 public immutable assetToken;

  constructor(address asset_) ERC20("Factory Vault Share", "FVS") {
    assetToken = MockFactoryERC20(asset_);
  }

  function asset() external view returns (address) {
    return address(assetToken);
  }

  function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
  }

  function convertToAssets(uint256 shares) public view returns (uint256) {
    uint256 supply = totalSupply();
    if (supply == 0) {
      return shares;
    }
    return shares * totalAssets() / supply;
  }

  function convertToShares(uint256 assets) public view returns (uint256) {
    uint256 supply = totalSupply();
    uint256 managedAssets = totalAssets();
    if (supply == 0 || managedAssets == 0) {
      return assets;
    }
    return assets * supply / managedAssets;
  }

  function maxWithdraw(address owner) external view returns (uint256) {
    return convertToAssets(balanceOf(owner));
  }

  function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
    uint256 assetsBefore = totalAssets();
    uint256 supply = totalSupply();
    shares = supply == 0 || assetsBefore == 0 ? assets : assets * supply / assetsBefore;
    assetToken.transferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);
  }

  function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
    shares = _toSharesRoundUp(assets);
    if (msg.sender != owner) {
      _spendAllowance(owner, msg.sender, shares);
    }
    _burn(owner, shares);
    assetToken.transfer(receiver, assets);
  }

  function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
    assets = convertToAssets(shares);
    if (msg.sender != owner) {
      _spendAllowance(owner, msg.sender, shares);
    }
    _burn(owner, shares);
    assetToken.transfer(receiver, assets);
  }

  function _toSharesRoundUp(uint256 assets) internal view returns (uint256 shares) {
    uint256 supply = totalSupply();
    uint256 managedAssets = totalAssets();
    if (supply == 0 || managedAssets == 0) {
      return assets;
    }
    shares = assets * supply / managedAssets;
    if (shares * managedAssets < assets * supply) {
      shares += 1;
    }
  }
}

contract IdleCreditVaultFactoryTest is Test {
  bytes4 internal constant AMOUNT_TOO_HIGH = bytes4(keccak256("AmountTooHigh()"));
  bytes4 internal constant FEES_TOO_LOW = bytes4(keccak256("FeesTooLow()"));
  bytes4 internal constant NOT_ALLOWED = bytes4(keccak256("NotAllowed()"));
  bytes4 internal constant IS_0 = bytes4(keccak256("Is0()"));
  bytes4 internal constant ONLY_TREASURY = bytes4(keccak256("OnlyTreasury()"));
  bytes4 internal constant WRITE_OFF_UNSUPPORTED = bytes4(keccak256("WriteOffUnsupported()"));
  bytes32 internal constant CREDIT_VAULT_DEPLOYED =
    keccak256("CreditVaultDeployed(address,address,address,address,address,address)");
  bytes32 internal constant EIP1967_ADMIN_SLOT =
    0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
  uint256 internal constant DEFAULT_FACTORY_FEE_SPLIT = 0;
  uint256 internal constant CDO_SLOT_GOVERNANCE_RECOVERY_FUND = 202;
  uint256 internal constant CDO_SLOT_GUARDIAN = 208;
  uint256 internal constant DEPLOYMENT_FEE = 5_000e6;
  uint256 internal constant USE_DEFAULT = type(uint256).max;
  uint256 internal constant CUSTOM_DEPLOYMENT_FEE = 2_000e6;
  IERC20 internal constant MAINNET_FEE_USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IERC20 internal constant BASE_FEE_USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
  IERC20 internal constant ARBITRUM_FEE_USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
  address internal constant MAINNET_FEE_TREASURY = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  address internal constant BASE_FEE_TREASURY = 0xFDbB4d606C199F091143BD604C85c191a526fbd0;
  address internal constant ARBITRUM_FEE_TREASURY = 0xF40d482D7fc94C30b256Dc7E722033bae68EcF90;
  uint256 internal constant SUBSCRIPTION_FEE = 100e6;
  uint256 internal constant OTHER_SUBSCRIPTION_FEE = 250e6;
  uint256 internal constant DEFAULT_SUBSCRIPTION_FEE = 500e6;
  uint256 internal constant SUBSCRIPTION_MONTH = 30 days;

  event SubscriptionPaid(address indexed wallet, uint256 months, uint256 amount, uint256 paidUntil);

  struct AncillaryDeployment {
    address cv;
    address strategy;
    address queue;
    address programmableBorrower;
    address keyringWhitelist;
    address writeOffEscrow;
  }

  address internal owner = makeAddr("owner");
  address internal creator = makeAddr("creator");
  address internal creatorFeeReceiver = makeAddr("creatorFeeReceiver");
  address internal manager = makeAddr("manager");
  address internal realBorrower = makeAddr("realBorrower");
  address internal proxyAdmin = makeAddr("proxyAdmin");
  address internal factoryProxyAdmin = makeAddr("factoryProxyAdmin");
  address internal feePayer = makeAddr("factoryFeePayer");

  /// @notice Treasury and the Pareto deployer can independently grant and revoke deployment access.
  function testWhitelistAdminsCanGrantAndRevokeAccess() external {
    IdleCreditVaultFactory factory = _deployFactory();
    address[2] memory admins = [owner, factory.DEPLOYER()];
    address wallet = makeAddr("wallet");

    for (uint256 i = 0; i < admins.length; i++) {
      _setDeploymentAllowance(factory, admins[i], wallet, 1);
      assertTrue(factory.whitelist(wallet), "wallet allowed");

      // Repeating the same grant replaces the remaining allowance rather than adding to it.
      _setDeploymentAllowance(factory, admins[i], wallet, 1);
      assertTrue(factory.whitelist(wallet), "wallet still allowed");
      assertEq(factory.remainingDeployments(wallet), 1);

      _setDeploymentAllowance(factory, admins[i], wallet, 0);
      assertFalse(factory.whitelist(wallet), "wallet revoked");
    }
  }

  /// @notice Deployment permission does not allow a creator to manage the whitelist.
  function testWhitelistedCreatorCannotUpdateWhitelist() external {
    IdleCreditVaultFactory factory = _deployFactory();

    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    _setDeploymentAllowance(factory, creator, manager, 1);
    assertFalse(factory.whitelist(manager), "manager not added");

    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    _setDeploymentAllowance(factory, creator, creator, 0);
    assertTrue(factory.whitelist(creator), "creator not removed");
  }

  /// @notice An unlisted wallet cannot grant itself deployment permission.
  function testUnlistedWalletCannotWhitelistItself() external {
    IdleCreditVaultFactory factory = _deployFactory();

    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    _setDeploymentAllowance(factory, manager, manager, 1);
    assertFalse(factory.whitelist(manager), "manager not added");
  }

  /// @notice Both deployment flows reject unlisted callers.
  function testUnlistedWalletsCannotDeploy() external {
    IdleCreditVaultFactory factory = _deployFactory();
    _assertDeploymentNotWhitelisted(factory, manager);
  }

  /// @notice Initially whitelisted admins can have deployment access revoked without losing whitelist management.
  function testRevokedAdminsCannotDeploy() external {
    IdleCreditVaultFactory factory = _deployFactory();
    address[2] memory admins = [owner, factory.DEPLOYER()];

    for (uint256 i = 0; i < admins.length; i++) {
      _setDeploymentAllowance(factory, owner, admins[i], 0);
      _assertDeploymentNotWhitelisted(factory, admins[i]);

      _setDeploymentAllowance(factory, admins[i], admins[i], type(uint256).max);
      assertTrue(factory.whitelist(admins[i]), "admin allowed again");
    }
  }

  /// @notice Revoking an allowed creator immediately blocks both deployment flows.
  function testRevokedCreatorCannotDeploy() external {
    IdleCreditVaultFactory factory = _deployFactory();
    _setDeploymentAllowance(factory, owner, creator, 0);
    _assertDeploymentNotWhitelisted(factory, creator);
  }

  /// @notice Either admin can batch-grant finite or unlimited allowances and revoke wallets with zero.
  function testBatchDeploymentAllowances() external {
    IdleCreditVaultFactory factory = _deployFactory();
    address[] memory wallets = new address[](3);
    wallets[0] = creator;
    wallets[1] = manager;
    wallets[2] = factory.DEPLOYER();
    uint256[] memory allowances = new uint256[](3);
    allowances[0] = 4;
    allowances[1] = 0;
    allowances[2] = factory.UNLIMITED_DEPLOYMENTS();
    vm.prank(owner);
    factory.setDeploymentAllowances(wallets, allowances);
    assertEq(factory.remainingDeployments(creator), 4, "replaces rather than adds");
    assertTrue(factory.whitelist(creator));
    assertFalse(factory.whitelist(manager));
    assertEq(factory.remainingDeployments(manager), 0);
    assertEq(factory.remainingDeployments(wallets[2]), type(uint256).max);

    allowances[0] = 0;
    allowances[1] = 3;
    allowances[2] = 0;
    vm.prank(wallets[2]);
    factory.setDeploymentAllowances(wallets, allowances);
    assertFalse(factory.whitelist(creator));
    assertEq(factory.remainingDeployments(creator), 0);
    assertTrue(factory.whitelist(manager));
    assertEq(factory.remainingDeployments(manager), 3);
    _assertDeploymentNotWhitelisted(factory, creator);
    _assertDeploymentNotWhitelisted(factory, wallets[2]);
    // Revoking deployment access does not remove the deployer's administrative authority.
    _setDeploymentAllowance(factory, wallets[2], wallets[2], type(uint256).max);
    assertTrue(factory.whitelist(wallets[2]));
  }

  /// @notice Invalid batch lengths and unauthorized callers cannot modify any allowance or whitelist entry.
  function testBatchDeploymentAllowancesRejectInvalidCalls() external {
    IdleCreditVaultFactory factory = _deployFactory();
    address[] memory wallets = new address[](2);
    wallets[0] = creator;
    wallets[1] = manager;
    uint256[] memory allowances = new uint256[](1);
    allowances[0] = 0;
    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    vm.prank(creator);
    factory.setDeploymentAllowances(wallets, allowances);
    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    vm.prank(manager);
    factory.setDeploymentAllowances(wallets, allowances);
    vm.expectRevert(IdleCreditVaultFactory.LengthMismatch.selector);
    vm.prank(owner);
    factory.setDeploymentAllowances(wallets, allowances);
    assertTrue(factory.whitelist(creator));
    assertEq(factory.remainingDeployments(creator), 2);
    assertFalse(factory.whitelist(manager));
  }

  /// @notice Standard and revolving deployments consume the same allowance, then both are blocked at zero.
  function testDeploymentAllowanceSharedAcrossFlows() external {
    vm.warp(100 days);
    IdleCreditVaultFactory factory = _deployFactory();
    _deployStandardCreditVault(factory);
    assertEq(factory.remainingDeployments(creator), 1);
    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    _deployRevolvingCreditVault(factory, underlying, new MockFactoryVault(address(underlying)));
    assertEq(factory.remainingDeployments(creator), 0);
    _assertFactoryFeeGate(factory, 5000, 0, IdleCreditVaultFactory.DeploymentLimitReached.selector);

    // An admin must explicitly replenish the exhausted allowance.
    _setDeploymentAllowance(factory, owner, creator, 1);
    _deployStandardCreditVault(factory);
    assertEq(factory.remainingDeployments(creator), 0);
  }

  /// @notice Unlimited allowances remain unchanged in either flow, while whitelist revocation still applies.
  function testUnlimitedDeploymentAllowance() external {
    vm.warp(100 days);
    IdleCreditVaultFactory factory = _deployFactory();
    address testCreator = creator;
    creator = factory.DEPLOYER();
    _deployStandardCreditVault(factory);
    assertEq(factory.remainingDeployments(creator), type(uint256).max);
    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    _deployRevolvingCreditVault(factory, underlying, new MockFactoryVault(address(underlying)));
    assertEq(factory.remainingDeployments(creator), type(uint256).max);
    _setDeploymentAllowance(factory, owner, creator, 0);
    _assertDeploymentNotWhitelisted(factory, creator);
    assertEq(factory.remainingDeployments(creator), 0);

    creator = testCreator;
    _setDeploymentAllowance(factory, owner, creator, type(uint256).max);
    _deployStandardCreditVault(factory);
    assertEq(factory.remainingDeployments(creator), type(uint256).max, "unlimited is configurable for any wallet");
  }

  /// @notice Whitelist permission alone does not grant a deployment quota after upgrading.
  function testWhitelistWithoutAllowanceCannotDeploy() external {
    IdleCreditVaultFactory factory = _deployFactory();
    creator = manager;
    // Simulate an entry from the earlier whitelist-only implementation (mapping at slot 3).
    vm.store(address(factory), keccak256(abi.encode(creator, uint256(3))), bytes32(uint256(1)));
    assertEq(factory.remainingDeployments(creator), 0);
    _assertFactoryFeeGate(factory, 5000, 0, IdleCreditVaultFactory.DeploymentLimitReached.selector);
  }

  /// @notice Reverts both before and after proxy creation restore the caller's full allowance.
  function testRevertedDeploymentsPreserveAllowance() external {
    vm.warp(100 days);
    IdleCreditVaultFactory factory = _deployFactory();
    _assertFactoryFeeGate(factory, 0, 0, FEES_TOO_LOW);
    assertEq(factory.remainingDeployments(creator), 2);
    _assertFactoryFeeGate(factory, 5000, 0, IS_0);
    assertEq(factory.remainingDeployments(creator), 2);

    // A zero fee receiver makes CDO configuration revert after the proxies have been created.
    IdleCreditVaultFactory.CreditVaultParams memory cvParams = _makeCreditVaultParams(address(0));
    cvParams.underlying = address(new MockFactoryERC20("Mock USDC", "mUSDC", 6));
    cvParams.implementation = address(new IdleCDOEpochVariant());
    IdleCreditVaultFactory.StrategyData memory strategyData;
    strategyData.implementation = address(new IdleCreditVault());
    strategyData.manager = manager;
    strategyData.borrower = realBorrower;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory borrowerParams;
    vm.expectRevert(IS_0);
    vm.prank(creator);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    assertEq(factory.remainingDeployments(creator), 2);
    vm.expectRevert(IS_0);
    vm.prank(creator);
    factory.deployRevolvingCreditVault(cvParams, strategyData, borrowerParams, ancillaryParams);
    assertEq(factory.remainingDeployments(creator), 2);
  }

  /// @notice Grant one wallet an explicit remaining allowance through the batch API.
  function _setDeploymentAllowance(IdleCreditVaultFactory factory, address admin, address wallet, uint256 allowance) internal {
    address[] memory wallets = new address[](1);
    wallets[0] = wallet;
    uint256[] memory allowances = new uint256[](1);
    allowances[0] = allowance;
    vm.prank(admin);
    factory.setDeploymentAllowances(wallets, allowances);
  }

  /// @notice Apply both fee terms to one wallet through the batch API.
  function _setWalletFees(IdleCreditVaultFactory factory, address admin, address wallet, uint256 deployment, uint256 monthly) internal {
    address[] memory wallets = new address[](1);
    wallets[0] = wallet;
    IdleCreditVaultFactory.WalletFees[] memory fees = new IdleCreditVaultFactory.WalletFees[](1);
    fees[0] = IdleCreditVaultFactory.WalletFees(deployment, monthly);
    vm.prank(admin);
    factory.setWalletFees(wallets, fees);
  }

  /// @notice Complete a standard deployment as the test creator to exercise successful quota consumption.
  function _deployStandardCreditVault(IdleCreditVaultFactory factory) internal {
    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    _deployCreditVaultWithConfig(
      factory, underlying, address(new IdleCDOEpochVariant()), _makeCreditVaultParams(creatorFeeReceiver), ancillaryParams
    );
  }

  /// @notice Neither the implementation nor an initialized factory proxy can be initialized again.
  function testFactoryInitializationIsLocked() external {
    IdleCreditVaultFactory implementation = new IdleCreditVaultFactory();
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    implementation.initialize(owner, proxyAdmin);

    IdleCreditVaultFactory factory = _deployFactory();
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    factory.initialize(manager, factoryProxyAdmin);
    assertEq(factory.treasury(), owner, "treasury preserved");
    assertTrue(factory.whitelist(creator), "whitelist preserved");
  }

  /// @notice Only treasury may change floors, independently of deployment whitelist membership.
  function testMinimumFeesAreTreasuryOnly() external {
    IdleCreditVaultFactory factory = _deployFactory();
    address[3] memory callers = [creator, manager, factory.DEPLOYER()];
    for (uint256 i = 0; i < callers.length; i++) {
      vm.expectRevert(ONLY_TREASURY);
      vm.prank(callers[i]);
      factory.setMinimumFees(1000, 100);
    }
    _setDeploymentAllowance(factory, owner, owner, 0);
    vm.prank(owner);
    factory.setMinimumFees(1000, 100);
    assertEq(factory.MIN_PERFORMANCE_FEE(), 1000);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 100);
  }

  /// @notice Floors cannot exceed the actual maximum fees accepted by credit vaults.
  function testMinimumFeesRespectVaultCaps() external {
    IdleCreditVaultFactory factory = _deployFactory();
    vm.startPrank(owner);
    vm.expectRevert(AMOUNT_TOO_HIGH);
    factory.setMinimumFees(20001, 500);
    vm.expectRevert(AMOUNT_TOO_HIGH);
    factory.setMinimumFees(5000, 2001);
    assertEq(factory.MIN_PERFORMANCE_FEE(), 5000);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 200);
    factory.setMinimumFees(20000, 2000);
    vm.stopPrank();
    assertEq(factory.MIN_PERFORMANCE_FEE(), 20000);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 2000);
  }

  /// @notice Both paths use updated floors and retain the inclusive either-fee acceptance rule.
  function testUpdatedMinimumFeesApplyToBothDeploymentFlows() external {
    IdleCreditVaultFactory factory = _deployFactory();
    _assertFactoryFeeGate(factory, 4999, 199, FEES_TOO_LOW);
    vm.prank(owner);
    factory.setMinimumFees(10000, 1000);
    _assertFactoryFeeGate(factory, 5000, 500, FEES_TOO_LOW);
    _assertFactoryFeeGate(factory, 9999, 999, FEES_TOO_LOW);
    _assertFactoryFeeGate(factory, 10000, 0, IS_0);
    _assertFactoryFeeGate(factory, 0, 1000, IS_0);

    vm.prank(owner);
    factory.setMinimumFees(2000, 200);
    _assertFactoryFeeGate(factory, 1999, 199, FEES_TOO_LOW);
    _assertFactoryFeeGate(factory, 2000, 0, IS_0);
    _assertFactoryFeeGate(factory, 0, 200, IS_0);
  }

  /// @notice An explicit zero floor disables the combined gate instead of restoring legacy defaults.
  function testZeroMinimumFeePermitsZeroFees() external {
    vm.warp(100 days);
    IdleCreditVaultFactory factory = _deployFactory();
    vm.prank(owner);
    factory.setMinimumFees(0, 500);
    assertEq(factory.MIN_PERFORMANCE_FEE(), 0);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 500);
    _assertFactoryFeeGate(factory, 0, 0, IS_0);
    vm.prank(owner);
    factory.setMinimumFees(5000, 0);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 0);
    _assertFactoryFeeGate(factory, 0, 0, IS_0);

    vm.prank(owner);
    factory.setMinimumFees(0, 0);
    assertEq(factory.MIN_PERFORMANCE_FEE(), 0);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 0);
    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory.CreditVaultParams memory cvParams = _makeCreditVaultParams(creatorFeeReceiver);
    cvParams.fees = 0;
    cvParams.managementFee = 0;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    AncillaryDeployment memory deployment = _deployCreditVaultWithConfig(
      factory, underlying, address(new IdleCDOEpochVariant()), cvParams, ancillaryParams
    );
    assertEq(IdleCDOEpochVariant(deployment.cv).fee(), 0);
    assertEq(IdleCDOEpochVariant(deployment.cv).managementFee(), 0);
    vm.prank(owner);
    factory.setMinimumFees(5000, 500);
    _assertFactoryFeeGate(factory, 0, 0, FEES_TOO_LOW);
    assertEq(IdleCDOEpochVariant(deployment.cv).fee(), 0, "existing fees unchanged");
    assertEq(IdleCDOEpochVariant(deployment.cv).managementFee(), 0, "existing management fee unchanged");
  }

  /// @notice Ordinary upgrades preserve configured floors, including an intentional zero value.
  function testConfiguredMinimumFeesSurviveUpgrade() external {
    IdleCreditVaultFactory factory = _deployFactory();
    vm.prank(owner);
    factory.setMinimumFees(0, 200);
    IdleCreditVaultFactory implementation = new IdleCreditVaultFactory();
    vm.prank(factoryProxyAdmin);
    ITransparentUpgradeableProxy(address(factory)).upgradeTo(address(implementation));
    assertEq(factory.MIN_PERFORMANCE_FEE(), 0);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 200);
    assertTrue(factory.whitelist(creator));
    assertEq(factory.remainingDeployments(creator), 2, "quota preserved");
    _assertFactoryFeeGate(factory, 0, 0, IS_0);
  }

  /// @notice Rehearse a plain upgrade of the production Mainnet V3 factory without initialization.
  function testMainnetFactoryUpgrade() external {
    vm.createSelectFork("mainnet", 26290277);
    _assertFactoryUpgrade(0xd6C6f31091Bf6E4a6a48C91cfA4C341f1BaB44ff);
  }

  /// @notice Rehearse the same upgrade and treasury configuration on the production Base V3 factory.
  function testBaseFactoryUpgrade() external {
    vm.createSelectFork(vm.envString("BASE_RPC_URL"), 53194953);
    _assertFactoryUpgrade(0x4220714A44EAF70810AB8742a8875FAcEe2De004);
  }

  /// @notice Preserve legacy state, require explicit whitelist grants, and apply default then custom floors.
  function _assertFactoryUpgrade(address factoryAddress) internal {
    IdleCreditVaultFactory factory = IdleCreditVaultFactory(factoryAddress);
    address treasuryBefore = factory.treasury();
    address adminBefore = factory.proxyAdmin();
    uint256 splitBefore = factory.feeSplit();
    bytes32[8] memory slots;
    for (uint256 i = 0; i < slots.length; i++) slots[i] = vm.load(factoryAddress, bytes32(i));
    ProxyAdmin admin = ProxyAdmin(address(uint160(uint256(vm.load(factoryAddress, EIP1967_ADMIN_SLOT)))));
    address adminOwner = admin.owner();
    IdleCreditVaultFactory implementation = new IdleCreditVaultFactory();
    vm.prank(adminOwner);
    admin.upgrade(ITransparentUpgradeableProxy(factoryAddress), address(implementation));
    assertEq(admin.getProxyImplementation(ITransparentUpgradeableProxy(factoryAddress)), address(implementation));
    for (uint256 i = 0; i < slots.length; i++) assertEq(vm.load(factoryAddress, bytes32(i)), slots[i]);
    assertEq(factory.treasury(), treasuryBefore);
    assertEq(factory.proxyAdmin(), adminBefore);
    assertEq(factory.feeSplit(), splitBefore);
    assertEq(factory.MIN_PERFORMANCE_FEE(), 5000);
    assertEq(factory.MIN_MANAGEMENT_FEE(), 200);
    assertFalse(factory.whitelist(treasuryBefore), "initialize not rerun");
    assertFalse(factory.whitelist(factory.DEPLOYER()), "deployer not automatically granted access");
    assertEq(factory.remainingDeployments(treasuryBefore), 0);
    assertEq(factory.remainingDeployments(factory.DEPLOYER()), 0);
    _assertDeploymentNotWhitelisted(factory, treasuryBefore);
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    factory.initialize(owner, proxyAdmin);

    _assertDeploymentNotWhitelisted(factory, creator);
    _setDeploymentAllowance(factory, factory.DEPLOYER(), creator, 2);
    _assertFactoryFeeGate(factory, 4999, 199, FEES_TOO_LOW);
    _assertFactoryFeeGate(factory, 5000, 0, IS_0);
    _assertFactoryFeeGate(factory, 0, 200, IS_0);
    vm.prank(treasuryBefore);
    factory.setMinimumFees(1000, 100);
    _assertFactoryFeeGate(factory, 999, 99, FEES_TOO_LOW);
    _assertFactoryFeeGate(factory, 1000, 0, IS_0);
    _assertFactoryFeeGate(factory, 0, 100, IS_0);
    _setDeploymentAllowance(factory, treasuryBefore, factory.DEPLOYER(), type(uint256).max);
    assertEq(factory.remainingDeployments(factory.DEPLOYER()), type(uint256).max);
    _deployStandardCreditVault(factory);
    assertEq(factory.remainingDeployments(creator), 1, "upgraded factory consumes quota");
  }

  /// @notice Use a zero manager to stop after the fee gate, before deploying any contracts.
  function _assertFactoryFeeGate(IdleCreditVaultFactory factory, uint256 fees, uint256 managementFee, bytes4 expected) internal {
    IdleCreditVaultFactory.CreditVaultParams memory cvParams;
    cvParams.fees = fees;
    cvParams.managementFee = managementFee;
    IdleCreditVaultFactory.StrategyData memory strategyData;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory borrowerParams;
    vm.expectRevert(expected);
    vm.prank(creator);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.expectRevert(expected);
    vm.prank(creator);
    factory.deployRevolvingCreditVault(cvParams, strategyData, borrowerParams, ancillaryParams);
  }

  /// @notice Check authorization before any deployment inputs or external calls are processed.
  function _assertDeploymentNotWhitelisted(IdleCreditVaultFactory factory, address caller) internal {
    IdleCreditVaultFactory.CreditVaultParams memory cvParams;
    IdleCreditVaultFactory.StrategyData memory strategyData;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory borrowerParams;

    vm.expectRevert(IdleCreditVaultFactory.NotWhitelisted.selector);
    vm.prank(caller);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);

    vm.expectRevert(IdleCreditVaultFactory.NotWhitelisted.selector);
    vm.prank(caller);
    factory.deployRevolvingCreditVault(cvParams, strategyData, borrowerParams, ancillaryParams);
  }

  /// @notice Reads an address from a CDO storage slot whose generated getter was removed.
  function _cdoAddress(address _cdo, uint256 _slot) internal view returns (address) {
    return address(uint160(uint256(vm.load(_cdo, bytes32(_slot)))));
  }

  function testDeployRevolvingCreditVaultWiresProgrammableBorrower() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryVault vault = new MockFactoryVault(address(underlying));
    IdleCreditVaultFactory factory = _deployFactory();
    (address cvProxy, address strategyProxy, address programmableBorrowerProxy) = _deployRevolvingCreditVault(factory, underlying, vault);
    _assertDeployment(cvProxy, strategyProxy, programmableBorrowerProxy, address(underlying), address(vault));
  }

  function testInitializeProgrammableBorrowerSetsBorrowerAndApr() external {
    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryVault vault = new MockFactoryVault(address(underlying));
    address idleCDOAddress = address(new MockFactoryCDO(address(underlying)));
    ProgrammableBorrower programmableBorrowerImplementation = new ProgrammableBorrower();
    ProgrammableBorrower programmableBorrower = ProgrammableBorrower(address(new TransparentUpgradeableProxy(
      address(programmableBorrowerImplementation),
      proxyAdmin,
      abi.encodeWithSelector(
        ProgrammableBorrower.initialize.selector,
        address(vault),
        idleCDOAddress,
        owner,
        manager,
        realBorrower,
        365e18
      )
    )));

    assertEq(programmableBorrower.owner(), owner, "owner");
    assertEq(programmableBorrower.manager(), manager, "manager");
    assertEq(programmableBorrower.idleCDO(), idleCDOAddress, "idle cdo");
    assertEq(programmableBorrower.borrower(), realBorrower, "borrower");
    assertEq(programmableBorrower.borrowerApr(), 365e18, "borrower apr");
  }

  function testProgrammableBorrowerImplementationInitializerIsDisabled() external {
    ProgrammableBorrower programmableBorrowerImplementation = new ProgrammableBorrower();

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    programmableBorrowerImplementation.initialize(
      address(0),
      address(0),
      address(0),
      address(0),
      address(0),
      0
    );
  }

  function testDeployCreditVaultWiresAncillaryContracts() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryKeyring keyring = new MockFactoryKeyring();
    IdleCreditVaultFactory factory = _deployFactory();
    AncillaryDeployment memory deployment =
      _deployCreditVaultWithAncillaries(factory, underlying, address(keyring));

    IdleCDOEpochVariant cv = IdleCDOEpochVariant(deployment.cv);
    IdleCreditVault strategy = IdleCreditVault(deployment.strategy);
    IdleCDOEpochQueue queue = IdleCDOEpochQueue(deployment.queue);
    KeyringIdleWhitelist keyringWhitelist = KeyringIdleWhitelist(deployment.keyringWhitelist);
    IdleCreditVaultWriteOffEscrow writeOffEscrow = IdleCreditVaultWriteOffEscrow(deployment.writeOffEscrow);

    assertEq(cv.owner(), owner, "cdo owner");
    assertEq(_cdoAddress(address(cv), CDO_SLOT_GOVERNANCE_RECOVERY_FUND), owner, "cdo governance fund");
    assertEq(_cdoAddress(address(cv), CDO_SLOT_GUARDIAN), manager, "cdo guardian");
    assertEq(cv.trancheAPRSplitRatio(), 100000, "AA-only APR split");
    assertFalse(cv.isBBDepositEnabled(), "BB deposits enabled by default");
    assertEq(deployment.programmableBorrower, address(0), "programmable borrower unsupported");
    assertEq(strategy.owner(), owner, "strategy owner");
    _assertProxyAdmin(deployment.cv);
    _assertProxyAdmin(deployment.strategy);
    _assertProxyAdmin(deployment.queue);
    _assertProxyAdmin(deployment.writeOffEscrow);
    assertEq(strategy.manager(), manager, "strategy manager");
    assertEq(queue.owner(), owner, "queue owner");
    assertEq(writeOffEscrow.owner(), owner, "write-off owner");
    assertEq(cv.keyring(), deployment.keyringWhitelist, "deployed keyring");
    assertEq(keyringWhitelist.keyring(), address(keyring), "keyring contract");
    assertEq(keyringWhitelist.admin(), manager, "keyring admin");
    assertTrue(keyringWhitelist.whitelist(deployment.queue), "queue whitelisted");
    assertEq(IdleCDOEpochVariantPrefunded(deployment.cv).epochQueue(), deployment.queue, "prefunded queue");
    assertEq(queue.prefundedDepositWindow(), 2 days, "prefunded window");
    assertEq(writeOffEscrow.idleCDOEpoch(), deployment.cv, "write-off cdo");
    assertEq(writeOffEscrow.strategy(), deployment.strategy, "write-off strategy");
    assertEq(writeOffEscrow.feeReceiver(), owner, "write-off fee receiver");
    assertEq(cv.feeReceiver(), creatorFeeReceiver, "fee receiver");
    assertEq(cv.fee(), 5000, "performance fee");
    assertEq(cv.feeSplit(), DEFAULT_FACTORY_FEE_SPLIT, "fee split");
    assertEq(cv.managementFee(), 500, "management fee");
    assertEq(cv.isDepositDuringEpochDisabled(), false, "deposit during epoch should be enabled");

    vm.expectRevert(AMOUNT_TOO_HIGH);
    vm.prank(owner);
    cv.setFeeParams(creatorFeeReceiver, 10000, 80000, 2001);
  }

  function testDeployCreditVaultWithoutOptionalContracts() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultFactory.CreditVaultParams memory cvParams =
      _makeCreditVaultParams(creatorFeeReceiver);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });

    AncillaryDeployment memory deployment = _deployCreditVaultWithConfig(
      factory,
      underlying,
      address(cdoImplementation),
      cvParams,
      ancillaryParams
    );
    IdleCDOEpochVariant cv = IdleCDOEpochVariant(deployment.cv);

    assertEq(deployment.queue, address(0), "queue");
    assertEq(deployment.programmableBorrower, address(0), "programmable borrower");
    assertEq(deployment.keyringWhitelist, address(0), "keyring whitelist");
    assertEq(deployment.writeOffEscrow, address(0), "write-off escrow");
    assertEq(cv.owner(), owner, "cdo owner");
    assertEq(cv.keyring(), address(0), "keyring");
    assertEq(cv.feeReceiver(), creatorFeeReceiver, "fee receiver");
    assertEq(cv.feeSplit(), DEFAULT_FACTORY_FEE_SPLIT, "fee split retained");
    _assertProxyAdmin(deployment.cv);
    _assertProxyAdmin(deployment.strategy);
  }

  function testDeployCreditVaultRevertsWhenFeeReceiverIsZero() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultFactory.CreditVaultParams memory cvParams =
      _makeCreditVaultParams(address(0));
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });
    IdleCreditVault strategyImplementation = new IdleCreditVault();
    cvParams.implementation = address(cdoImplementation);
    cvParams.limit = 0;
    cvParams.underlying = address(underlying);
    IdleCreditVaultFactory.StrategyData memory strategyData =
      _makeStrategyData(
        address(strategyImplementation),
        address(underlying),
        address(factory),
        "Standard",
        12e18
      );

    vm.prank(creator);
    vm.expectRevert(IS_0);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
  }

  function testDeployCreditVaultRevertsWhenFeesAreBelowMinimums() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultFactory.CreditVaultParams memory cvParams =
      _makeCreditVaultParams(creatorFeeReceiver);
    cvParams.fees = 4999;
    cvParams.managementFee = 199;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });

    IdleCreditVault strategyImplementation = new IdleCreditVault();

    vm.prank(creator);
    vm.expectRevert(FEES_TOO_LOW);
    cvParams.implementation = address(cdoImplementation);
    cvParams.underlying = address(underlying);
    factory.deployCreditVault(
      cvParams,
      _makeStrategyData(address(strategyImplementation), address(underlying), address(factory), "Standard", 12e18),
      ancillaryParams
    );
  }

  function testDeployCreditVaultAllowsManagementFeeMinimumWithoutPerformanceFee() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultFactory.CreditVaultParams memory cvParams =
      _makeCreditVaultParams(creatorFeeReceiver);
    cvParams.fees = 0;
    cvParams.managementFee = 200;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });

    AncillaryDeployment memory deployment = _deployCreditVaultWithConfig(
      factory,
      underlying,
      address(cdoImplementation),
      cvParams,
      ancillaryParams
    );

    IdleCDOEpochVariant cv = IdleCDOEpochVariant(deployment.cv);
    assertEq(cv.fee(), 0, "performance fee");
    assertEq(cv.managementFee(), 200, "management fee");
  }

  function testTreasuryCanUpdateFactoryFeeSplit() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    assertEq(factory.feeSplit(), DEFAULT_FACTORY_FEE_SPLIT, "default fee split");

    vm.prank(creator);
    vm.expectRevert(ONLY_TREASURY);
    factory.setFeeSplit(70000);

    address paretoDeployer = factory.DEPLOYER();
    vm.prank(paretoDeployer);
    vm.expectRevert(ONLY_TREASURY);
    factory.setFeeSplit(70000);

    vm.prank(owner);
    vm.expectRevert(AMOUNT_TOO_HIGH);
    factory.setFeeSplit(100001);

    vm.prank(owner);
    factory.setFeeSplit(70000);
    assertEq(factory.feeSplit(), 70000, "updated fee split");

    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });

    AncillaryDeployment memory deployment = _deployCreditVaultWithConfig(
      factory,
      underlying,
      address(cdoImplementation),
      _makeCreditVaultParams(creatorFeeReceiver),
      ancillaryParams
    );

    assertEq(IdleCDOEpochVariant(deployment.cv).feeSplit(), 70000, "factory fee split");
  }

  function testDeployCreditVaultDeploysKeyringWithNormalQueue() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryKeyring keyring = new MockFactoryKeyring();
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCDOEpochQueue queueImplementation = new IdleCDOEpochQueue();
    IdleCreditVaultFactory.CreditVaultParams memory cvParams =
      _makeCreditVaultParams(creatorFeeReceiver);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(keyring),
      queueImplementation: address(queueImplementation),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });

    AncillaryDeployment memory deployment = _deployCreditVaultWithConfig(
      factory,
      underlying,
      address(cdoImplementation),
      cvParams,
      ancillaryParams
    );
    IdleCDOEpochVariant cv = IdleCDOEpochVariant(deployment.cv);
    IdleCDOEpochQueue queue = IdleCDOEpochQueue(deployment.queue);
    KeyringIdleWhitelist keyringWhitelist = KeyringIdleWhitelist(deployment.keyringWhitelist);

    assertTrue(deployment.keyringWhitelist != address(0), "deployed keyring");
    assertEq(deployment.writeOffEscrow, address(0), "write-off disabled");
    assertEq(cv.keyring(), deployment.keyringWhitelist, "credit vault keyring");
    assertEq(keyringWhitelist.keyring(), address(keyring), "keyring contract");
    assertEq(keyringWhitelist.admin(), manager, "keyring admin");
    assertEq(queue.owner(), owner, "queue owner");
    assertEq(queue.prefundedDepositWindow(), 0, "normal queue");
    assertTrue(keyringWhitelist.whitelist(deployment.queue), "queue whitelisted");
  }

  function testDeployCreditVaultSetsOwnerAsWriteOffFeeReceiver() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultWriteOffEscrow writeOffImplementation = new IdleCreditVaultWriteOffEscrow();
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(writeOffImplementation)
    });

    AncillaryDeployment memory deployment = _deployCreditVaultWithConfig(
      factory,
      underlying,
      address(cdoImplementation),
      _makeCreditVaultParams(creatorFeeReceiver),
      ancillaryParams
    );
    IdleCreditVaultWriteOffEscrow writeOffEscrow = IdleCreditVaultWriteOffEscrow(deployment.writeOffEscrow);

    assertEq(writeOffEscrow.owner(), owner, "write-off owner");
    assertEq(writeOffEscrow.feeReceiver(), owner, "write-off fee receiver");
  }

  function testDeployRevolvingCreditVaultCanDeployQueueWithoutWriteOffEscrow() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryVault vault = new MockFactoryVault(address(underlying));
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochQueue queueImplementation = new IdleCDOEpochQueue();
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(queueImplementation),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });

    AncillaryDeployment memory deployment =
      _deployRevolvingCreditVaultWithAncillary(factory, underlying, vault, ancillaryParams);

    assertTrue(deployment.queue != address(0), "queue deployed");
    assertTrue(deployment.programmableBorrower != address(0), "programmable borrower deployed");
    assertEq(deployment.writeOffEscrow, address(0), "write-off unsupported");
    assertEq(IdleCDOEpochQueue(deployment.queue).owner(), owner, "queue owner");
    _assertProxyAdmin(deployment.queue);
  }

  function testDeployRevolvingCreditVaultRevertsWhenFeesAreBelowMinimums() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryVault vault = new MockFactoryVault(address(underlying));
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });
    IdleCreditVaultFactory.CreditVaultParams memory cvParams = _makeRevolvingCreditVaultParams();
    cvParams.fees = 4999;
    cvParams.managementFee = 199;

    address strategyImplementation = address(new IdleCreditVault());
    address cdoImplementation = address(new IdleCDOEpochVariant());
    address programmableBorrowerImplementation = address(new ProgrammableBorrower());

    vm.prank(creator);
    vm.expectRevert(FEES_TOO_LOW);
    cvParams.implementation = cdoImplementation;
    cvParams.underlying = address(underlying);
    factory.deployRevolvingCreditVault(
      cvParams,
      _makeStrategyData(strategyImplementation, address(underlying), address(factory), "Revolver", 12e18),
      IdleCreditVaultFactory.ProgrammableBorrowerParams({
        implementation: programmableBorrowerImplementation,
        vault: address(vault),
        borrower: realBorrower,
        borrowerApr: 365e18
      }),
      ancillaryParams
    );
  }

  function testDeployRevolvingCreditVaultRevertsWithWriteOffEscrow() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryVault vault = new MockFactoryVault(address(underlying));
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(new IdleCreditVaultWriteOffEscrow())
    });
    address strategyImplementation = address(new IdleCreditVault());
    address cdoImplementation = address(new IdleCDOEpochVariant());
    address programmableBorrowerImplementation = address(new ProgrammableBorrower());

    vm.prank(creator);
    vm.expectRevert(WRITE_OFF_UNSUPPORTED);
    IdleCreditVaultFactory.CreditVaultParams memory cvParams = _makeRevolvingCreditVaultParams();
    cvParams.implementation = cdoImplementation;
    cvParams.underlying = address(underlying);
    factory.deployRevolvingCreditVault(
      cvParams,
      _makeStrategyData(strategyImplementation, address(underlying), address(factory), "Revolver", 12e18),
      IdleCreditVaultFactory.ProgrammableBorrowerParams({
        implementation: programmableBorrowerImplementation,
        vault: address(vault),
        borrower: realBorrower,
        borrowerApr: 365e18
      }),
      ancillaryParams
    );
  }

  function testWriteOffEscrowFeeReceiverCanBeUpdatedByOwner() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    MockFactoryKeyring keyring = new MockFactoryKeyring();
    IdleCreditVaultFactory factory = _deployFactory();
    AncillaryDeployment memory deployment =
      _deployCreditVaultWithAncillaries(factory, underlying, address(keyring));
    IdleCreditVaultWriteOffEscrow writeOffEscrow = IdleCreditVaultWriteOffEscrow(deployment.writeOffEscrow);
    address newFeeReceiver = makeAddr("newWriteOffFeeReceiver");

    vm.prank(creator);
    vm.expectRevert(NOT_ALLOWED);
    writeOffEscrow.setFeeReceiver(newFeeReceiver);

    vm.prank(owner);
    vm.expectRevert(IS_0);
    writeOffEscrow.setFeeReceiver(address(0));

    vm.prank(owner);
    writeOffEscrow.setFeeReceiver(newFeeReceiver);

    assertEq(writeOffEscrow.feeReceiver(), newFeeReceiver, "write-off fee receiver");
  }

  function _findDeployment(Vm.Log[] memory entries) internal pure returns (AncillaryDeployment memory deployment) {
    for (uint256 i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == CREDIT_VAULT_DEPLOYED) {
        (
          deployment.cv,
          deployment.strategy,
          deployment.queue,
          deployment.programmableBorrower,
          deployment.keyringWhitelist,
          deployment.writeOffEscrow
        ) = abi.decode(entries[i].data, (address, address, address, address, address, address));
        return deployment;
      }
    }
    revert("deployment event not found");
  }

  function _countEvent(Vm.Log[] memory entries, bytes32 eventSignature) internal pure returns (uint256 count) {
    for (uint256 i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == eventSignature) {
        count += 1;
      }
    }
  }

  function _assertProxyAdmin(address proxy) internal view {
    assertEq(address(uint160(uint256(vm.load(proxy, EIP1967_ADMIN_SLOT)))), proxyAdmin, "proxy admin");
  }

  /// @notice Deploy a factory with unlimited admin allowances, then grant the test creator two deployments.
  function _deployFactory() internal returns (IdleCreditVaultFactory factory) {
    IdleCreditVaultFactory factoryImplementation = new IdleCreditVaultFactory();
    factory = IdleCreditVaultFactory(address(new TransparentUpgradeableProxy(
      address(factoryImplementation),
      factoryProxyAdmin,
      abi.encodeWithSelector(IdleCreditVaultFactory.initialize.selector, owner, proxyAdmin)
    )));
    assertEq(factory.proxyAdmin(), proxyAdmin, "factory proxy admin");
    assertEq(factory.MIN_PERFORMANCE_FEE(), 5000, "default performance minimum");
    assertEq(factory.MIN_MANAGEMENT_FEE(), 200, "default management minimum");
    assertFalse(factory.whitelist(creator), "creator initially unlisted");
    assertTrue(factory.whitelist(owner), "treasury initially whitelisted");
    assertTrue(factory.whitelist(factory.DEPLOYER()), "deployer initially whitelisted");
    assertEq(factory.remainingDeployments(owner), type(uint256).max, "treasury unlimited");
    assertEq(factory.remainingDeployments(factory.DEPLOYER()), type(uint256).max, "deployer unlimited");
    _setDeploymentAllowance(factory, owner, creator, 2);
  }

  function _deployRevolvingCreditVault(
    IdleCreditVaultFactory factory,
    MockFactoryERC20 underlying,
    MockFactoryVault vault
  ) internal returns (address cvProxy, address strategyProxy, address programmableBorrowerProxy) {
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: address(0),
      queueImplementation: address(0),
      prefundedDepositWindow: 0,
      writeOffImplementation: address(0)
    });
    AncillaryDeployment memory deployment =
      _deployRevolvingCreditVaultWithAncillary(factory, underlying, vault, ancillaryParams);
    cvProxy = deployment.cv;
    strategyProxy = deployment.strategy;
    programmableBorrowerProxy = deployment.programmableBorrower;
  }

  function _deployRevolvingCreditVaultWithAncillary(
    IdleCreditVaultFactory factory,
    MockFactoryERC20 underlying,
    MockFactoryVault vault,
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams
  ) internal returns (AncillaryDeployment memory deployment) {
    address strategyImplementation = address(new IdleCreditVault());
    address cdoImplementation = address(new IdleCDOEpochVariant());
    address programmableBorrowerImplementation = address(new ProgrammableBorrower());

    vm.recordLogs();
    vm.prank(creator);
    IdleCreditVaultFactory.CreditVaultParams memory cvParams = _makeRevolvingCreditVaultParams();
    cvParams.implementation = cdoImplementation;
    cvParams.underlying = address(underlying);
    factory.deployRevolvingCreditVault(
      cvParams,
      _makeStrategyData(strategyImplementation, address(underlying), address(factory), "Revolver", 12e18),
      IdleCreditVaultFactory.ProgrammableBorrowerParams({
        implementation: programmableBorrowerImplementation,
        vault: address(vault),
        borrower: realBorrower,
        borrowerApr: 365e18
      }),
      ancillaryParams
    );
    Vm.Log[] memory entries = vm.getRecordedLogs();
    deployment = _findDeployment(entries);
    assertEq(_countEvent(entries, CREDIT_VAULT_DEPLOYED), 1, "single deployment event");
    assertEq(deployment.writeOffEscrow, address(0), "revolving write-off unsupported");
  }

  function _deployCreditVaultWithAncillaries(
    IdleCreditVaultFactory factory,
    MockFactoryERC20 underlying,
    address keyring
  ) internal returns (AncillaryDeployment memory deployment) {
    IdleCDOEpochVariantPrefunded cdoImplementation = new IdleCDOEpochVariantPrefunded();
    IdleCDOEpochQueue queueImplementation = new IdleCDOEpochQueue();
    IdleCreditVaultWriteOffEscrow writeOffImplementation = new IdleCreditVaultWriteOffEscrow();

    IdleCreditVaultFactory.CreditVaultParams memory cvParams = IdleCreditVaultFactory.CreditVaultParams({
      implementation: address(cdoImplementation),
      limit: 0,
      underlying: address(underlying),
      apr: 12e18,
      epochDuration: 7 days,
      bufferPeriod: 1 days,
      instantWithdrawDelay: 1 hours,
      instantWithdrawAprDelta: 1e18,
      disableInstantWithdraw: true,
      keyringPolicy: 42,
      feeReceiver: creatorFeeReceiver,
      fees: 5000,
      managementFee: 500,
      isInterestMinted: false,
      isDepositDuringEpochDisabled: false
    });
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams = IdleCreditVaultFactory.AncillaryParams({
      keyring: keyring,
      queueImplementation: address(queueImplementation),
      prefundedDepositWindow: 2 days,
      writeOffImplementation: address(writeOffImplementation)
    });

    deployment = _deployCreditVaultWithConfig(
      factory,
      underlying,
      address(cdoImplementation),
      cvParams,
      ancillaryParams
    );
  }

  function _deployCreditVaultWithConfig(
    IdleCreditVaultFactory factory,
    MockFactoryERC20 underlying,
    address cdoImplementation,
    IdleCreditVaultFactory.CreditVaultParams memory cvParams,
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams
  ) internal returns (AncillaryDeployment memory deployment) {
    IdleCreditVault strategyImplementation = new IdleCreditVault();
    cvParams.implementation = cdoImplementation;
    cvParams.limit = 0;
    cvParams.underlying = address(underlying);
    IdleCreditVaultFactory.StrategyData memory strategyData =
      _makeStrategyData(address(strategyImplementation), address(underlying), address(factory), "Standard", 12e18);

    vm.recordLogs();
    vm.prank(creator);
    factory.deployCreditVault(
      cvParams,
      strategyData,
      ancillaryParams
    );
    Vm.Log[] memory entries = vm.getRecordedLogs();
    deployment = _findDeployment(entries);
    assertEq(_countEvent(entries, CREDIT_VAULT_DEPLOYED), 1, "single deployment event");
  }

  function _makeCreditVaultParams(
    address feeReceiver
  ) internal pure returns (IdleCreditVaultFactory.CreditVaultParams memory) {
    return IdleCreditVaultFactory.CreditVaultParams({
      implementation: address(0),
      limit: 0,
      underlying: address(0),
      apr: 12e18,
      epochDuration: 7 days,
      bufferPeriod: 1 days,
      instantWithdrawDelay: 1 hours,
      instantWithdrawAprDelta: 1e18,
      disableInstantWithdraw: true,
      keyringPolicy: 42,
      feeReceiver: feeReceiver,
      fees: 5000,
      managementFee: 500,
      isInterestMinted: false,
      isDepositDuringEpochDisabled: false
    });
  }

  function _makeRevolvingCreditVaultParams() internal view returns (IdleCreditVaultFactory.CreditVaultParams memory) {
    return IdleCreditVaultFactory.CreditVaultParams({
      implementation: address(0),
      limit: 0,
      underlying: address(0),
      apr: 12e18,
      epochDuration: 7 days,
      bufferPeriod: 1 days,
      instantWithdrawDelay: 1 hours,
      instantWithdrawAprDelta: 1e18,
      disableInstantWithdraw: false,
      keyringPolicy: 0,
      feeReceiver: creatorFeeReceiver,
      fees: 5000,
      managementFee: 0,
      isInterestMinted: false,
      isDepositDuringEpochDisabled: true
    });
  }

  function _makeStrategyData(
    address implementation,
    address,
    address,
    string memory borrowerName,
    uint256
  ) internal view returns (IdleCreditVaultFactory.StrategyData memory) {
    return IdleCreditVaultFactory.StrategyData({
      implementation: implementation,
      manager: manager,
      borrower: realBorrower,
      borrowerName: borrowerName
    });
  }

  function _assertDeployment(
    address cvProxy,
    address strategyProxy,
    address programmableBorrowerProxy,
    address underlying,
    address vault
  ) internal view {
    IdleCDOEpochVariant cv = IdleCDOEpochVariant(cvProxy);
    IdleCreditVault strategy = IdleCreditVault(strategyProxy);
    ProgrammableBorrower programmableBorrower = ProgrammableBorrower(programmableBorrowerProxy);

    assertEq(cv.owner(), owner, "cdo owner");
    assertEq(strategy.owner(), owner, "strategy owner");
    assertEq(programmableBorrower.owner(), owner, "programmable borrower owner");
    _assertProxyAdmin(cvProxy);
    _assertProxyAdmin(strategyProxy);
    _assertProxyAdmin(programmableBorrowerProxy);
    assertEq(strategy.manager(), manager, "strategy manager");
    assertEq(strategy.idleCDO(), cvProxy, "strategy cdo");
    assertEq(strategy.borrower(), programmableBorrowerProxy, "strategy borrower");
    assertEq(strategy.unscaledApr(), 0, "strategy apr should be zero");
    assertEq(strategy.getApr(), 0, "scaled strategy apr should be zero");
    assertEq(cv.isInterestMinted(), true, "minted interest should be forced on");
    assertEq(cv.isProgrammableBorrower(), true, "programmable mode should be enabled");
    assertEq(cv.disableInstantWithdraw(), true, "instant withdraw should be disabled");
    assertEq(cv.isDepositDuringEpochDisabled(), true, "deposit during epoch should be disabled");
    assertEq(_cdoAddress(address(cv), CDO_SLOT_GOVERNANCE_RECOVERY_FUND), owner, "governance fund");
    assertEq(_cdoAddress(address(cv), CDO_SLOT_GUARDIAN), manager, "guardian");
    assertEq(cv.trancheAPRSplitRatio(), 100000, "AA-only APR split");
    assertFalse(cv.isBBDepositEnabled(), "BB deposits enabled by default");
    assertEq(cv.feeReceiver(), creatorFeeReceiver, "fee receiver");
    assertEq(cv.fee(), 5000, "fee value");
    assertEq(cv.feeSplit(), DEFAULT_FACTORY_FEE_SPLIT, "fee split");
    assertEq(cv.managementFee(), 0, "management fee");
    assertEq(address(programmableBorrower.underlyingToken()), underlying, "underlying token");
    assertEq(address(programmableBorrower.vault()), vault, "vault");
    assertEq(programmableBorrower.idleCDO(), cvProxy, "programmable borrower cdo");
    assertEq(programmableBorrower.manager(), manager, "programmable borrower manager");
    assertEq(programmableBorrower.borrower(), realBorrower, "real borrower");
    assertEq(programmableBorrower.borrowerApr(), 365e18, "borrower apr");
  }

  /// @notice Standard and revolving deployments each charge the same unlisted wallet one fee.
  function testFactoryChargesEachPaidDeployment() external {
    vm.createSelectFork("mainnet", 26290277);
    IdleCreditVaultFactory factory = _upgradeFactoryForFeeTest(0xd6C6f31091Bf6E4a6a48C91cfA4C341f1BaB44ff);
    IERC20 usdc = MAINNET_FEE_USDC;
    address recipient = MAINNET_FEE_TREASURY;
    assertEq(factory.treasury(), recipient);
    assertEq(address(factory.deploymentFeeToken()), address(usdc));
    vm.prank(recipient);
    factory.setDeploymentFee(DEPLOYMENT_FEE);

    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(usdc);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory borrowerParams = _mainnetRevolvingBorrowerParams();

    deal(address(usdc), feePayer, 2 * DEPLOYMENT_FEE, true);
    uint256 treasuryBalance = usdc.balanceOf(recipient);
    uint256 factoryBalance = usdc.balanceOf(address(factory));
    vm.startPrank(feePayer);
    usdc.approve(address(factory), DEPLOYMENT_FEE);
    vm.recordLogs();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    address standardVault = _assertRecordedVaultDeployment().cv;
    assertEq(usdc.balanceOf(feePayer), DEPLOYMENT_FEE);
    assertEq(usdc.balanceOf(recipient), treasuryBalance + DEPLOYMENT_FEE);
    assertEq(usdc.allowance(feePayer, address(factory)), 0);

    vm.expectRevert();
    factory.deployRevolvingCreditVault(cvParams, strategyData, borrowerParams, ancillaryParams);
    assertEq(usdc.balanceOf(recipient), treasuryBalance + DEPLOYMENT_FEE);
    usdc.approve(address(factory), DEPLOYMENT_FEE);
    vm.recordLogs();
    factory.deployRevolvingCreditVault(cvParams, strategyData, borrowerParams, ancillaryParams);
    vm.stopPrank();
    AncillaryDeployment memory revolving = _assertRecordedVaultDeployment();
    assertTrue(revolving.cv != standardVault, "distinct vaults");
    assertGt(revolving.programmableBorrower.code.length, 0, "programmable borrower deployed");
    assertEq(ProgrammableBorrower(revolving.programmableBorrower).idleCDO(), revolving.cv);
    assertEq(usdc.balanceOf(feePayer), 0);
    assertEq(usdc.balanceOf(recipient), treasuryBalance + 2 * DEPLOYMENT_FEE);
    assertEq(usdc.balanceOf(address(factory)), factoryBalance);
    assertEq(usdc.allowance(feePayer, address(factory)), 0);
    assertFalse(factory.whitelist(feePayer));
    assertEq(factory.remainingDeployments(feePayer), 0);
  }

  /// @notice Base fees go to Base treasury, roll back on failure, and use the latest treasury quote.
  function testFactoryPaidDeploymentRollbackAndFeeChangeOnBase() external {
    vm.createSelectFork("base", 53194953);
    IdleCreditVaultFactory factory = _upgradeFactoryForFeeTest(0x4220714A44EAF70810AB8742a8875FAcEe2De004);
    IERC20 usdc = BASE_FEE_USDC;
    address recipient = BASE_FEE_TREASURY;
    assertEq(factory.treasury(), recipient);
    assertEq(address(factory.deploymentFeeToken()), address(usdc));
    vm.prank(recipient);
    factory.setDeploymentFee(DEPLOYMENT_FEE);

    uint256 updatedFee = DEPLOYMENT_FEE + 1_000e6;
    address protocolDeployer = factory.DEPLOYER();
    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasury.selector);
    vm.prank(protocolDeployer);
    factory.setDeploymentFee(updatedFee);
    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasury.selector);
    vm.prank(feePayer);
    factory.setDeploymentFee(updatedFee);
    assertEq(factory.deploymentFee(), DEPLOYMENT_FEE);

    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(usdc);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    uint256 treasuryBalance = usdc.balanceOf(recipient);
    deal(address(usdc), feePayer, DEPLOYMENT_FEE - 1, true);
    vm.startPrank(feePayer);
    usdc.approve(address(factory), DEPLOYMENT_FEE);
    vm.expectRevert();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();
    assertEq(usdc.balanceOf(feePayer), DEPLOYMENT_FEE - 1);
    assertEq(usdc.balanceOf(recipient), treasuryBalance);

    // The zero fee receiver reverts during vault configuration, after fee collection and proxy creation.
    deal(address(usdc), feePayer, DEPLOYMENT_FEE, true);
    cvParams.feeReceiver = address(0);
    vm.expectRevert(IdleCreditVaultFactory.Is0.selector);
    vm.prank(feePayer);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    assertEq(usdc.balanceOf(feePayer), DEPLOYMENT_FEE);
    assertEq(usdc.balanceOf(recipient), treasuryBalance);
    assertEq(usdc.allowance(feePayer, address(factory)), DEPLOYMENT_FEE);

    vm.prank(recipient);
    factory.setDeploymentFee(updatedFee);
    cvParams.feeReceiver = feePayer;
    deal(address(usdc), feePayer, updatedFee, true);
    vm.startPrank(feePayer);
    vm.expectRevert();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    usdc.approve(address(factory), updatedFee);
    vm.recordLogs();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();
    _assertRecordedVaultDeployment();
    assertEq(usdc.balanceOf(feePayer), 0);
    assertEq(usdc.balanceOf(recipient), treasuryBalance + updatedFee);
  }

  /// @notice Enabling paid access after a plain upgrade preserves the existing whitelist quota and fee exemption.
  function testFactoryPaidAccessPreservesWhitelistQuota() external {
    vm.createSelectFork("mainnet", 26290277);
    IdleCreditVaultFactory factory = _upgradeFactoryForFeeTest(0xd6C6f31091Bf6E4a6a48C91cfA4C341f1BaB44ff);
    address recipient = MAINNET_FEE_TREASURY;
    IERC20 usdc = MAINNET_FEE_USDC;
    assertEq(factory.deploymentFee(), 0);
    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(usdc);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    deal(address(usdc), feePayer, DEPLOYMENT_FEE, true);
    vm.startPrank(feePayer);
    usdc.approve(address(factory), DEPLOYMENT_FEE);
    vm.expectRevert(IdleCreditVaultFactory.NotWhitelisted.selector);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();

    vm.prank(recipient);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    _setDeploymentAllowance(factory, recipient, feePayer, 1);
    uint256 treasuryBalance = usdc.balanceOf(recipient);

    vm.startPrank(feePayer);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.expectRevert(IdleCreditVaultFactory.DeploymentLimitReached.selector);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();
    assertEq(factory.remainingDeployments(feePayer), 0);
    assertEq(usdc.balanceOf(feePayer), DEPLOYMENT_FEE);
    assertEq(usdc.allowance(feePayer, address(factory)), DEPLOYMENT_FEE);
    assertEq(usdc.balanceOf(recipient), treasuryBalance);

    vm.prank(recipient);
    factory.setDeploymentFee(0);
    assertEq(factory.deploymentFee(), 0);
  }

  /// @notice A paid deployment on Arbitrum One transfers native USDC to the registered treasury.
  function testArbitrumFactoryPaidDeployment() external {
    vm.createSelectFork("arbitrum");
    assertEq(block.chainid, 42161, "Arbitrum One fork");
    IdleCreditVaultFactory factory = _upgradeFactoryForFeeTest(0xbe73A30E9B9aE208Dfe615889bb4eff32a0e9208);
    IERC20 usdc = ARBITRUM_FEE_USDC;
    address recipient = ARBITRUM_FEE_TREASURY;
    assertEq(factory.treasury(), recipient);
    assertEq(address(factory.deploymentFeeToken()), address(usdc));
    assertFalse(factory.whitelist(feePayer));
    vm.prank(recipient);
    factory.setDeploymentFee(DEPLOYMENT_FEE);

    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(usdc);
    // Use the maximum valid performance fee so the live factory's configured floor cannot affect this test.
    cvParams.fees = 20_000;
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    deal(address(usdc), feePayer, 2 * DEPLOYMENT_FEE, true);
    uint256 treasuryBalance = usdc.balanceOf(recipient);
    uint256 factoryBalance = usdc.balanceOf(address(factory));

    vm.startPrank(feePayer);
    usdc.approve(address(factory), DEPLOYMENT_FEE);
    vm.recordLogs();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();

    _assertRecordedVaultDeployment();
    assertEq(usdc.balanceOf(feePayer), DEPLOYMENT_FEE);
    assertEq(usdc.balanceOf(recipient), treasuryBalance + DEPLOYMENT_FEE);
    assertEq(usdc.balanceOf(address(factory)), factoryBalance);
    assertEq(usdc.allowance(feePayer, address(factory)), 0);
  }

  /// @notice New factories charge 5,000 USDC on supported chains until treasury changes or disables the fee.
  function testNewFactoryDeploymentFee() external {
    uint256[3] memory chains = [uint256(1), 8453, 42161];
    for (uint256 i = 0; i < chains.length; i++) {
      vm.chainId(chains[i]);
      IdleCreditVaultFactory factory = _deployFactory();
      assertEq(factory.deploymentFee(), DEPLOYMENT_FEE);
      vm.prank(owner);
      factory.setDeploymentFee(0);
      _assertDeploymentNotWhitelisted(factory, feePayer);
    }
  }

  /// @notice Only pricing admins can set or clear custom terms. Clearing follows future default changes.
  function testWalletDeploymentFeeOverrides() external {
    vm.chainId(1);
    IdleCreditVaultFactory factory = _deployFactory();
    address deployer = factory.DEPLOYER();
    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    _setWalletFees(factory, feePayer, feePayer, 0, USE_DEFAULT);
    assertEq(factory.deploymentFeeFor(feePayer), DEPLOYMENT_FEE);

    _setWalletFees(factory, deployer, feePayer, CUSTOM_DEPLOYMENT_FEE, USE_DEFAULT);
    vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
    _setWalletFees(factory, feePayer, feePayer, USE_DEFAULT, USE_DEFAULT);
    assertEq(factory.deploymentFeeFor(feePayer), CUSTOM_DEPLOYMENT_FEE);
    assertEq(factory.deploymentFeeFor(manager), DEPLOYMENT_FEE);
    assertEq(factory.monthlySubscriptionFee(feePayer), DEFAULT_SUBSCRIPTION_FEE);

    vm.prank(owner);
    factory.setDeploymentFee(0);
    assertEq(factory.deploymentFeeFor(feePayer), 0);
    _assertDeploymentNotWhitelisted(factory, feePayer);
    vm.prank(owner);
    factory.setDeploymentFee(SUBSCRIPTION_FEE);
    assertEq(factory.deploymentFeeFor(feePayer), CUSTOM_DEPLOYMENT_FEE);
    _setWalletFees(factory, owner, feePayer, USE_DEFAULT, USE_DEFAULT);
    assertEq(factory.deploymentFeeFor(feePayer), SUBSCRIPTION_FEE);
    vm.prank(owner);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    assertEq(factory.deploymentFeeFor(feePayer), DEPLOYMENT_FEE);
  }

  /// @notice The highest custom price, a waiver, and the default round-trip distinctly through the batch API.
  function testWalletFeeEncoding() external {
    vm.chainId(1);
    IdleCreditVaultFactory factory = _deployFactory();
    uint256[3] memory prices = [USE_DEFAULT - 1, 0, USE_DEFAULT];
    for (uint256 i = 0; i < prices.length; i++) {
      uint256 price = prices[i];
      _setWalletFees(factory, owner, feePayer, price, price);
      IdleCreditVaultFactory.WalletFees memory terms = factory.walletFees(feePayer);
      assertEq(terms.deploymentFee, price);
      assertEq(terms.monthlyFee, price);
      assertEq(factory.deploymentFeeFor(feePayer), price == USE_DEFAULT ? DEPLOYMENT_FEE : price);
      assertEq(factory.monthlySubscriptionFee(feePayer), price == USE_DEFAULT ? DEFAULT_SUBSCRIPTION_FEE : price);
    }
  }

  /// @notice An unlisted wallet with a deployment waiver can deploy without USDC and still owes its subscription.
  function testWalletDeploymentFeeWaiver() external {
    IdleCreditVaultFactory factory = _upgradeMainnetFactoryForSubscriptionTest();
    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, 0, USE_DEFAULT);
    _assertDeploymentNotWhitelisted(factory, feePayer);
    vm.prank(MAINNET_FEE_TREASURY);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    assertEq(factory.deploymentFeeFor(feePayer), 0);
    assertFalse(factory.whitelist(feePayer));
    assertEq(MAINNET_FEE_USDC.allowance(feePayer, address(factory)), 0);
    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(MAINNET_FEE_USDC);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    uint256 treasuryBalance = MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY);
    vm.recordLogs();
    vm.prank(feePayer);
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    _assertRecordedVaultDeployment();
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance);
    assertTrue(factory.isSubscriptionDue(feePayer));
  }

  /// @notice An unsupported chain has no deployment fee token and rejects fee activation by treasury.
  function testFactoryRejectsPaidAccessOnUnsupportedNetwork() external {
    vm.chainId(31337);
    IdleCreditVaultFactory factory = _deployFactory();
    assertEq(address(factory.deploymentFeeToken()), address(0));
    vm.expectRevert(IdleCreditVaultFactory.UnsupportedDeploymentFeeNetwork.selector);
    vm.prank(owner);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    vm.expectRevert(IdleCreditVaultFactory.UnsupportedDeploymentFeeNetwork.selector);
    _setWalletFees(factory, owner, feePayer, CUSTOM_DEPLOYMENT_FEE, USE_DEFAULT);
    assertEq(factory.deploymentFee(), 0);
  }

  /// @notice Only treasury or the Pareto deployer override rates; unset wallets owe the 500 USDC default,
  /// while zero-override and whitelisted wallets are never due.
  function testSubscriptionRateAccessAndDueStatus() external {
    vm.chainId(1);
    vm.warp(100 days);
    IdleCreditVaultFactory factory = _deployFactory();
    address deployer = factory.DEPLOYER();
    address otherSubscriber = makeAddr("otherSubscriber");
    address zeroRateWallet = makeAddr("zeroRateWallet");
    address unsetRateWallet = makeAddr("unsetRateWallet");
    assertEq(factory.SUBSCRIPTION_PERIOD(), SUBSCRIPTION_MONTH, "30-day month");
    assertEq(factory.DEFAULT_MONTHLY_SUBSCRIPTION_FEE(), DEFAULT_SUBSCRIPTION_FEE, "500 USDC default");

    // Deployment permission alone does not allow a creator to set rates.
    address[2] memory unauthorized = [creator, manager];
    for (uint256 i = 0; i < unauthorized.length; i++) {
      vm.expectRevert(IdleCreditVaultFactory.OnlyTreasuryOrDeployer.selector);
      _setWalletFees(factory, unauthorized[i], feePayer, USE_DEFAULT, SUBSCRIPTION_FEE);
    }
    assertEq(factory.monthlySubscriptionFee(feePayer), DEFAULT_SUBSCRIPTION_FEE, "unauthorized override not set");
    assertEq(factory.walletFees(feePayer).monthlyFee, USE_DEFAULT, "no unauthorized override");

    // Set custom, default and waived fees independently for several wallets in the same transaction.
    address[] memory wallets = new address[](3);
    wallets[0] = feePayer;
    wallets[1] = otherSubscriber;
    wallets[2] = zeroRateWallet;
    IdleCreditVaultFactory.WalletFees[] memory fees = new IdleCreditVaultFactory.WalletFees[](3);
    fees[0] = IdleCreditVaultFactory.WalletFees(CUSTOM_DEPLOYMENT_FEE, SUBSCRIPTION_FEE);
    fees[1] = IdleCreditVaultFactory.WalletFees(USE_DEFAULT, OTHER_SUBSCRIPTION_FEE);
    fees[2] = IdleCreditVaultFactory.WalletFees(0, 0);
    vm.prank(owner);
    factory.setWalletFees(wallets, fees);
    assertEq(factory.USE_DEFAULT_FEE(), USE_DEFAULT);
    assertEq(factory.deploymentFeeFor(feePayer), CUSTOM_DEPLOYMENT_FEE);
    assertEq(factory.deploymentFeeFor(otherSubscriber), DEPLOYMENT_FEE);
    assertEq(factory.deploymentFeeFor(zeroRateWallet), 0);
    _setWalletFees(factory, deployer, creator, USE_DEFAULT, SUBSCRIPTION_FEE);

    assertEq(factory.monthlySubscriptionFee(feePayer), SUBSCRIPTION_FEE, "subscriber rate");
    assertEq(factory.monthlySubscriptionFee(otherSubscriber), OTHER_SUBSCRIPTION_FEE, "other rate");
    assertEq(factory.monthlySubscriptionFee(zeroRateWallet), 0, "explicit zero override");
    assertEq(factory.monthlySubscriptionFee(unsetRateWallet), DEFAULT_SUBSCRIPTION_FEE, "unset wallet owes the default");
    assertEq(factory.monthlySubscriptionFee(creator), SUBSCRIPTION_FEE, "deployer-set rate");
    assertEq(factory.walletFees(zeroRateWallet).monthlyFee, 0, "zero override recorded");
    assertEq(factory.walletFees(unsetRateWallet).monthlyFee, USE_DEFAULT, "unset wallet has no override");

    assertTrue(factory.isSubscriptionDue(feePayer), "never-paid subscriber due");
    assertTrue(factory.isSubscriptionDue(otherSubscriber), "never-paid other subscriber due");
    assertTrue(factory.isSubscriptionDue(unsetRateWallet), "unset wallet due at the default");
    assertFalse(factory.isSubscriptionDue(zeroRateWallet), "zero override never due");
    assertFalse(factory.isSubscriptionDue(creator), "whitelisted creator exempt despite a rate");
    assertFalse(factory.isSubscriptionDue(owner), "treasury exempt");
    assertEq(factory.subscriptionPaidUntil(feePayer), 0, "never paid");

    // A zero override has nothing to collect.
    vm.expectRevert(IdleCreditVaultFactory.Is0.selector);
    vm.prank(zeroRateWallet);
    factory.paySubscription(1);

    // The admin can exempt a previously unset wallet by overriding it to zero.
    _setWalletFees(factory, deployer, unsetRateWallet, USE_DEFAULT, 0);
    assertEq(factory.monthlySubscriptionFee(unsetRateWallet), 0, "unset wallet overridden to zero");
    assertFalse(factory.isSubscriptionDue(unsetRateWallet), "exempted wallet not due");
    vm.expectRevert(IdleCreditVaultFactory.Is0.selector);
    vm.prank(unsetRateWallet);
    factory.paySubscription(1);

    // A whitelisted payment returns early: USDC has no code on this local chain, so any transfer attempt would revert.
    vm.prank(creator);
    factory.paySubscription(1);
    assertEq(factory.subscriptionPaidUntil(creator), 0, "whitelisted payment grants no expiry");

    // Revoking the whitelist makes the preserved rate apply; a zero rate clears the prompt.
    _setDeploymentAllowance(factory, deployer, creator, 0);
    assertEq(factory.monthlySubscriptionFee(creator), SUBSCRIPTION_FEE, "rate preserved after delisting");
    assertTrue(factory.isSubscriptionDue(creator), "delisted creator due");
    _setWalletFees(factory, owner, feePayer, USE_DEFAULT, 0);
    assertFalse(factory.isSubscriptionDue(feePayer), "rate reset to zero");
  }

  /// @notice Without a fee token, subscriptions read as zero: the default does not apply and nonzero overrides revert.
  function testSubscriptionRatesRequireSupportedNetwork() external {
    vm.chainId(31337);
    IdleCreditVaultFactory factory = _deployFactory();
    assertEq(factory.monthlySubscriptionFee(feePayer), 0, "no default without a fee token");
    assertFalse(factory.isSubscriptionDue(feePayer), "nothing due without a fee token");
    vm.expectRevert(IdleCreditVaultFactory.UnsupportedDeploymentFeeNetwork.selector);
    _setWalletFees(factory, owner, feePayer, USE_DEFAULT, SUBSCRIPTION_FEE);
    _setWalletFees(factory, owner, feePayer, USE_DEFAULT, 0);
    assertEq(factory.walletFees(feePayer).monthlyFee, 0, "zero override recorded");
    assertEq(factory.monthlySubscriptionFee(feePayer), 0);
    assertFalse(factory.isSubscriptionDue(feePayer));
  }

  /// @notice A rejected entry leaves both fee settings of every earlier wallet in the batch untouched.
  function testWalletFeeBatchRollbackOnUnsupportedNetwork() external {
    vm.chainId(31337);
    IdleCreditVaultFactory factory = _deployFactory();
    address[] memory wallets = new address[](2);
    wallets[0] = feePayer;
    wallets[1] = manager;
    IdleCreditVaultFactory.WalletFees[] memory fees = new IdleCreditVaultFactory.WalletFees[](2);
    fees[0] = IdleCreditVaultFactory.WalletFees(0, 0);
    fees[1] = IdleCreditVaultFactory.WalletFees(USE_DEFAULT, SUBSCRIPTION_FEE);
    vm.expectRevert(IdleCreditVaultFactory.LengthMismatch.selector);
    vm.prank(owner);
    factory.setWalletFees(wallets, new IdleCreditVaultFactory.WalletFees[](1));
    vm.expectRevert(IdleCreditVaultFactory.UnsupportedDeploymentFeeNetwork.selector);
    vm.prank(owner);
    factory.setWalletFees(wallets, fees);
    IdleCreditVaultFactory.WalletFees memory terms = factory.walletFees(feePayer);
    assertEq(terms.deploymentFee, USE_DEFAULT);
    assertEq(terms.monthlyFee, USE_DEFAULT);
  }

  /// @notice Resetting both prices after a real subscription payment preserves the purchased period.
  function testResetWalletFeesPreservesPaidPeriod() external {
    IdleCreditVaultFactory factory = _upgradeMainnetFactoryForSubscriptionTest();
    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, 0, SUBSCRIPTION_FEE);
    deal(address(MAINNET_FEE_USDC), feePayer, SUBSCRIPTION_FEE, true);
    vm.startPrank(feePayer);
    MAINNET_FEE_USDC.approve(address(factory), SUBSCRIPTION_FEE);
    factory.paySubscription(1);
    vm.stopPrank();

    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, USE_DEFAULT, USE_DEFAULT);
    IdleCreditVaultFactory.WalletFees memory terms = factory.walletFees(feePayer);
    assertEq(terms.deploymentFee, USE_DEFAULT);
    assertEq(terms.monthlyFee, USE_DEFAULT);
    assertEq(factory.monthlySubscriptionFee(feePayer), DEFAULT_SUBSCRIPTION_FEE);
    assertEq(factory.subscriptionPaidUntil(feePayer), block.timestamp + SUBSCRIPTION_MONTH);
    assertFalse(factory.isSubscriptionDue(feePayer));
  }

  /// @notice First payment, renewal before expiry and renewal after expiry charge the rate and set the expected expiry.
  function testSubscriptionPaymentsChargeRateAndExtendExpiry() external {
    IdleCreditVaultFactory factory = _upgradeMainnetFactoryForSubscriptionTest();
    address otherSubscriber = makeAddr("otherSubscriber");
    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, USE_DEFAULT, SUBSCRIPTION_FEE);
    _setWalletFees(factory, factory.DEPLOYER(), otherSubscriber, USE_DEFAULT, OTHER_SUBSCRIPTION_FEE);
    deal(address(MAINNET_FEE_USDC), feePayer, 10 * SUBSCRIPTION_FEE, true);
    deal(address(MAINNET_FEE_USDC), otherSubscriber, OTHER_SUBSCRIPTION_FEE, true);
    uint256 treasuryBalance = MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY);
    uint256 start = block.timestamp;

    vm.startPrank(feePayer);
    MAINNET_FEE_USDC.approve(address(factory), type(uint256).max);
    vm.expectRevert(IdleCreditVaultFactory.Is0.selector);
    factory.paySubscription(0);

    // First payment covers two months from now.
    vm.expectEmit(true, true, true, true);
    emit SubscriptionPaid(feePayer, 2, 2 * SUBSCRIPTION_FEE, start + 2 * SUBSCRIPTION_MONTH);
    factory.paySubscription(2);
    assertEq(factory.subscriptionPaidUntil(feePayer), start + 2 * SUBSCRIPTION_MONTH, "first expiry");
    assertFalse(factory.isSubscriptionDue(feePayer), "paid");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + 2 * SUBSCRIPTION_FEE, "first charge");

    // Renewal before expiry stacks on the current expiry, not on the payment time.
    vm.warp(start + 10 days);
    factory.paySubscription(1);
    assertEq(factory.subscriptionPaidUntil(feePayer), start + 3 * SUBSCRIPTION_MONTH, "early renewal expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + 3 * SUBSCRIPTION_FEE, "early renewal charge");

    // The subscription is due once the paid-through timestamp is reached.
    vm.warp(start + 3 * SUBSCRIPTION_MONTH - 1);
    assertFalse(factory.isSubscriptionDue(feePayer), "active until expiry");
    vm.warp(start + 3 * SUBSCRIPTION_MONTH);
    assertTrue(factory.isSubscriptionDue(feePayer), "due at expiry");

    // Renewal after expiry restarts from the payment time; the lapsed gap is not charged.
    vm.warp(start + 100 days);
    factory.paySubscription(3);
    vm.stopPrank();
    assertEq(factory.subscriptionPaidUntil(feePayer), start + 100 days + 3 * SUBSCRIPTION_MONTH, "late renewal expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(feePayer), 4 * SUBSCRIPTION_FEE, "subscriber paid six months");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + 6 * SUBSCRIPTION_FEE, "late renewal charge");
    assertEq(MAINNET_FEE_USDC.balanceOf(address(factory)), 0, "factory holds no USDC");

    // Another wallet pays its own rate.
    vm.startPrank(otherSubscriber);
    MAINNET_FEE_USDC.approve(address(factory), OTHER_SUBSCRIPTION_FEE);
    factory.paySubscription(1);
    vm.stopPrank();
    assertEq(factory.subscriptionPaidUntil(otherSubscriber), block.timestamp + SUBSCRIPTION_MONTH, "other expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(otherSubscriber), 0, "other rate charged");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + 6 * SUBSCRIPTION_FEE + OTHER_SUBSCRIPTION_FEE);

    // A wallet without an override pays the 500 USDC default.
    address defaultSubscriber = makeAddr("defaultSubscriber");
    assertTrue(factory.isSubscriptionDue(defaultSubscriber), "default subscriber due");
    deal(address(MAINNET_FEE_USDC), defaultSubscriber, 2 * DEFAULT_SUBSCRIPTION_FEE, true);
    vm.startPrank(defaultSubscriber);
    MAINNET_FEE_USDC.approve(address(factory), 2 * DEFAULT_SUBSCRIPTION_FEE);
    factory.paySubscription(2);
    vm.stopPrank();
    assertEq(factory.subscriptionPaidUntil(defaultSubscriber), block.timestamp + 2 * SUBSCRIPTION_MONTH, "default expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(defaultSubscriber), 0, "default rate charged");
    assertEq(
      MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY),
      treasuryBalance + 6 * SUBSCRIPTION_FEE + OTHER_SUBSCRIPTION_FEE + 2 * DEFAULT_SUBSCRIPTION_FEE,
      "treasury received default payment"
    );

    // A rate change applies only to future payments, and a failed transfer leaves the expiry unchanged.
    uint256 paidUntil = factory.subscriptionPaidUntil(feePayer);
    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, USE_DEFAULT, OTHER_SUBSCRIPTION_FEE);
    assertEq(factory.subscriptionPaidUntil(feePayer), paidUntil, "paid period unchanged");
    vm.expectRevert();
    vm.prank(feePayer);
    factory.paySubscription(2);
    assertEq(factory.subscriptionPaidUntil(feePayer), paidUntil, "failed payment rolled back");
    assertEq(MAINNET_FEE_USDC.balanceOf(feePayer), 4 * SUBSCRIPTION_FEE, "failed payment kept funds");
    vm.prank(feePayer);
    factory.paySubscription(1);
    assertEq(factory.subscriptionPaidUntil(feePayer), paidUntil + SUBSCRIPTION_MONTH, "new rate renewal");
    assertEq(MAINNET_FEE_USDC.balanceOf(feePayer), 4 * SUBSCRIPTION_FEE - OTHER_SUBSCRIPTION_FEE, "new rate charged");
  }

  /// @notice A wallet overridden to zero still pays the deployment fee, and subscription status does not gate deployment.
  function testZeroRateWalletPaysDeploymentFeeWithoutSubscription() external {
    IdleCreditVaultFactory factory = _upgradeMainnetFactoryForSubscriptionTest();
    address zeroRateWallet = makeAddr("zeroRateWallet");
    vm.prank(MAINNET_FEE_TREASURY);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    assertTrue(factory.isSubscriptionDue(zeroRateWallet), "unset wallet owes the default");
    _setWalletFees(factory, MAINNET_FEE_TREASURY, zeroRateWallet, USE_DEFAULT, 0);
    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, USE_DEFAULT, SUBSCRIPTION_FEE);
    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(MAINNET_FEE_USDC);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    uint256 treasuryBalance = MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY);

    deal(address(MAINNET_FEE_USDC), zeroRateWallet, DEPLOYMENT_FEE, true);
    vm.startPrank(zeroRateWallet);
    MAINNET_FEE_USDC.approve(address(factory), DEPLOYMENT_FEE);
    // The combined call has no subscription to collect and reverts before charging the deployment fee.
    vm.expectRevert(IdleCreditVaultFactory.Is0.selector);
    factory.deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, 1);
    vm.recordLogs();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();
    _assertRecordedVaultDeployment();
    assertEq(MAINNET_FEE_USDC.balanceOf(zeroRateWallet), 0, "deployment fee charged");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + DEPLOYMENT_FEE);
    assertFalse(factory.isSubscriptionDue(zeroRateWallet), "zero rate not due after deployment");
    assertEq(factory.subscriptionPaidUntil(zeroRateWallet), 0, "no subscription recorded");

    // An unpaid subscriber can still deploy by paying the fee; deployment leaves its subscription untouched.
    assertTrue(factory.isSubscriptionDue(feePayer), "subscriber due");
    deal(address(MAINNET_FEE_USDC), feePayer, DEPLOYMENT_FEE, true);
    vm.startPrank(feePayer);
    MAINNET_FEE_USDC.approve(address(factory), DEPLOYMENT_FEE);
    vm.recordLogs();
    factory.deployCreditVault(cvParams, strategyData, ancillaryParams);
    vm.stopPrank();
    _assertRecordedVaultDeployment();
    assertTrue(factory.isSubscriptionDue(feePayer), "still due after deployment");
    assertEq(factory.subscriptionPaidUntil(feePayer), 0, "deployment does not pay subscription");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + 2 * DEPLOYMENT_FEE);
  }

  /// @notice One call deploys a vault and collects the deployment fee plus the selected months, or reverts both.
  function testDeployWithSubscriptionCollectsBothPaymentsAtomically() external {
    IdleCreditVaultFactory factory = _upgradeMainnetFactoryForSubscriptionTest();
    vm.prank(MAINNET_FEE_TREASURY);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    _setWalletFees(factory, MAINNET_FEE_TREASURY, feePayer, CUSTOM_DEPLOYMENT_FEE, SUBSCRIPTION_FEE);
    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(MAINNET_FEE_USDC);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory borrowerParams = _mainnetRevolvingBorrowerParams();
    uint256 total = CUSTOM_DEPLOYMENT_FEE + 3 * SUBSCRIPTION_FEE;
    uint256 funded = total + CUSTOM_DEPLOYMENT_FEE + SUBSCRIPTION_FEE;
    uint256 treasuryBalance = MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY);
    deal(address(MAINNET_FEE_USDC), feePayer, funded, true);

    vm.startPrank(feePayer);
    // The subscription transfer succeeds, then the deployment fee exceeds the remaining allowance.
    MAINNET_FEE_USDC.approve(address(factory), 3 * SUBSCRIPTION_FEE);
    vm.expectRevert();
    factory.deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, 3);
    assertEq(factory.subscriptionPaidUntil(feePayer), 0, "subscription rolled back");
    assertEq(MAINNET_FEE_USDC.balanceOf(feePayer), funded, "funds restored");
    assertEq(MAINNET_FEE_USDC.allowance(feePayer, address(factory)), 3 * SUBSCRIPTION_FEE, "allowance restored");

    // A zero fee receiver reverts during vault configuration, after both payments were transferred.
    MAINNET_FEE_USDC.approve(address(factory), total);
    cvParams.feeReceiver = address(0);
    vm.expectRevert(IdleCreditVaultFactory.Is0.selector);
    factory.deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, 3);
    assertEq(factory.subscriptionPaidUntil(feePayer), 0, "subscription rolled back after setup failure");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance, "treasury unchanged");
    assertEq(MAINNET_FEE_USDC.allowance(feePayer, address(factory)), total, "allowance restored after setup failure");

    cvParams.feeReceiver = feePayer;
    uint256 start = block.timestamp;
    vm.recordLogs();
    factory.deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, 3);
    _assertRecordedVaultDeployment();
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + total, "deployment fee plus three months");
    assertEq(MAINNET_FEE_USDC.allowance(feePayer, address(factory)), 0, "exact approval consumed");
    assertEq(factory.subscriptionPaidUntil(feePayer), start + 3 * SUBSCRIPTION_MONTH, "three months paid");
    assertFalse(factory.isSubscriptionDue(feePayer), "subscription active");

    // The revolving combined call also reverts atomically when the deployment fee fails after the subscription.
    vm.warp(start + 10 days);
    MAINNET_FEE_USDC.approve(address(factory), SUBSCRIPTION_FEE);
    vm.expectRevert();
    factory.deployRevolvingCreditVaultWithSubscription(cvParams, strategyData, borrowerParams, ancillaryParams, 1);
    assertEq(factory.subscriptionPaidUntil(feePayer), start + 3 * SUBSCRIPTION_MONTH, "revolving failure keeps expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(feePayer), funded - total, "revolving failure keeps payer funds");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + total, "revolving failure keeps treasury");
    assertEq(MAINNET_FEE_USDC.allowance(feePayer, address(factory)), SUBSCRIPTION_FEE, "revolving failure keeps allowance");

    // With enough allowance, the revolving combined call renews from the current expiry.
    MAINNET_FEE_USDC.approve(address(factory), CUSTOM_DEPLOYMENT_FEE + SUBSCRIPTION_FEE);
    vm.recordLogs();
    factory.deployRevolvingCreditVaultWithSubscription(cvParams, strategyData, borrowerParams, ancillaryParams, 1);
    vm.stopPrank();
    AncillaryDeployment memory revolving = _assertRecordedVaultDeployment();
    assertEq(ProgrammableBorrower(revolving.programmableBorrower).idleCDO(), revolving.cv, "revolving vault wired");
    assertEq(factory.subscriptionPaidUntil(feePayer), start + 4 * SUBSCRIPTION_MONTH, "revolving renewal expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(feePayer), 0, "all payments charged");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + funded, "treasury received all payments");
    assertEq(MAINNET_FEE_USDC.balanceOf(address(factory)), 0, "factory holds no USDC");
  }

  /// @notice A whitelisted wallet with a rate pays nothing through any subscription path; finite quotas still decrement.
  function testWhitelistedWalletIsExemptFromSubscriptionPayments() external {
    IdleCreditVaultFactory factory = _upgradeMainnetFactoryForSubscriptionTest();
    vm.prank(MAINNET_FEE_TREASURY);
    factory.setDeploymentFee(DEPLOYMENT_FEE);
    _setWalletFees(factory, MAINNET_FEE_TREASURY, creator, CUSTOM_DEPLOYMENT_FEE, OTHER_SUBSCRIPTION_FEE);
    _setDeploymentAllowance(factory, MAINNET_FEE_TREASURY, creator, 2);
    assertEq(factory.deploymentFeeFor(creator), 0, "whitelist uses quota");
    (IdleCreditVaultFactory.CreditVaultParams memory cvParams, IdleCreditVaultFactory.StrategyData memory strategyData) =
      _factoryFeeTestParams(MAINNET_FEE_USDC);
    IdleCreditVaultFactory.AncillaryParams memory ancillaryParams;
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory borrowerParams = _mainnetRevolvingBorrowerParams();
    // Fund and approve enough for every fee so that any attempted charge would succeed and be visible.
    uint256 funds = 2 * OTHER_SUBSCRIPTION_FEE + DEPLOYMENT_FEE;
    deal(address(MAINNET_FEE_USDC), creator, funds, true);
    uint256 treasuryBalance = MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY);

    vm.startPrank(creator);
    MAINNET_FEE_USDC.approve(address(factory), type(uint256).max);
    factory.paySubscription(2);
    assertEq(factory.subscriptionPaidUntil(creator), 0, "standalone payment grants no expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(creator), funds, "standalone payment charges nothing");

    // Each combined call deploys by consuming one finite quota slot and charges no USDC.
    vm.recordLogs();
    factory.deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, 2);
    _assertRecordedVaultDeployment();
    assertEq(factory.remainingDeployments(creator), 1, "standard combined call uses quota");
    vm.recordLogs();
    factory.deployRevolvingCreditVaultWithSubscription(cvParams, strategyData, borrowerParams, ancillaryParams, 2);
    _assertRecordedVaultDeployment();
    assertEq(factory.remainingDeployments(creator), 0, "revolving combined call uses quota");

    // An exhausted quota blocks deployment but leaves the wallet whitelisted and its subscription exempt.
    vm.expectRevert(IdleCreditVaultFactory.DeploymentLimitReached.selector);
    factory.deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, 2);
    factory.paySubscription(2);
    vm.stopPrank();
    assertTrue(factory.whitelist(creator), "still whitelisted");
    assertFalse(factory.isSubscriptionDue(creator), "exhausted quota still exempt");
    assertEq(factory.subscriptionPaidUntil(creator), 0, "no expiry from any path");
    assertEq(MAINNET_FEE_USDC.balanceOf(creator), funds, "no USDC from any path");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance, "treasury unchanged");

    // Delisting applies the preserved rate.
    _setDeploymentAllowance(factory, MAINNET_FEE_TREASURY, creator, 0);
    assertEq(factory.monthlySubscriptionFee(creator), OTHER_SUBSCRIPTION_FEE, "rate preserved");
    assertTrue(factory.isSubscriptionDue(creator), "due after delisting");
    assertEq(factory.deploymentFeeFor(creator), CUSTOM_DEPLOYMENT_FEE, "deployment price after delisting");
    vm.prank(creator);
    factory.paySubscription(1);
    assertEq(factory.subscriptionPaidUntil(creator), block.timestamp + SUBSCRIPTION_MONTH, "delisted expiry");
    assertEq(MAINNET_FEE_USDC.balanceOf(MAINNET_FEE_TREASURY), treasuryBalance + OTHER_SUBSCRIPTION_FEE, "delisted wallet charged");
  }

  /// @dev Check that a successful call emitted exactly one deployment event for a vault with code.
  function _assertRecordedVaultDeployment() internal returns (AncillaryDeployment memory deployment) {
    Vm.Log[] memory entries = vm.getRecordedLogs();
    assertEq(_countEvent(entries, CREDIT_VAULT_DEPLOYED), 1, "single deployment event");
    deployment = _findDeployment(entries);
    assertGt(deployment.cv.code.length, 0, "vault deployed");
  }

  /// @dev Rehearse a plain upgrade via the live ProxyAdmin and check the freshly compiled factory runtime size.
  function _upgradeFactoryForFeeTest(address factoryAddress) internal returns (IdleCreditVaultFactory factory) {
    ProxyAdmin admin = ProxyAdmin(address(uint160(uint256(vm.load(factoryAddress, EIP1967_ADMIN_SLOT)))));
    address implementation = deployCode("IdleCreditVaultFactory.sol:IdleCreditVaultFactory");
    assertLt(implementation.code.length, 24_576, "factory EIP-170 runtime size");
    vm.prank(admin.owner());
    admin.upgrade(ITransparentUpgradeableProxy(factoryAddress), implementation);
    factory = IdleCreditVaultFactory(factoryAddress);
  }

  /// @dev Deploy real vault and strategy implementations to exercise the current factory's full configuration path.
  function _factoryFeeTestParams(IERC20 usdc) internal returns (
    IdleCreditVaultFactory.CreditVaultParams memory cvParams,
    IdleCreditVaultFactory.StrategyData memory strategyData
  ) {
    cvParams.implementation = deployCode("IdleCDOEpochVariant.sol:IdleCDOEpochVariant");
    cvParams.underlying = address(usdc);
    cvParams.epochDuration = 7 days;
    cvParams.bufferPeriod = 1 days;
    cvParams.feeReceiver = feePayer;
    cvParams.fees = 5_000;
    strategyData.implementation = deployCode("IdleCreditVault.sol:IdleCreditVault");
    strategyData.manager = makeAddr("factoryFeeTestManager");
    strategyData.borrower = makeAddr("factoryFeeTestBorrower");
    strategyData.borrowerName = "Factory Fee Test";
  }

  /// @dev Fork mainnet at the fee-test block and upgrade the production factory, which starts with the default
  /// rate for every wallet, no overrides and no paid periods.
  function _upgradeMainnetFactoryForSubscriptionTest() internal returns (IdleCreditVaultFactory factory) {
    vm.createSelectFork("mainnet", 26290277);
    factory = _upgradeFactoryForFeeTest(0xd6C6f31091Bf6E4a6a48C91cfA4C341f1BaB44ff);
    assertEq(factory.treasury(), MAINNET_FEE_TREASURY, "mainnet treasury");
    assertEq(factory.monthlySubscriptionFee(feePayer), DEFAULT_SUBSCRIPTION_FEE, "default rate after upgrade");
    IdleCreditVaultFactory.WalletFees memory terms = factory.walletFees(feePayer);
    assertEq(terms.deploymentFee, USE_DEFAULT, "no deployment override after upgrade");
    assertEq(terms.monthlyFee, USE_DEFAULT, "no subscription override after upgrade");
    assertEq(factory.subscriptionPaidUntil(feePayer), 0, "no expiry after upgrade");
    assertFalse(factory.whitelist(feePayer), "fee payer unlisted");
  }

  /// @dev Programmable borrower parameters backed by the live mainnet ERC-4626 vault used by the fee tests.
  function _mainnetRevolvingBorrowerParams() internal returns (IdleCreditVaultFactory.ProgrammableBorrowerParams memory) {
    return IdleCreditVaultFactory.ProgrammableBorrowerParams({
      implementation: deployCode("ProgrammableBorrower.sol:ProgrammableBorrower"),
      vault: 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB,
      borrower: makeAddr("revolvingFeeTestBorrower"),
      borrowerApr: 12e18
    });
  }
}
