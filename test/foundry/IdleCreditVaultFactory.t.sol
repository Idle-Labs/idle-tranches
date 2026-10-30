// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

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
  uint256 internal constant DEFAULT_FACTORY_FEE_SPLIT = 50000;
  uint256 internal constant CDO_SLOT_GOVERNANCE_RECOVERY_FUND = 202;
  uint256 internal constant CDO_SLOT_GUARDIAN = 208;

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
}
