// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CollateralsVault, IIdleCDOEpochVariant, IIdleCreditVault, ILiquidationAdapter} from "../../contracts/strategies/idle/CollateralsVault.sol";

contract MockERC20 is ERC20 {
  uint8 private _decimals;
  constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
    _decimals = decimals_;
  }
  function decimals() public view override returns (uint8) {
    return _decimals;
  }
  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract MockPriceFeed {
  int256 public answer;
  uint8 public decimals_;
  uint256 public updatedAt;
  constructor(int256 _answer, uint8 _decimals, uint256 _updatedAt) {
    answer = _answer;
    decimals_ = _decimals;
    updatedAt = _updatedAt;
  }
  function setAnswer(int256 _answer, uint256 _updatedAt) external {
    answer = _answer;
    updatedAt = _updatedAt;
  }
  function decimals() external view returns (uint8) {
    return decimals_;
  }
  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (0, answer, 0, updatedAt, 0);
  }
}

contract MockStrategy is IIdleCreditVault {
  address public override borrower;
  address public override manager;
  constructor(address _borrower, address _manager) {
    borrower = _borrower;
    manager = _manager;
  }
}

contract MockCreditVault is IIdleCDOEpochVariant {
  address public override strategy;
  address public override token;
  uint256 public contractValue;
  constructor(address _strategy, address _token, uint256 _contractValue) {
    strategy = _strategy;
    token = _token;
    contractValue = _contractValue;
  }
  function setContractValue(uint256 _value) external {
    contractValue = _value;
  }
  function getContractValue() external view override returns (uint256) {
    return contractValue;
  }
}

contract MockLiquidationAdapter is ILiquidationAdapter {
  function liquidateCollateral(
    address collateral,
    uint256 collateralAmount,
    address borrowedToken,
    uint256 minOut,
    bytes calldata
  ) external returns (uint256 borrowedOut) {
    // pull collateral
    ERC20(collateral).transferFrom(msg.sender, address(this), collateralAmount);
    // simplistic conversion: 1:1 collateral to borrowed
    borrowedOut = collateralAmount;
    MockERC20(borrowedToken).mint(msg.sender, borrowedOut);
    if (borrowedOut < minOut) {
      revert("slippage");
    }
  }
}

/// @notice Simple adapter used only in fork tests; sends pre-funded borrowed tokens.
contract ForkLiquidationAdapter is ILiquidationAdapter {
  function liquidateCollateral(
    address collateral,
    uint256 collateralAmount,
    address borrowedToken,
    uint256 minOut,
    bytes calldata
  ) external returns (uint256 borrowedOut) {
    ERC20(collateral).transferFrom(msg.sender, address(this), collateralAmount);
    borrowedOut = ERC20(borrowedToken).balanceOf(address(this));
    if (borrowedOut < minOut) revert("MIN_OUT");
    ERC20(borrowedToken).transfer(msg.sender, borrowedOut);
  }
}

contract TestCollateralsVault is Test {
  using stdStorage for StdStorage;

  // Fork config (optional)
  uint256 internal constant FORK_BLOCK = 23941000;
  address internal constant LIVE_CREDIT_VAULT = 0x14B8E918848349D1e71e806a52c13D4e0d3246E0;
  address internal borrower = address(0xB0B);
  address internal manager = address(0xA11CE);
  address internal pauser = address(0x12345);

  CollateralsVault internal vault;
  MockERC20 internal borrowedToken;
  MockPriceFeed internal borrowedFeed;
  MockStrategy internal strategy;
  MockCreditVault internal creditVault;
  MockERC20 internal collateralToken;
  MockPriceFeed internal collateralFeed;
  MockERC20 internal collateralToken2;
  MockPriceFeed internal collateralFeed2;
  MockLiquidationAdapter internal adapter;
  bool internal runFork;
  CollateralsVault internal forkVault;
  ForkLiquidationAdapter internal forkAdapter;

  function setUp() public {
    runFork = vm.envOr("RUN_FORK_TESTS", false);
    vm.warp(2 days); // avoid underflow in validity checks
    vault = new CollateralsVault();
    borrowedToken = new MockERC20("Borrowed", "BRW", 18);
    borrowedFeed = new MockPriceFeed(int256(1e8), 8, block.timestamp);
    strategy = new MockStrategy(borrower, manager);
    creditVault = new MockCreditVault(address(strategy), address(borrowedToken), 75e18); // $75 debt
    collateralToken = new MockERC20("Collateral", "COL", 18);
    collateralFeed = new MockPriceFeed(int256(1e8), 8, block.timestamp);
    collateralToken2 = new MockERC20("Collateral2", "COL2", 6);
    collateralFeed2 = new MockPriceFeed(int256(2e8), 8, block.timestamp); // $2
    adapter = new MockLiquidationAdapter();

    // reset borrower to allow initialize
    stdstore.target(address(vault)).sig(vault.borrower.selector).checked_write(address(0));
    vault.initialize(pauser, address(creditVault), address(borrowedFeed), borrowedFeed.decimals(), 1 days);
    vault.setLiquidationAdapter(address(adapter), true);

    // fork setup (optional)
    if (runFork) {
      vm.createSelectFork(vm.envString("ETH_RPC_URL"), FORK_BLOCK);
    forkVault = new CollateralsVault();
    stdstore.target(address(forkVault)).sig(forkVault.borrower.selector).checked_write(address(0));
    forkVault.initialize(pauser, LIVE_CREDIT_VAULT, address(borrowedFeed), borrowedFeed.decimals(), 1 days);
    forkAdapter = new ForkLiquidationAdapter();
  }
  }

  function _addCollateral() internal {
    vault.addCollateral(address(collateralToken), address(collateralFeed), 1 days);
  }

  function _addCollateral2() internal {
    vault.addCollateral(address(collateralToken2), address(collateralFeed2), 1 days);
  }

  function _mintAndApproveCollateral(address to, uint256 amount) internal {
    collateralToken.mint(to, amount);
    vm.prank(to);
    collateralToken.approve(address(vault), amount);
  }

  function _mintAndApproveCollateral2(address to, uint256 amount) internal {
    collateralToken2.mint(to, amount);
    vm.prank(to);
    collateralToken2.approve(address(vault), amount);
  }

  function testInitializeSetsParams() external {
    assertEq(vault.owner(), address(this));
    assertEq(address(vault.creditVault()), address(creditVault));
    assertEq(vault.borrower(), borrower);
    assertEq(vault.manager(), manager);
    assertEq(vault.pauser(), pauser);
    assertEq(vault.penaltyReceiver(), vault.TREASURY_LEAGUE_MULTISIG());
    assertEq(vault.liquidationDelay(), 3 days);
    assertEq(vault.liquidationPenalty(), 50);
    assertEq(vault.ltv(), 750);
    assertEq(vault.borrowedTokenPriceFeed(), address(borrowedFeed));
    assertEq(vault.borrowedTokenPriceFeedDecimals(), borrowedFeed.decimals());
    assertEq(vault.borrowedTokenPriceFeedValidityPeriod(), 1 days);
  }

  function testInitializeRevertsOnInvalidFeed() external {
    CollateralsVault newVault = new CollateralsVault();
    stdstore.target(address(newVault)).sig(newVault.borrower.selector).checked_write(address(0));
    vm.expectRevert(CollateralsVault.InvalidData.selector);
    newVault.initialize(pauser, address(creditVault), address(0), 8, 1 days);
    vm.expectRevert(CollateralsVault.InvalidData.selector);
    newVault.initialize(pauser, address(creditVault), address(borrowedFeed), 19, 1 days);
  }

  function testAddCollateralStoresInfo() external {
    vault.addCollateral(address(collateralToken), address(collateralFeed), 1 days);
    CollateralsVault.CollateralInfo memory info = vault.getCollateralInfo(address(collateralToken));
    assertTrue(info.allowed);
    assertEq(info.priceFeed, address(collateralFeed));
    assertEq(info.tokenDecimals, 18);
    assertEq(info.priceFeedDecimals, 8);
    assertEq(info.validityPeriod, 1 days);
  }

  function testAddCollateralRevertsOnInvalidData() external {
    vm.expectRevert(CollateralsVault.InvalidData.selector);
    vault.addCollateral(address(0), address(collateralFeed), 0);
    vm.expectRevert(CollateralsVault.InvalidData.selector);
    vault.addCollateral(address(collateralToken), address(0), 0);
  }

  function testDisableCollateralBypassOracleExcludesFromLTV() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 100e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 100e18);
    uint256 beforeValue = vault.getTotCollateralsScaled();
    vm.prank(address(this));
    vault.disableCollateralBypassOracle(address(collateralToken));
    uint256 afterValue = vault.getTotCollateralsScaled();
    assertGt(beforeValue, 0);
    assertEq(afterValue, 0);
  }

  function testDepositOnlyBorrower() external {
    _addCollateral();
    _mintAndApproveCollateral(address(this), 10e18);
    vm.expectRevert(CollateralsVault.NotAllowed.selector);
    vault.depositCollateral(address(collateralToken), 10e18);

    _mintAndApproveCollateral(borrower, 10e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 10e18);
    assertEq(collateralToken.balanceOf(address(vault)), 10e18);
  }

  function testRedeemRevertsIfWouldBeLiquidatable() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 100e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 100e18);
    // withdraw 10% collateral -> makes position unhealthy (borrowed 75, max borrowable becomes 67.5)
    vm.prank(borrower);
    vm.expectRevert(CollateralsVault.NotAllowed.selector);
    vault.redeemCollateral(address(collateralToken), 10e18);
  }

  function testRedeemAllowedWhenHealthy() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 100e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 100e18);
    creditVault.setContractValue(50e18); // lower debt to keep LTV healthy
    // small redeem keeps LTV healthy
    vm.prank(borrower);
    vault.redeemCollateral(address(collateralToken), 1e18);
    assertEq(collateralToken.balanceOf(borrower), 1e18);
  }

  function testPauseBlocksDepositAndRedeem() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 10e18);
    vault.pause();
    vm.prank(borrower);
    vm.expectRevert();
    vault.depositCollateral(address(collateralToken), 1e18);
    vm.prank(borrower);
    vm.expectRevert();
    vault.redeemCollateral(address(collateralToken), 0);
  }

  function testBorrowedScaledOffsetsHeldBorrowedTokens() external {
    uint256 baseBorrowed = vault.borrowedScaled();
    borrowedToken.mint(address(vault), 1_000e18);
    uint256 afterBorrowed = vault.borrowedScaled();
    assertLt(afterBorrowed, baseBorrowed);
    assertEq(afterBorrowed, 0);
  }

  function testBorrowedTokenPriceStaleReverts() external {
    borrowedFeed.setAnswer(int256(1e8), block.timestamp - 2 days);
    vm.expectRevert(CollateralsVault.InvalidOraclePrice.selector);
    vault.borrowedScaled();
  }

  function testForkBorrowedScaled() external view {
    if (!runFork) return;
    uint256 borrowedVal = forkVault.borrowedScaled();
    assertGt(borrowedVal, 0);
  }

  function testForkLiquidationFlow() external {
    if (!runFork) return;

    // overwrite borrower and manager to this contract for testing
    stdstore.target(address(forkVault)).sig(forkVault.borrower.selector).checked_write(address(this));
    stdstore.target(address(forkVault)).sig(forkVault.manager.selector).checked_write(address(this));

    // point creditVault to a controllable mock with small debt
    MockCreditVault mockCV = new MockCreditVault(address(strategy), address(borrowedToken), 0);
    uint256 dec = forkVault.borrowedTokenDecimals();
    uint256 contractValue = 1_000 * 10 ** dec; // 1000 tokens debt
    mockCV.setContractValue(contractValue);
    stdstore.target(address(forkVault)).sig(forkVault.creditVault.selector).checked_write(address(mockCV));

    // allow adapter and add collateral (use borrowed token as collateral)
    forkVault.setLiquidationAdapter(address(forkAdapter), true);
    forkVault.addCollateral(address(borrowedToken), address(borrowedFeed), 1 days);

    // fund borrower and adapter with borrowed tokens
    deal(address(borrowedToken), address(this), 5_000 * 10 ** dec);
    deal(address(borrowedToken), address(forkAdapter), 5_000 * 10 ** dec);

    // deposit collateral
    borrowedToken.approve(address(forkVault), type(uint256).max);
    forkVault.depositCollateral(address(borrowedToken), 4_000 * 10 ** dec);

    // trigger margin call and liquidate
    forkVault.marginCall();
    vm.warp(block.timestamp + forkVault.liquidationDelay() + 1);
    address[] memory cols = toArray(address(borrowedToken));
    uint256[] memory mins = toArrayUint(500 * 10 ** dec);
    address[] memory ads = toArray(address(forkAdapter));
    bytes[] memory datas = toArrayBytes("");
    forkVault.liquidate(cols, mins, ads, datas);
    assertEq(forkVault.lastMarginCallTimestamp(), 0);
  }

  function testMarginCallOnlyManager() external {
    vm.expectRevert(CollateralsVault.NotAllowed.selector);
    vault.marginCall();
  }

  function testLiquidateRequiresManagerAndDelay() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 100e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 100e18);
    creditVault.setContractValue(200e18);
    vm.prank(manager);
    vault.marginCall();
    vm.expectRevert(CollateralsVault.NotLiquidatable.selector);
    vm.prank(manager);
    vault.liquidate(toArray(address(collateralToken)), toArrayUint(0), toArray(address(adapter)), toArrayBytes(""));
    vm.warp(block.timestamp + vault.liquidationDelay() + 1);
    vm.expectRevert(CollateralsVault.NotAllowed.selector);
    vault.liquidate(toArray(address(collateralToken)), toArrayUint(0), toArray(address(adapter)), toArrayBytes(""));
  }

  function testLiquidateFlowPenalizesAndResetsTimestamp() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 400e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 400e18);
    // make position liquidatable: increase borrowed value
    creditVault.setContractValue(500e18);
    vm.prank(manager);
    vault.marginCall();
    // fund vault with borrowed tokens to cover penalty transfer after margin call
    borrowedToken.mint(address(vault), 100e18);
    vm.warp(block.timestamp + vault.liquidationDelay() + 1);
    // refresh oracle timestamps to keep prices valid
    borrowedFeed.setAnswer(int256(1e8), block.timestamp);
    collateralFeed.setAnswer(int256(1e8), block.timestamp);
    vm.prank(manager);
    (uint256[] memory outs, uint256 out) = vault.liquidate(
      toArray(address(collateralToken)),
      toArrayUint(0),
      toArray(address(adapter)),
      toArrayBytes("")
    );
    assertEq(vault.lastMarginCallTimestamp(), 0);
    assertGt(outs[0], 0);
    assertGt(out, 0);
    // penalty should have been sent
    // penaltyReceiver is constant, just check balance > 0
    assertGt(borrowedToken.balanceOf(vault.penaltyReceiver()), 0);
  }

  function testLiquidateUsesProvidedOrderAndHandlesRepeats() external {
    _addCollateral();
    _addCollateral2();
    _mintAndApproveCollateral(borrower, 100e18); // $100
    _mintAndApproveCollateral2(borrower, 50_000_000); // 50 COL2 (6 decimals) => $100
    vm.startPrank(borrower);
    vault.depositCollateral(address(collateralToken), 100e18);
    collateralToken2.approve(address(vault), 50_000_000);
    vault.depositCollateral(address(collateralToken2), 50_000_000);
    vm.stopPrank();

    creditVault.setContractValue(300e18); // shortfall > single collateral, needs both
    vm.prank(manager);
    vault.marginCall();
    borrowedToken.mint(address(vault), 100e18);
    vm.warp(block.timestamp + vault.liquidationDelay() + 1);
    // refresh oracle timestamps
    borrowedFeed.setAnswer(int256(1e8), block.timestamp);
    collateralFeed.setAnswer(int256(1e8), block.timestamp);
    collateralFeed2.setAnswer(int256(2e8), block.timestamp);
    // Provide order with duplicate entry; should still succeed
    address[] memory order = new address[](3);
    order[0] = address(collateralToken2);
    order[1] = address(collateralToken2);
    order[2] = address(collateralToken);
    vm.prank(manager);
    uint256[] memory mins = new uint256[](3);
    mins[0] = 1;
    mins[1] = 1;
    mins[2] = 1;
    address[] memory adaptersList = new address[](3);
    adaptersList[0] = address(adapter);
    adaptersList[1] = address(adapter);
    adaptersList[2] = address(adapter);
    bytes[] memory datas = new bytes[](3);
    (uint256[] memory outs, uint256 out) = vault.liquidate(order, mins, adaptersList, datas);
    assertEq(vault.lastMarginCallTimestamp(), 0);
    assertGt(outs[0] + outs[1] + outs[2], 0);
    assertGt(out, 0);
  }

  function testLiquidateRevertsWhenInsufficientCollateral() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 1e18); // $1
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 1e18);
    creditVault.setContractValue(1_000e18); // huge debt
    vm.prank(manager);
    vault.marginCall();
    borrowedToken.mint(address(vault), 10e18);
    vm.warp(block.timestamp + vault.liquidationDelay() + 1);
    borrowedFeed.setAnswer(int256(1e8), block.timestamp);
    collateralFeed.setAnswer(int256(1e8), block.timestamp);
    vm.prank(manager);
    vm.expectRevert(CollateralsVault.NotEnoughCollaterals.selector);
    vault.liquidate(toArray(address(collateralToken)), toArrayUint(0), toArray(address(adapter)), toArrayBytes(""));
  }

  function testBorrowedTokenPriceFeedZeroReverts() external {
    borrowedFeed.setAnswer(0, block.timestamp);
    vm.expectRevert(CollateralsVault.InvalidOraclePrice.selector);
    vault.borrowedScaled();
  }

  function testRemoveCollateralAllowsWithdrawButNotCounted() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 10e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 10e18);
    creditVault.setContractValue(0);
    vm.prank(address(this));
    vault.removeCollateral(address(collateralToken));
    // value should be zero in totals
    assertEq(vault.getTotCollateralsScaled(), 0);
    // borrower can still withdraw
    vm.prank(borrower);
    vault.redeemCollateral(address(collateralToken), 10e18);
    assertEq(collateralToken.balanceOf(borrower), 10e18);
  }

  function testPauseBlocksMarginCallAndLiquidate() external {
    _addCollateral();
    _mintAndApproveCollateral(borrower, 10e18);
    vm.prank(borrower);
    vault.depositCollateral(address(collateralToken), 10e18);
    vault.pause();
    vm.prank(manager);
    vm.expectRevert();
    vault.marginCall();
    vm.prank(manager);
    vm.expectRevert();
    vault.liquidate(toArray(address(collateralToken)), toArrayUint(0), toArray(address(adapter)), toArrayBytes(""));
  }

  function toArray(address a) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
  }

  function toArrayUint(uint256 v) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    arr[0] = v;
  }

  function toArrayBytes(bytes memory b) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](1);
    arr[0] = b;
  }
}
