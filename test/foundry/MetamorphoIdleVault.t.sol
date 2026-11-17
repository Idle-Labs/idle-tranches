// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {TranchesChainlinkOracle} from "../../contracts/strategies/morpho/TranchesChainlinkOracle.sol";
import {IMetaMorphoOracleFactory} from "../../contracts/interfaces/morpho/IMetaMorphoOracleFactory.sol";
import { DeployMetamorphoVault } from "../../forge-scripts/DeployMetamorphoVault.s.sol";

import {IIdleCDOStrategy} from "../../contracts/interfaces/IIdleCDOStrategy.sol";
import {IIdleCDO} from "../../contracts/interfaces/IIdleCDO.sol";
import {IdleCDOTranche} from "../../contracts/IdleCDOTranche.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626} from "../../contracts/interfaces/IERC4626.sol";

interface IKeyringWhitelist {
  function setWhitelistStatus(address entity, bool status) external;
}

contract MetamorphoIdleVault is Test, DeployMetamorphoVault {
  // @notice test tranche prices pre and post redeem
  uint256 BLOCK = 22525130;
  string constant network = 'mainnet';
  address internal constant CDO = 0xf6223C567F21E33e859ED7A045773526E9E3c2D5;
  address internal constant KEYRING = 0x6351370a1c982780Da2D8c85DfedD421F7193Fa5;

  function setUp() public {
    vm.createSelectFork(network, BLOCK);
    vm.startPrank(TL_MULTISIG);
    IKeyringWhitelist(KEYRING).setWhitelistStatus(DEPLOYER, true);
    vm.stopPrank();

    // Give LOAN_TOKEN to deployer
    deal(LOAN_TOKEN, DEPLOYER, 100 * 1e6);
    // Deposit LOAN_TOKEN in CDO with DEPLOYER
    vm.startPrank(DEPLOYER);
    IERC20Detailed(LOAN_TOKEN).approve(CDO, type(uint256).max);
    IIdleCDO(CDO).depositAA(1e6);
    vm.stopPrank();
  }

  function testMetamorphoFactoryCreation() external {
    vm.startPrank(DEPLOYER);
    _setUpMorphoVault();
    vm.stopPrank();

    // vm.prank(TL_MULTISIG);
    // IMMVault(mmVault).acceptOwnership();
    // console.log('vault.address ', address(mmVault));
    // console.log('vault.owner   ', IMMVault(mmVault).owner());
  }
}

/// @dev Minimal loan token exposing only the decimals read by the oracle
contract MockOracleLoanToken {
  uint8 public decimals;

  /// @param _decimals Decimals returned by the token
  constructor(uint8 _decimals) {
    decimals = _decimals;
  }
}

/// @dev Minimal CDO exposing only the calls made by the oracle
contract MockOracleCDO {
  address public token;
  uint256 public price;

  /// @param _token Underlying (loan) token returned by the CDO
  constructor(address _token) {
    token = _token;
  }

  /// @notice Sets the virtualPrice returned for any tranche
  /// @param _price New virtualPrice
  function setPrice(uint256 _price) external {
    price = _price;
  }

  /// @notice Returns the configured virtualPrice, whatever the tranche
  function virtualPrice(address) external view returns (uint256) {
    return price;
  }
}

/// @dev Minimal tranche token exposing only the calls made by the oracle and the deploy script
contract MockOracleTranche {
  address public minter;
  uint8 public decimals = 18;

  /// @param _minter CDO returned as the tranche minter
  constructor(address _minter) {
    minter = _minter;
  }
}

/// @dev Morpho oracle factory that only records the feed and decimals it receives
contract MockMorphoOracleFactory {
  address public baseFeed;
  uint256 public baseDecimals;
  uint256 public quoteDecimals;

  /// @notice Records the base feed and token decimals, same ABI as IMetaMorphoOracleFactory
  /// @return oracle Address of this recording factory
  function createMorphoChainlinkOracleV2(
    address,
    uint256,
    address baseFeed1,
    address,
    uint256 baseTokenDecimals,
    address,
    uint256,
    address,
    address,
    uint256 quoteTokenDecimals,
    bytes32
  ) external returns (address oracle) {
    baseFeed = baseFeed1;
    baseDecimals = baseTokenDecimals;
    quoteDecimals = quoteTokenDecimals;
    return address(this);
  }
}

contract TestTranchesChainlinkOracle is Test {
  uint256 internal constant SCALE = 1e18;
  uint256 internal constant ONE = 1e6; // virtualPrice of 1 with a 6 decimals loan token
  uint256 internal constant EIP170_LIMIT = 24576;

  MockOracleLoanToken internal loanToken;
  MockOracleCDO internal mockCdo;
  MockOracleTranche internal tranche;

  /// @notice Deploys mocks for a 6 decimals loan token and a virtualPrice of 1
  function setUp() public {
    loanToken = new MockOracleLoanToken(6);
    mockCdo = new MockOracleCDO(address(loanToken));
    tranche = new MockOracleTranche(address(mockCdo));
    mockCdo.setPrice(ONE);
  }

  /// @dev Deploys the oracle with `discount` and returns its current price
  function _price(uint256 discount) internal returns (uint256) {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), discount);
    (, int256 answer,,,) = oracle.latestRoundData();
    return uint256(answer);
  }

  /// @notice Constructor wires immutables and keeps the virtualPrice decimals
  function testConstructor() external {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), 5e16);
    assertEq(oracle.collateralToken(), address(tranche));
    assertEq(address(oracle.cdo()), address(mockCdo));
    assertEq(oracle.loanToken(), address(loanToken));
    assertEq(oracle.loanTokenDecimals(), 6);
    assertEq(oracle.decimals(), 6);
    assertEq(oracle.discount(), 5e16);
    assertEq(oracle.DISCOUNT_SCALE(), SCALE);
  }

  /// @notice A zero discount returns the virtualPrice unchanged
  function testZeroDiscountReturnsVirtualPrice() external {
    assertEq(_price(0), ONE);
    mockCdo.setPrice(1_234_567);
    assertEq(_price(0), 1_234_567);
  }

  /// @notice virtualPrice of 1 with a 5% discount returns 0.95 in the oracle units
  function testFivePercentDiscount() external {
    assertEq(_price(5e16), 950_000);
  }

  /// @notice The discounted price follows the virtualPrice as it changes
  function testDiscountTracksVirtualPrice() external {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), 5e16);
    mockCdo.setPrice(1_100_000);
    (, int256 answer,,,) = oracle.latestRoundData();
    assertEq(uint256(answer), 1_045_000);
  }

  /// @notice Scaling is preserved with a loan token that has 18 decimals
  function testDiscountWith18DecimalsLoanToken() external {
    loanToken = new MockOracleLoanToken(18);
    mockCdo = new MockOracleCDO(address(loanToken));
    tranche = new MockOracleTranche(address(mockCdo));
    mockCdo.setPrice(1e18);
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), 5e16);
    (, int256 answer,,,) = oracle.latestRoundData();
    assertEq(oracle.decimals(), 18);
    assertEq(uint256(answer), 0.95e18);
  }

  /// @notice Boundary: 100% discount is accepted and prices the collateral at zero
  function testFullDiscountIsAccepted() external {
    assertEq(_price(SCALE), 0);
    mockCdo.setPrice(type(uint256).max);
    assertEq(_price(SCALE), 0);
  }

  /// @notice Boundary: the smallest discount (1e-18) on a 1e6 price rounds down by one unit
  function testSmallestDiscountRoundsDown() external {
    // 1e6 * (1e18 - 1) / 1e18 = 999999.999999999999 -> 999999
    assertEq(_price(1), ONE - 1);
  }

  /// @notice Boundary: largest discount below 100% (1e18 - 1) rounds a 1e6 price down to 0
  function testLargestDiscountBelowFull() external {
    // 1e6 * 1 / 1e18 = 0.000000000001 -> 0
    assertEq(_price(SCALE - 1), 0);
  }

  /// @notice Discounts above 100% are rejected
  function testDiscountAboveFullReverts() external {
    vm.expectRevert(TranchesChainlinkOracle.DiscountTooHigh.selector);
    new TranchesChainlinkOracle(address(tranche), SCALE + 1);
  }

  /// @notice Boundary: the maximum uint256 discount is rejected
  function testMaxUintDiscountReverts() external {
    vm.expectRevert(TranchesChainlinkOracle.DiscountTooHigh.selector);
    new TranchesChainlinkOracle(address(tranche), type(uint256).max);
  }

  /// @notice Rounding is always down, never valuing the collateral above the exact discounted price
  function testRoundingDown() external {
    // 1 * 0.95 = 0.95 -> 0
    mockCdo.setPrice(1);
    assertEq(_price(5e16), 0);
    // 3 * 0.9 = 2.7 -> 2
    mockCdo.setPrice(3);
    assertEq(_price(1e17), 2);
    // 19 * 0.95 = 18.05 -> 18
    mockCdo.setPrice(19);
    assertEq(_price(5e16), 18);
    // exact results are not changed: 20 * 0.95 = 19
    mockCdo.setPrice(20);
    assertEq(_price(5e16), 19);
  }

  /// @notice Zero discount preserves legacy pricing above the former overflow threshold and through int256.max.
  function testLargeZeroDiscountPreservesLegacyPrice() external {
    uint256 largePrice = type(uint256).max / SCALE + 1;
    mockCdo.setPrice(largePrice);
    assertEq(_price(0), largePrice);
    mockCdo.setPrice(uint256(type(int256).max));
    assertEq(_price(0), uint256(type(int256).max));
  }

  /// @notice A 5% discount succeeds above the former product limit and at the largest positive signed price.
  function testLargeDiscountedPrice() external {
    uint256 largePrice = type(uint256).max / 95e16 + 1;
    mockCdo.setPrice(largePrice);
    // Independently compute floor(19 * price / 20) as price - ceil(price / 20).
    assertEq(_price(5e16), largePrice - largePrice / 20 - (largePrice % 20 == 0 ? 0 : 1));
    largePrice = uint256(type(int256).max);
    mockCdo.setPrice(largePrice);
    assertEq(_price(5e16), largePrice - largePrice / 20 - (largePrice % 20 == 0 ? 0 : 1));
  }

  /// @notice Extreme uint256 inputs do not overflow; answers above int256.max retain the legacy signed conversion.
  function testUint256BoundaryDiscounts() external {
    uint256 maxPrice = type(uint256).max;
    mockCdo.setPrice(maxPrice);
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), 0);
    (, int256 answer,,,) = oracle.latestRoundData();
    assertEq(answer, int256(maxPrice));
    assertEq(answer, -1);
    // _price converts the returned bits back to uint256, including for the smallest discount.
    assertEq(_price(1), maxPrice - maxPrice / SCALE - 1);
    assertEq(_price(SCALE / 2), maxPrice / 2);
    assertEq(_price(SCALE - 1), maxPrice / SCALE);
  }

  /// @notice The freshly compiled oracle runtime stays below the EIP-170 contract size limit
  function testRuntimeSizeBelowEip170() external {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), 5e16);
    assertGt(address(oracle).code.length, 0);
    assertLe(address(oracle).code.length, EIP170_LIMIT);
  }

  /// @notice The deploy script entrypoint forwards the discount to the adapter used as Morpho base feed
  function testDeployOracleScriptForwardsDiscount() external {
    MockMorphoOracleFactory factory = new MockMorphoOracleFactory();
    DeployMetamorphoVault deployer = new DeployMetamorphoVault();
    assertEq(address(deployer.deployOracle(address(tranche), IMetaMorphoOracleFactory(address(factory)), 5e16)), address(factory));

    TranchesChainlinkOracle adapter = TranchesChainlinkOracle(factory.baseFeed());
    assertEq(adapter.discount(), 5e16);
    assertEq(adapter.collateralToken(), address(tranche));
    assertEq(factory.baseDecimals(), 18);
    assertEq(factory.quoteDecimals(), 6);
    (, int256 answer,,,) = adapter.latestRoundData();
    assertEq(answer, 950_000);
  }

  /// @notice Compare all discounts with direct multiplication where the independent reference cannot overflow.
  function testFuzzDiscountedPrice(uint256 virtualPrice, uint256 discount) external {
    discount = bound(discount, 0, SCALE);
    virtualPrice = bound(virtualPrice, 0, type(uint256).max / SCALE);
    mockCdo.setPrice(virtualPrice);
    uint256 price = _price(discount);
    assertEq(price, virtualPrice * (SCALE - discount) / SCALE);
    assertLe(price, virtualPrice);
  }

  /// @notice Zero discount preserves the previous int256 conversion for every uint256 virtualPrice.
  function testFuzzZeroDiscountPreservesLegacyPrice(uint256 virtualPrice) external {
    mockCdo.setPrice(virtualPrice);
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(address(tranche), 0);
    (, int256 answer,,,) = oracle.latestRoundData();
    assertEq(answer, int256(virtualPrice));
  }

  /// @notice Validate 5% pricing across the positive int256 range using subtraction and ceiling division.
  function testFuzzFivePercentLargePrice(uint256 virtualPrice) external {
    virtualPrice = bound(virtualPrice, 0, uint256(type(int256).max));
    mockCdo.setPrice(virtualPrice);
    uint256 expectedPrice = virtualPrice - virtualPrice / 20 - (virtualPrice % 20 == 0 ? 0 : 1);
    assertEq(_price(5e16), expectedPrice);
  }

  /// @notice Any discount above 100% is rejected
  function testFuzzDiscountAboveFullReverts(uint256 discount) external {
    discount = bound(discount, SCALE + 1, type(uint256).max);
    vm.expectRevert(TranchesChainlinkOracle.DiscountTooHigh.selector);
    new TranchesChainlinkOracle(address(tranche), discount);
  }
}
