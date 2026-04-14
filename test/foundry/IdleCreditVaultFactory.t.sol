// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IdleCreditVaultFactory} from "../../contracts/IdleCreditVaultFactory.sol";
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
  bytes4 internal constant CDO_INITIALIZE_SELECTOR =
    bytes4(keccak256("initialize(uint256,address,address,address,address,address,uint256)"));

  address internal owner = makeAddr("owner");
  address internal manager = makeAddr("manager");
  address internal rebalancer = makeAddr("rebalancer");
  address internal realBorrower = makeAddr("realBorrower");
  address internal proxyAdmin = makeAddr("proxyAdmin");
  address internal factoryProxyAdmin = makeAddr("factoryProxyAdmin");
  address internal guardian = makeAddr("guardian");
  address internal governanceFund = makeAddr("governanceFund");

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
    address idleCDOAddress = makeAddr("idleCDO");
    ProgrammableBorrower programmableBorrowerImplementation = new ProgrammableBorrower();
    ProgrammableBorrower programmableBorrower = ProgrammableBorrower(address(new TransparentUpgradeableProxy(
      address(programmableBorrowerImplementation),
      proxyAdmin,
      abi.encodeWithSelector(
        ProgrammableBorrower.initialize.selector,
        address(underlying),
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

  function _findProxy(Vm.Log[] memory entries, bytes32 eventSignature) internal pure returns (address deployed) {
    for (uint256 i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == eventSignature) {
        return abi.decode(entries[i].data, (address));
      }
    }
    revert("deployment event not found");
  }

  function _deployFactory() internal returns (IdleCreditVaultFactory factory) {
    IdleCreditVaultFactory factoryImplementation = new IdleCreditVaultFactory();
    factory = IdleCreditVaultFactory(address(new TransparentUpgradeableProxy(
      address(factoryImplementation),
      factoryProxyAdmin,
      abi.encodeWithSelector(IdleCreditVaultFactory.initialize.selector)
    )));
  }

  function _deployRevolvingCreditVault(
    IdleCreditVaultFactory factory,
    MockFactoryERC20 underlying,
    MockFactoryVault vault
  ) internal returns (address cvProxy, address strategyProxy, address programmableBorrowerProxy) {
    IdleCreditVault strategyImplementation = new IdleCreditVault();
    IdleCDOEpochVariant cdoImplementation = new IdleCDOEpochVariant();
    ProgrammableBorrower programmableBorrowerImplementation = new ProgrammableBorrower();

    IdleCreditVaultFactory.TransparentProxyData memory cvData = IdleCreditVaultFactory.TransparentProxyData({
      implementation: address(cdoImplementation),
      proxyAdmin: proxyAdmin,
      initializeData: abi.encodeWithSelector(
        CDO_INITIALIZE_SELECTOR,
        0,
        address(underlying),
        governanceFund,
        guardian,
        rebalancer,
        address(0),
        100000
      )
    });
    IdleCreditVaultFactory.TransparentProxyData memory strategyData = IdleCreditVaultFactory.TransparentProxyData({
      implementation: address(strategyImplementation),
      proxyAdmin: proxyAdmin,
      initializeData: abi.encodeWithSelector(
        IdleCreditVault.initialize.selector,
        address(underlying),
        address(factory),
        manager,
        realBorrower,
        "Revolver",
        12e18
      )
    });
    IdleCreditVaultFactory.CreditVaultParams memory cvParams = IdleCreditVaultFactory.CreditVaultParams({
      apr: 12e18,
      epochDuration: 7 days,
      bufferPeriod: 1 days,
      instantWithdrawDelay: 1 hours,
      instantWithdrawAprDelta: 1e18,
      disableInstantWithdraw: false,
      keyring: address(0),
      keyringPolicy: 0,
      keyringAllowWithdraw: false,
      fees: 10000,
      isInterestMinted: false,
      isDepositDuringEpochDisabled: true
    });
    IdleCreditVaultFactory.ProgrammableBorrowerProxyData memory programmableBorrowerData =
      IdleCreditVaultFactory.ProgrammableBorrowerProxyData({
        implementation: address(programmableBorrowerImplementation),
        proxyAdmin: proxyAdmin
      });
    IdleCreditVaultFactory.ProgrammableBorrowerParams memory programmableBorrowerParams =
      IdleCreditVaultFactory.ProgrammableBorrowerParams({
        underlyingToken: address(underlying),
        vault: address(vault),
        manager: manager,
        borrower: realBorrower,
        borrowerApr: 365e18
      });

    vm.recordLogs();
    factory.deployRevolvingCreditVault(
      cvData,
      strategyData,
      cvParams,
      programmableBorrowerData,
      programmableBorrowerParams,
      address(0),
      owner
    );
    Vm.Log[] memory entries = vm.getRecordedLogs();
    cvProxy = _findProxy(entries, keccak256("CreditVaultDeployed(address)"));
    strategyProxy = _findProxy(entries, keccak256("StrategyDeployed(address)"));
    programmableBorrowerProxy = _findProxy(entries, keccak256("ProgrammableBorrowerDeployed(address)"));
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
    assertEq(strategy.idleCDO(), cvProxy, "strategy cdo");
    assertEq(strategy.borrower(), programmableBorrowerProxy, "strategy borrower");
    assertEq(strategy.unscaledApr(), 0, "strategy apr should be zero");
    assertEq(strategy.getApr(), 0, "scaled strategy apr should be zero");
    assertEq(cv.isInterestMinted(), true, "minted interest should be forced on");
    assertEq(cv.isProgrammableBorrower(), true, "programmable mode should be enabled");
    assertEq(cv.disableInstantWithdraw(), true, "instant withdraw should be disabled");
    assertEq(cv.guardian(), guardian, "guardian");
    assertEq(cv.feeReceiver(), owner, "fee receiver");
    assertEq(cv.fee(), 10000, "fee value");
    assertEq(address(programmableBorrower.underlyingToken()), underlying, "underlying token");
    assertEq(address(programmableBorrower.vault()), vault, "vault");
    assertEq(programmableBorrower.idleCDO(), cvProxy, "programmable borrower cdo");
    assertEq(programmableBorrower.manager(), manager, "programmable borrower manager");
    assertEq(programmableBorrower.borrower(), realBorrower, "real borrower");
    assertEq(programmableBorrower.borrowerApr(), 365e18, "borrower apr");
  }
}
