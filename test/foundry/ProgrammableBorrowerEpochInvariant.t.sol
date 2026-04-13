// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IdleCDOTranche} from "../../contracts/IdleCDOTranche.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {ProgrammableBorrower} from "../../contracts/strategies/idle/ProgrammableBorrower.sol";

/// @notice Mintable underlying token used by the epoch-level invariant harness.
contract MockEpochInvariantERC20 is ERC20 {
  constructor() ERC20("Mock USDC", "mUSDC") {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }
}

/// @notice Deterministic ERC4626-style vault used by the epoch-level invariant harness.
/// @dev The vault exposes explicit gain, loss, and withdraw-limit knobs so the handler can
/// exercise the `IdleCDOEpochVariant` programmable-borrower flow without relying on a fork.
contract MockEpochInvariantVault is ERC20 {
  MockEpochInvariantERC20 public immutable assetToken;
  uint256 public withdrawLimit = type(uint256).max;

  constructor(address _asset) ERC20("Epoch Invariant Vault Share", "EIVS") {
    assetToken = MockEpochInvariantERC20(_asset);
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
    uint256 maxAssets = convertToAssets(balanceOf(owner));
    return maxAssets < withdrawLimit ? maxAssets : withdrawLimit;
  }

  function addGain(uint256 assets) external {
    assetToken.mint(address(this), assets);
  }

  function applyLoss(uint256 assets) external {
    uint256 bal = assetToken.balanceOf(address(this));
    assetToken.burn(address(this), assets > bal ? bal : assets);
  }

  function setWithdrawLimit(uint256 assets) external {
    withdrawLimit = assets;
  }

  function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
    uint256 assetsBefore = totalAssets();
    uint256 supply = totalSupply();
    shares = supply == 0 || assetsBefore == 0 ? assets : assets * supply / assetsBefore;
    assetToken.transferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);
  }

  function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
    uint256 maxAssets = this.maxWithdraw(owner);
    require(assets <= maxAssets, "insufficient-liquidity");
    shares = _toSharesRoundUp(assets);
    if (msg.sender != owner) {
      _spendAllowance(owner, msg.sender, shares);
    }
    _burn(owner, shares);
    assetToken.transfer(receiver, assets);
  }

  function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
    assets = convertToAssets(shares);
    uint256 maxAssets = this.maxWithdraw(owner);
    require(assets <= maxAssets, "insufficient-liquidity");
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

/// @notice Stateful handler covering the small higher-level programmable-borrower epoch flow.
/// @dev This handler does not try to model the whole IdleCDO system. Instead it focuses on the
/// programmable-specific guarantees we care about at the orchestration layer:
/// - programmable mode never uses instant withdrawals
/// - start/stop keep epoch-accounting state in sync with the borrower
/// - successful stops source realized interest from the programmable borrower
/// - close-pool with outstanding principal defaults instead of silently succeeding
contract ProgrammableBorrowerEpochHandler is Test {
  IdleCDOEpochVariant public immutable cdoEpoch;
  IdleCreditVault public immutable strategy;
  ProgrammableBorrower public immutable programmableBorrower;
  MockEpochInvariantERC20 public immutable underlying;
  MockEpochInvariantVault public immutable vault;
  IdleCDOTranche public immutable aaTranche;

  address public immutable owner;
  address public immutable manager;
  address public immutable lp;
  address public immutable revolvingBorrower;

  bool public hasExpectedLastEpochInterest;
  uint256 public expectedLastEpochInterest;

  constructor(
    IdleCDOEpochVariant _cdoEpoch,
    IdleCreditVault _strategy,
    ProgrammableBorrower _programmableBorrower,
    MockEpochInvariantERC20 _underlying,
    MockEpochInvariantVault _vault,
    IdleCDOTranche _aaTranche,
    address _owner,
    address _manager,
    address _lp,
    address _revolvingBorrower
  ) {
    cdoEpoch = _cdoEpoch;
    strategy = _strategy;
    programmableBorrower = _programmableBorrower;
    underlying = _underlying;
    vault = _vault;
    aaTranche = _aaTranche;
    owner = _owner;
    manager = _manager;
    lp = _lp;
    revolvingBorrower = _revolvingBorrower;
  }

  /// @notice Deposit AA tranche liquidity while the pool is in the buffer state.
  function depositAA(uint256 amountSeed) external {
    if (cdoEpoch.defaulted() || cdoEpoch.isEpochRunning() || cdoEpoch.epochEndDate() == 0) {
      return;
    }

    uint256 balance = underlying.balanceOf(lp);
    if (balance == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, balance);
    vm.prank(lp);
    cdoEpoch.depositAA(amount);
  }

  /// @notice Request an AA withdrawal. In programmable mode this must stay on the normal path.
  function requestWithdraw(uint256 amountSeed) external {
    if (
      cdoEpoch.defaulted() ||
      cdoEpoch.isEpochRunning() ||
      cdoEpoch.epochEndDate() == 0 ||
      !cdoEpoch.allowAAWithdrawRequest()
    ) {
      return;
    }

    uint256 shares = aaTranche.balanceOf(lp);
    if (shares == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, shares);
    vm.prank(lp);
    cdoEpoch.requestWithdraw(amount, address(aaTranche));

    // Programmable mode must never route AA requests into the instant-withdraw bucket.
    assertEq(strategy.pendingInstantWithdraws(), 0, "instant withdraws should stay disabled");
    assertEq(strategy.instantWithdrawsRequests(lp), 0, "instant withdraw receipts should stay empty");
  }

  /// @notice Claim a matured normal withdrawal receipt to recycle capital through the harness.
  function claimWithdraw() external {
    if (strategy.lastWithdrawRequest(lp) == 0 || cdoEpoch.isEpochRunning()) {
      return;
    }

    if (cdoEpoch.epochEndDate() != 0 && strategy.epochNumber() <= strategy.lastWithdrawRequest(lp)) {
      return;
    }

    vm.prank(lp);
    cdoEpoch.claimWithdrawRequest();
  }

  /// @notice Start a new epoch once the buffer has elapsed.
  function startEpoch() external {
    if (
      cdoEpoch.defaulted() ||
      cdoEpoch.isEpochRunning() ||
      cdoEpoch.epochEndDate() == 0 ||
      block.timestamp < cdoEpoch.epochEndDate() + cdoEpoch.bufferPeriod()
    ) {
      return;
    }

    vm.prank(manager);
    cdoEpoch.startEpoch();

    assertTrue(programmableBorrower.epochAccountingActive(), "borrower accounting should start with the epoch");
  }

  /// @notice Advance time across buffer and epoch boundaries.
  function warp(uint256 elapsedSeed) external {
    uint256 elapsed = bound(elapsedSeed, 1, 40 days);
    vm.warp(block.timestamp + elapsed);
  }

  /// @notice Borrow a bounded amount from the programmable borrower while an epoch is running.
  function borrow(uint256 amountSeed) external {
    if (!cdoEpoch.isEpochRunning() || cdoEpoch.defaulted()) {
      return;
    }

    uint256 available = programmableBorrower.availableToBorrow();
    if (available == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, available);
    vm.prank(revolvingBorrower);
    programmableBorrower.borrow(amount);
  }

  /// @notice Repay a bounded amount back into the programmable borrower.
  function repay(uint256 amountSeed) external {
    uint256 totalOwed = programmableBorrower.borrowerPrincipal()
      + programmableBorrower.borrowerInterestOwedNow();
    uint256 balance = underlying.balanceOf(revolvingBorrower);
    if (totalOwed == 0 || balance == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, totalOwed < balance ? totalOwed : balance);
    vm.prank(revolvingBorrower);
    programmableBorrower.repay(amount);
  }

  /// @notice Add deterministic positive vault PnL while an epoch is active.
  function addVaultGain(uint256 amountSeed) external {
    if (!programmableBorrower.epochAccountingActive() || programmableBorrower.vaultSharesBalance() == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, 100_000e18);
    vault.addGain(amount);
  }

  /// @notice Apply deterministic vault losses while an epoch is active.
  function applyVaultLoss(uint256 amountSeed) external {
    if (!programmableBorrower.epochAccountingActive() || programmableBorrower.vaultSharesBalance() == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, vault.totalAssets());
    vault.applyLoss(amount);
  }

  /// @notice Cap or uncap withdrawable vault liquidity to exercise partial stop-epoch recalls.
  function setVaultWithdrawLimit(uint256 limitSeed, bool capLiquidity) external {
    uint256 currentAssets = vault.convertToAssets(programmableBorrower.vaultSharesBalance());
    vault.setWithdrawLimit(capLiquidity ? bound(limitSeed, 0, currentAssets) : type(uint256).max);
  }

  /// @notice Stop the running epoch in either normal or close-pool mode.
  function stopEpoch(bool closePool) external {
    if (!cdoEpoch.isEpochRunning() || cdoEpoch.defaulted() || block.timestamp < cdoEpoch.epochEndDate()) {
      return;
    }

    uint256 expectedInterest = programmableBorrower.totalInterestDueNow();
    uint256 debtBefore = programmableBorrower.borrowerInterestDebt();
    uint256 accruedBefore = programmableBorrower.borrowerInterestAccruedNow();
    uint256 principalBefore = programmableBorrower.borrowerPrincipal();

    vm.prank(manager);
    cdoEpoch.stopEpoch(0, closePool ? 1 : 0);

    if (cdoEpoch.defaulted()) {
      assertEq(
        programmableBorrower.borrowerInterestDebt(),
        debtBefore,
        "borrower debt should not settle on a defaulted stop"
      );
      return;
    }

    hasExpectedLastEpochInterest = true;
    expectedLastEpochInterest = expectedInterest;

    assertApproxEqAbs(cdoEpoch.lastEpochInterest(), expectedInterest, 2, "last epoch interest mismatch");
    assertFalse(programmableBorrower.epochAccountingActive(), "borrower accounting should stop with the epoch");

    if (closePool) {
      assertEq(principalBefore, 0, "close-pool stop should not succeed with outstanding principal");
      assertEq(cdoEpoch.epochEndDate(), 0, "successful close-pool stop should close the pool");
      return;
    }

    assertEq(
      programmableBorrower.borrowerInterestDebt(),
      debtBefore + accruedBefore,
      "normal stop should settle borrower interest debt"
    );
  }
}

/// @notice Stateful invariant suite for programmable-borrower epoch orchestration.
contract ProgrammableBorrowerEpochInvariant is StdInvariant, Test {
  using stdStorage for StdStorage;

  MockEpochInvariantERC20 internal underlying;
  MockEpochInvariantVault internal vault;
  IdleCDOEpochVariant internal cdoEpoch;
  IdleCreditVault internal strategy;
  ProgrammableBorrower internal programmableBorrower;
  IdleCDOTranche internal aaTranche;
  ProgrammableBorrowerEpochHandler internal handler;

  address internal owner = makeAddr("owner");
  address internal manager = makeAddr("manager");
  address internal rebalancer = makeAddr("rebalancer");
  address internal lp = makeAddr("lp");
  address internal revolvingBorrower = makeAddr("revolvingBorrower");

  function setUp() public {
    vm.warp(100 days);

    underlying = new MockEpochInvariantERC20();
    vault = new MockEpochInvariantVault(address(underlying));

    strategy = new IdleCreditVault();
    stdstore.target(address(strategy)).sig(strategy.token.selector).checked_write(address(0));
    strategy.initialize(address(underlying), owner, manager, makeAddr("placeholderBorrower"), "Borrower", 10e18);

    cdoEpoch = new IdleCDOEpochVariant();
    stdstore.target(address(cdoEpoch)).sig(cdoEpoch.token.selector).checked_write(address(0));
    cdoEpoch.initialize(0, address(underlying), address(this), owner, rebalancer, address(strategy), 100000);

    aaTranche = IdleCDOTranche(cdoEpoch.AATranche());

    vm.prank(owner);
    strategy.setWhitelistedCDO(address(cdoEpoch));
    vm.prank(owner);
    strategy.setMaxApr(0);

    vm.startPrank(owner);
    cdoEpoch.setIsAYSActive(false);
    cdoEpoch.setFeeParams(address(this), 0);
    cdoEpoch.setInstantWithdrawParams(3 days, 1.5e18, false);
    cdoEpoch.setLossToleranceBps(5000);
    cdoEpoch.setEpochParams(30 days, 5 days);
    cdoEpoch.setKeyringParams(address(0), 0, false);
    cdoEpoch.setIsInterestMinted(true);
    vm.stopPrank();

    programmableBorrower = new ProgrammableBorrower();
    stdstore
      .target(address(programmableBorrower))
      .sig(programmableBorrower.underlyingToken.selector)
      .checked_write(address(0));
    programmableBorrower.initialize(
      address(underlying),
      address(vault),
      address(cdoEpoch),
      address(this),
      manager,
      revolvingBorrower,
      365e18
    );

    vm.prank(owner);
    strategy.setBorrower(address(programmableBorrower));
    vm.prank(owner);
    cdoEpoch.setIsProgrammableBorrower(true);
    vm.prank(manager);
    strategy.setAprs(0, 0);

    underlying.mint(lp, 1_000_000e18);
    underlying.mint(revolvingBorrower, 1_000_000e18);

    vm.prank(lp);
    underlying.approve(address(cdoEpoch), type(uint256).max);
    vm.prank(revolvingBorrower);
    underlying.approve(address(programmableBorrower), type(uint256).max);

    handler = new ProgrammableBorrowerEpochHandler(
      cdoEpoch,
      strategy,
      programmableBorrower,
      underlying,
      vault,
      aaTranche,
      owner,
      manager,
      lp,
      revolvingBorrower
    );
    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](11);
    selectors[0] = handler.depositAA.selector;
    selectors[1] = handler.requestWithdraw.selector;
    selectors[2] = handler.claimWithdraw.selector;
    selectors[3] = handler.startEpoch.selector;
    selectors[4] = handler.warp.selector;
    selectors[5] = handler.borrow.selector;
    selectors[6] = handler.repay.selector;
    selectors[7] = handler.addVaultGain.selector;
    selectors[8] = handler.applyVaultLoss.selector;
    selectors[9] = handler.setVaultWithdrawLimit.selector;
    selectors[10] = handler.stopEpoch.selector;
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice Programmable-borrower deployments must never accumulate instant-withdraw receipts.
  function invariant_programmableModeNeverUsesInstantWithdraws() external view {
    assertEq(strategy.pendingInstantWithdraws(), 0, "pending instant withdraws should stay zero");
    assertEq(strategy.instantWithdrawsRequests(lp), 0, "user instant withdraw receipts should stay zero");
  }

  /// @notice Core programmable-mode configuration should stay pinned for the whole harness.
  function invariant_programmableModeConfigurationStaysPinned() external view {
    assertTrue(cdoEpoch.isProgrammableBorrower(), "programmable flag should stay enabled");
    assertTrue(cdoEpoch.isInterestMinted(), "minted-interest mode should stay enabled");
    assertEq(strategy.unscaledApr(), 0, "strategy APR should stay at zero");
  }

  /// @notice Epoch-running state should stay synchronized with programmable-borrower accounting.
  function invariant_epochStateStaysInSync() external view {
    assertEq(
      cdoEpoch.isEpochRunning(),
      programmableBorrower.epochAccountingActive(),
      "epoch-running and borrower-accounting flags diverged"
    );
  }

  /// @notice After a successful non-default stop, the CDO should retain the realized interest value.
  function invariant_lastEpochInterestMatchesLastObservedSuccessfulStop() external view {
    if (!handler.hasExpectedLastEpochInterest()) {
      return;
    }
    assertApproxEqAbs(
      cdoEpoch.lastEpochInterest(),
      handler.expectedLastEpochInterest(),
      2,
      "last epoch interest drifted from the last successful stop"
    );
  }
}
