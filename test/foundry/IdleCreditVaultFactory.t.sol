// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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
    assertEq(cv.governanceRecoveryFund(), owner, "cdo governance fund");
    assertEq(cv.guardian(), manager, "cdo guardian");
    assertEq(cv.trancheAPRSplitRatio(), 100000, "AA-only APR split");
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

  function testDeployCreditVaultWithoutOptionalContractsAndFeeReceiver() external {
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
    assertEq(cv.feeReceiver(), address(0), "fee receiver");
    assertEq(cv.feeSplit(), DEFAULT_FACTORY_FEE_SPLIT, "fee split retained");
    _assertProxyAdmin(deployment.cv);
    _assertProxyAdmin(deployment.strategy);
  }

  function testDeployCreditVaultRevertsWhenFeesAreBelowMinimums() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    IdleCreditVaultFactory.CreditVaultParams memory cvParams =
      _makeCreditVaultParams(creatorFeeReceiver);
    cvParams.fees = 4999;
    cvParams.managementFee = 499;
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
    cvParams.managementFee = 500;
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
    assertEq(cv.managementFee(), 500, "management fee");
  }

  function testTreasuryCanUpdateFactoryFeeSplit() external {
    vm.warp(100 days);

    MockFactoryERC20 underlying = new MockFactoryERC20("Mock USDC", "mUSDC", 6);
    IdleCreditVaultFactory factory = _deployFactory();
    assertEq(factory.feeSplit(), DEFAULT_FACTORY_FEE_SPLIT, "default fee split");

    vm.prank(creator);
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
    cvParams.managementFee = 499;

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

  function _deployFactory() internal returns (IdleCreditVaultFactory factory) {
    IdleCreditVaultFactory factoryImplementation = new IdleCreditVaultFactory();
    factory = IdleCreditVaultFactory(address(new TransparentUpgradeableProxy(
      address(factoryImplementation),
      factoryProxyAdmin,
      abi.encodeWithSelector(IdleCreditVaultFactory.initialize.selector, owner, proxyAdmin)
    )));
    assertEq(factory.proxyAdmin(), proxyAdmin, "factory proxy admin");
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
    assertEq(cv.governanceRecoveryFund(), owner, "governance fund");
    assertEq(cv.guardian(), manager, "guardian");
    assertEq(cv.trancheAPRSplitRatio(), 100000, "AA-only APR split");
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
