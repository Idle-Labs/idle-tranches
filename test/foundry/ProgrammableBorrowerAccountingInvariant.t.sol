// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ProgrammableBorrower} from "../../contracts/strategies/idle/ProgrammableBorrower.sol";

/// @notice Mintable underlying token used by the invariant harness.
contract MockInvariantERC20 is ERC20 {
  constructor() ERC20("Mock USDC", "mUSDC") {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }
}

/// @notice Deterministic ERC4626-style vault used to isolate programmable-borrower accounting.
/// @dev The vault exposes explicit gain, loss, and withdraw-limit knobs so the invariant harness
/// can exercise non-zero PnL and partial-liquidity paths without relying on a forked integration.
contract MockInvariantVault is ERC20 {
  MockInvariantERC20 public immutable assetToken;
  uint256 public withdrawLimit = type(uint256).max;

  /// @param _asset underlying token address
  constructor(address _asset) ERC20("Invariant Vault Share", "IVS") {
    assetToken = MockInvariantERC20(_asset);
  }

  /// @notice ERC4626 asset accessor
  function asset() external view returns (address) {
    return address(assetToken);
  }

  /// @notice Current underlying assets controlled by the vault.
  function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
  }

  /// @notice Share-to-asset conversion used by the invariant harness.
  function convertToAssets(uint256 shares) public view returns (uint256) {
    uint256 supply = totalSupply();
    if (supply == 0) {
      return shares;
    }
    return shares * totalAssets() / supply;
  }

  /// @notice Asset-to-share conversion used by the invariant harness.
  function convertToShares(uint256 assets) public view returns (uint256) {
    uint256 supply = totalSupply();
    uint256 managedAssets = totalAssets();
    if (supply == 0 || managedAssets == 0) {
      return assets;
    }
    return assets * supply / managedAssets;
  }

  /// @notice The withdrawable amount can be capped to simulate illiquidity.
  function maxWithdraw(address owner) external view returns (uint256) {
    uint256 maxAssets = convertToAssets(balanceOf(owner));
    return maxAssets < withdrawLimit ? maxAssets : withdrawLimit;
  }

  /// @notice Simulate positive vault PnL by minting underlying directly to the vault.
  function addGain(uint256 assets) external {
    assetToken.mint(address(this), assets);
  }

  /// @notice Simulate vault losses by burning underlying directly from the vault.
  function applyLoss(uint256 assets) external {
    uint256 bal = assetToken.balanceOf(address(this));
    assetToken.burn(address(this), assets > bal ? bal : assets);
  }

  /// @notice Set the maximum assets that can be withdrawn by any owner.
  function setWithdrawLimit(uint256 assets) external {
    withdrawLimit = assets;
  }

  /// @notice Deposit underlying and mint proportional shares.
  function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
    uint256 assetsBefore = totalAssets();
    uint256 supply = totalSupply();
    shares = supply == 0 || assetsBefore == 0 ? assets : assets * supply / assetsBefore;
    assetToken.transferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);
  }

  /// @notice Withdraw underlying and burn proportional shares.
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

  /// @notice Redeem shares and return underlying based on current share price.
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

  /// @dev Convert assets into shares rounding up so withdraw cannot overpay assets.
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

/// @notice Stateful handler that fuzzes only the core programmable-borrower accounting actions.
/// @dev The handler keeps a small reference model for:
/// - principal
/// - settled borrower-interest debt
/// - accrued but unsettled borrower interest
/// - epoch principal-like deposits that should extend the vault baseline
/// - deterministic vault gains, losses, and liquidity caps
///
/// The harness intentionally does not model instant withdrawals or full IdleCDO stop/start
/// orchestration. It is focused only on the accounting logic inside `ProgrammableBorrower`.
contract ProgrammableBorrowerAccountingHandler is Test {
  uint256 internal constant YEAR = 365 days;
  uint256 internal constant ONE_TRANCHE_TOKEN = 1e18;

  ProgrammableBorrower public immutable borrowerContract;
  MockInvariantERC20 public immutable underlying;
  MockInvariantVault public immutable vault;
  address public immutable idleCDO;
  address public immutable borrower;

  uint256 public modelBorrowerPrincipal;
  uint256 public modelBorrowerInterestDebt;
  uint256 public modelBorrowerInterestAccrued;
  uint256 public modelLastBorrowerAccrual;
  bool public modelEpochAccountingActive;
  uint256 public modelEpochPendingWithdraws;
  uint256 public modelEpochStartVaultAssets;
  uint256 public modelEpochPrincipalDeposits;
  uint256 public modelEpochWithdrawnFromVault;

  /// @param _borrowerContract programmable borrower under test
  /// @param _underlying underlying token
  /// @param _idleCDO trusted caller allowed to use the epoch hooks
  /// @param _borrower real borrower address used for borrow/repay calls
  constructor(
    ProgrammableBorrower _borrowerContract,
    MockInvariantERC20 _underlying,
    MockInvariantVault _vault,
    address _idleCDO,
    address _borrower
  ) {
    borrowerContract = _borrowerContract;
    underlying = _underlying;
    vault = _vault;
    idleCDO = _idleCDO;
    borrower = _borrower;
  }

  /// @notice Start a new accounting epoch with a fuzzed withdraw reserve.
  function startEpoch(uint256 pendingWithdrawSeed) external {
    if (modelEpochAccountingActive) {
      return;
    }

    _accrueModelInterest();

    uint256 totalAssets = underlying.balanceOf(address(borrowerContract)) + _vaultAssets();
    uint256 pendingWithdraws = bound(pendingWithdrawSeed, 0, totalAssets);
    uint256 startAssets = totalAssets;

    vm.prank(idleCDO);
    borrowerContract.onStartEpoch(pendingWithdraws);

    modelEpochAccountingActive = true;
    modelEpochPendingWithdraws = pendingWithdraws;
    modelEpochStartVaultAssets = startAssets;
    modelEpochPrincipalDeposits = 0;
    modelEpochWithdrawnFromVault = 0;
    modelLastBorrowerAccrual = block.timestamp;
  }

  /// @notice Advance time to fuzz borrower-interest accrual boundaries.
  function warp(uint256 elapsed) external {
    uint256 boundedElapsed = bound(elapsed, 1, 30 days);
    vm.warp(block.timestamp + boundedElapsed);
  }

  /// @notice Borrow a fuzzed amount, bounded to the live available liquidity.
  function borrow(uint256 amountSeed) external {
    if (!modelEpochAccountingActive) {
      return;
    }

    uint256 available = borrowerContract.availableToBorrow();
    if (available == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, available);

    _accrueModelInterest();
    uint256 onHand = underlying.balanceOf(address(borrowerContract));

    vm.prank(borrower);
    borrowerContract.borrow(amount);

    if (amount > onHand) {
      modelEpochWithdrawnFromVault += amount - onHand;
    }
    modelBorrowerPrincipal += amount;
  }

  /// @notice Repay a fuzzed amount, bounded to the tracked debt plus principal.
  function repay(uint256 amountSeed) external {
    uint256 totalOwed = modelBorrowerInterestDebt + modelBorrowerInterestAccruedNow() + modelBorrowerPrincipal;
    uint256 borrowerBalance = underlying.balanceOf(borrower);
    if (totalOwed == 0 || borrowerBalance == 0) {
      return;
    }

    uint256 amount = bound(amountSeed, 1, totalOwed < borrowerBalance ? totalOwed : borrowerBalance);

    _accrueModelInterest();

    vm.prank(borrower);
    borrowerContract.repay(amount);

    uint256 currentEpochInterestPaid;
    uint256 remaining = amount;

    uint256 settledInterestDue = modelBorrowerInterestDebt;
    if (settledInterestDue != 0) {
      if (remaining >= settledInterestDue) {
        modelBorrowerInterestDebt = 0;
        remaining -= settledInterestDue;
      } else {
        modelBorrowerInterestDebt = settledInterestDue - remaining;
        if (modelEpochAccountingActive) {
          modelEpochPrincipalDeposits += remaining;
        }
        return;
      }
    }

    uint256 accruedInterestDue = modelBorrowerInterestAccrued;
    if (remaining >= accruedInterestDue) {
      currentEpochInterestPaid = accruedInterestDue;
      modelBorrowerInterestAccrued = 0;
      remaining -= accruedInterestDue;

      uint256 principalPaid = remaining > modelBorrowerPrincipal ? modelBorrowerPrincipal : remaining;
      modelBorrowerPrincipal -= principalPaid;
    } else {
      currentEpochInterestPaid = remaining;
      modelBorrowerInterestAccrued = accruedInterestDue - remaining;
    }

    if (modelEpochAccountingActive) {
      modelEpochPrincipalDeposits += amount - currentEpochInterestPaid;
    }
  }

  /// @notice Add deterministic positive vault PnL during an active epoch.
  function addVaultGain(uint256 amountSeed) external {
    if (!modelEpochAccountingActive || borrowerContract.vaultSharesBalance() == 0) {
      return;
    }
    uint256 amount = bound(amountSeed, 1, 100_000e18);
    vault.addGain(amount);
  }

  /// @notice Apply deterministic vault loss during an active epoch.
  function applyVaultLoss(uint256 amountSeed) external {
    if (!modelEpochAccountingActive || borrowerContract.vaultSharesBalance() == 0) {
      return;
    }
    uint256 amount = bound(amountSeed, 1, vault.totalAssets());
    vault.applyLoss(amount);
  }

  /// @notice Cap or uncap withdrawable vault liquidity to exercise partial stop-epoch recalls.
  function setVaultWithdrawLimit(uint256 limitSeed, bool capLiquidity) external {
    uint256 currentAssets = vault.convertToAssets(borrowerContract.vaultSharesBalance());
    vault.setWithdrawLimit(capLiquidity ? bound(limitSeed, 0, currentAssets) : type(uint256).max);
  }

  /// @notice Stop the current epoch and optionally settle accrued borrower interest immediately.
  /// @dev Settlement is fuzzed only in the same transaction as stop to mirror the production path.
  function stopEpoch(uint256 amountRequiredSeed, bool settle) external {
    if (!modelEpochAccountingActive) {
      return;
    }

    _accrueModelInterest();

    uint256 onHand = underlying.balanceOf(address(borrowerContract));
    uint256 totalAssets = onHand + _vaultAssets();
    uint256 amountRequired = bound(amountRequiredSeed, 0, totalAssets);
    if (amountRequired > onHand) {
      uint256 shortfall = amountRequired - onHand;
      uint256 maxW = vault.maxWithdraw(address(borrowerContract));
      modelEpochWithdrawnFromVault += shortfall > maxW ? maxW : shortfall;
    }

    vm.prank(idleCDO);
    borrowerContract.onStopEpoch(amountRequired);

    modelEpochAccountingActive = false;
    modelEpochPendingWithdraws = 0;

    if (!settle) {
      return;
    }

    vm.prank(idleCDO);
    borrowerContract.settleBorrowerInterest();

    modelBorrowerInterestDebt += modelBorrowerInterestAccrued;
    modelBorrowerInterestAccrued = 0;
  }

  /// @notice Current modelled borrower interest including uncheckpointed time-based accrual.
  function modelBorrowerInterestAccruedNow() public view returns (uint256) {
    uint256 principal = modelBorrowerPrincipal;
    uint256 accrued = modelBorrowerInterestAccrued;
    uint256 last = modelLastBorrowerAccrual;
    uint256 apr = borrowerContract.borrowerApr();
    if (principal == 0 || last == 0 || apr == 0) {
      return accrued;
    }

    uint256 elapsed = block.timestamp - last;
    if (elapsed == 0) {
      return accrued;
    }

    return accrued + principal * (apr / 100) * elapsed / (YEAR * ONE_TRANCHE_TOKEN);
  }

  /// @notice Expected total pool-facing interest in the deterministic invariant harness.
  function modelTotalInterestDueNow() external view returns (uint256) {
    (uint256 vaultInterest, uint256 loss) = modelVaultNetInterest();
    if (modelEpochAccountingActive) {
      uint256 totalGain = vaultInterest + modelBorrowerInterestAccruedNow();
      return totalGain > loss ? totalGain - loss : 0;
    }
    return modelBorrowerInterestAccruedNow();
  }

  /// @notice Expected borrower interest still owed in the invariant harness.
  function modelBorrowerInterestOwedNow() external view returns (uint256) {
    return modelBorrowerInterestDebt + modelBorrowerInterestAccruedNow();
  }

  /// @notice Compute the modelled vault net delta split into interest and loss.
  function modelVaultNetInterest() public view returns (uint256 interest, uint256 loss) {
    if (modelEpochAccountingActive) {
      uint256 earnedAssets = _vaultAssets() + modelEpochWithdrawnFromVault;
      uint256 principalAssets = modelEpochStartVaultAssets + modelEpochPrincipalDeposits;
      if (earnedAssets > principalAssets) {
        interest = earnedAssets - principalAssets;
      } else {
        loss = principalAssets - earnedAssets;
      }
    }
  }

  /// @dev Current deterministic vault assets held by the programmable borrower.
  function _vaultAssets() internal view returns (uint256) {
    uint256 shares = borrowerContract.vaultSharesBalance();
    return shares == 0 ? 0 : vault.convertToAssets(shares);
  }

  /// @dev Checkpoint modelled borrower interest up to the current timestamp.
  function _accrueModelInterest() internal {
    uint256 last = modelLastBorrowerAccrual;
    uint256 principal = modelBorrowerPrincipal;
    uint256 apr = borrowerContract.borrowerApr();
    if (last == 0 || principal == 0 || apr == 0) {
      modelLastBorrowerAccrual = block.timestamp;
      return;
    }

    uint256 elapsed = block.timestamp - last;
    if (elapsed == 0) {
      return;
    }

    modelBorrowerInterestAccrued += principal * (apr / 100) * elapsed / (YEAR * ONE_TRANCHE_TOKEN);
    modelLastBorrowerAccrual = block.timestamp;
  }
}

/// @notice Invariant harness for the core programmable-borrower accounting logic.
/// @dev The harness intentionally avoids full IdleCDO orchestration so the invariants stay focused
/// on the borrower ledger, vault PnL tracking, and repayment classification rules.
contract ProgrammableBorrowerAccountingInvariant is StdInvariant, Test {
  using stdStorage for StdStorage;
  MockInvariantERC20 internal underlying;
  MockInvariantVault internal vault;
  ProgrammableBorrower internal borrowerContract;
  ProgrammableBorrowerAccountingHandler internal handler;

  address internal idleCDO = makeAddr("idleCDO");
  address internal borrower = makeAddr("borrower");

  function setUp() public {
    underlying = new MockInvariantERC20();
    vault = new MockInvariantVault(address(underlying));

    borrowerContract = new ProgrammableBorrower();
    stdstore
      .target(address(borrowerContract))
      .sig(borrowerContract.underlyingToken.selector)
      .checked_write(address(0));
    borrowerContract.initialize(address(underlying), address(vault), idleCDO, address(this), address(this));
    borrowerContract.setBorrower(borrower);
    borrowerContract.setBorrowerApr(365e18);

    // Prefund the borrower contract with idle capital and the real borrower with ample repayment liquidity.
    underlying.mint(address(borrowerContract), 1_000_000e18);
    underlying.mint(borrower, 1_000_000e18);

    vm.prank(borrower);
    underlying.approve(address(borrowerContract), type(uint256).max);

    handler = new ProgrammableBorrowerAccountingHandler(borrowerContract, underlying, vault, idleCDO, borrower);
    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](8);
    selectors[0] = handler.startEpoch.selector;
    selectors[1] = handler.warp.selector;
    selectors[2] = handler.borrow.selector;
    selectors[3] = handler.repay.selector;
    selectors[4] = handler.stopEpoch.selector;
    selectors[5] = handler.addVaultGain.selector;
    selectors[6] = handler.applyVaultLoss.selector;
    selectors[7] = handler.setVaultWithdrawLimit.selector;
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice The borrower debt ledger should always match the reference model.
  function invariant_borrowerLedgerMatchesModel() external view {
    assertEq(borrowerContract.borrowerPrincipal(), handler.modelBorrowerPrincipal(), "principal mismatch");
    assertEq(borrowerContract.borrowerInterestDebt(), handler.modelBorrowerInterestDebt(), "interest debt mismatch");
    assertEq(
      borrowerContract.borrowerInterestAccrued(),
      handler.modelBorrowerInterestAccrued(),
      "stored accrued interest mismatch"
    );
    assertEq(
      borrowerContract.borrowerInterestAccruedNow(),
      handler.modelBorrowerInterestAccruedNow(),
      "live accrued interest mismatch"
    );
    assertEq(
      borrowerContract.borrowerInterestOwedNow(),
      handler.modelBorrowerInterestOwedNow(),
      "total borrower interest owed mismatch"
    );
  }

  /// @notice The pool-facing interest number should match the deterministic reference model.
  function invariant_totalInterestDueMatchesModel() external view {
    assertEq(
      borrowerContract.totalInterestDueNow(),
      handler.modelTotalInterestDueNow(),
      "total interest due mismatch"
    );
  }

  /// @notice The borrowable liquidity should always equal total assets minus reserved withdraws.
  function invariant_availableToBorrowMatchesFreeAssets() external view {
    uint256 totalAssets = underlying.balanceOf(address(borrowerContract)) + vault.convertToAssets(borrowerContract.vaultSharesBalance());
    uint256 reserved = borrowerContract.epochPendingWithdraws();
    uint256 expectedAvailable = totalAssets <= reserved ? 0 : totalAssets - reserved;
    assertEq(borrowerContract.availableToBorrow(), expectedAvailable, "available to borrow mismatch");
  }

  /// @notice Vault-side epoch accounting tracked by the contract should match the reference model.
  function invariant_epochVaultAccountingMatchesModel() external view {
    assertEq(
      borrowerContract.epochStartVaultAssets(),
      handler.modelEpochStartVaultAssets(),
      "epoch start assets mismatch"
    );
    assertEq(
      borrowerContract.epochDepositedToVault(),
      handler.modelEpochPrincipalDeposits(),
      "epoch principal deposits mismatch"
    );
    assertEq(
      borrowerContract.epochWithdrawnFromVault(),
      handler.modelEpochWithdrawnFromVault(),
      "epoch withdrawn assets mismatch"
    );
    assertEq(
      borrowerContract.epochPendingWithdraws(),
      handler.modelEpochPendingWithdraws(),
      "reserved pending withdraws mismatch"
    );
    assertEq(
      borrowerContract.epochAccountingActive(),
      handler.modelEpochAccountingActive(),
      "epoch active flag mismatch"
    );
  }
}
