// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {TranchesChainlinkOracle} from "../../contracts/strategies/morpho/TranchesChainlinkOracle.sol";
import {IMorphoChainlinkOracleV2} from "../../contracts/interfaces/morpho/IMorphoChainlinkOracleV2.sol";
import { DeployMetamorphoVault } from "../../forge-scripts/DeployMetamorphoVault.s.sol";

import {IChainalysisSanctionsList, KeyringIdleWhitelist} from "../../contracts/KeyringIdleWhitelist.sol";
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

contract TestTranchesChainlinkOracle is Test {
  uint256 internal constant SCALE = 1e18;
  uint256 internal constant ONE = 1e6;
  uint256 internal constant EIP170_LIMIT = 24576;
  uint256 internal constant FORK_BLOCK = 22_525_130;
  address internal constant CHAINALYSIS_SANCTIONS = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;
  address internal constant LEGACY_KEYRING_WHITELIST = 0x6a6A91c7c7C05f9f6B8bC9F6e5eA231e460450e3;
  uint256 internal constant KEYRING_POLICY = 4;
  uint256 internal constant KEYRING_FORK_BLOCK = 26_290_277;
  uint256 internal constant BEFORE_RONIN_SANCTION = 14_500_000;

  IIdleCDO internal oracleCdo;
  address internal trancheToken;

  /// @notice Uses the deployed Fasanara USDC CDO and its AA tranche on the repository's mainnet endpoint.
  function setUp() public {
    vm.createSelectFork("mainnet", FORK_BLOCK);
    oracleCdo = IIdleCDO(0xf6223C567F21E33e859ED7A045773526E9E3c2D5);
    trancheToken = oracleCdo.AATranche();
  }

  /// @notice Blacklisting revokes a stored grant and overrides a valid underlying credential.
  function testKeyringBlacklistRevokesWhitelist() external {
    vm.rollFork(KEYRING_FORK_BLOCK);
    KeyringIdleWhitelist adapter = new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
    address lender = makeAddr("blacklisted lender");
    _grantLegacyKeyringAccess(lender);

    adapter.setWhitelistStatus(lender, true);
    assertTrue(adapter.whitelist(lender));
    assertTrue(adapter.checkCredential(KEYRING_POLICY, lender));

    vm.expectRevert(abi.encodeWithSelector(KeyringIdleWhitelist.NotAdmin.selector, lender));
    vm.prank(lender);
    adapter.setBlacklistStatus(lender, true);

    adapter.setBlacklistStatus(lender, true);
    assertTrue(adapter.blacklist(lender));
    assertFalse(adapter.whitelist(lender));
    assertFalse(adapter.checkCredential(KEYRING_POLICY, lender));

    adapter.setWhitelistStatus(lender, true);
    assertFalse(adapter.whitelist(lender));

    adapter.setBlacklistStatus(lender, false);
    assertFalse(adapter.blacklist(lender));
    assertFalse(adapter.whitelist(lender));
    assertTrue(adapter.checkCredential(KEYRING_POLICY, lender));
  }

  /// @notice Sanctions deny eligibility even before anyone syncs the stored flag.
  function testKeyringSanctionsDenyAndSyncWhitelist() external {
    uint256 postSanctionFork = vm.activeFork();
    vm.createSelectFork("mainnet", BEFORE_RONIN_SANCTION);
    KeyringIdleWhitelist adapter = new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
    address roninWallet = 0x098B716B8Aaf21512996dC57EB0615e2383E2f96;

    adapter.setWhitelistStatus(roninWallet, true);
    assertTrue(adapter.checkCredential(KEYRING_POLICY, roninWallet));

    // Carry the local grant forward and read the actual sanctions listing at the later block.
    vm.makePersistent(address(adapter));
    vm.selectFork(postSanctionFork);
    IChainalysisSanctionsList sanctions = IChainalysisSanctionsList(CHAINALYSIS_SANCTIONS);
    assertTrue(sanctions.isSanctioned(roninWallet), "fixture wallet must be sanctioned");

    assertFalse(adapter.blacklist(roninWallet));
    assertFalse(adapter.checkCredential(KEYRING_POLICY, roninWallet));
    assertTrue(adapter.whitelist(roninWallet));

    vm.prank(makeAddr("sanctions sync caller"));
    adapter.syncSanctions(roninWallet);
    assertFalse(adapter.whitelist(roninWallet));
    assertFalse(adapter.blacklist(roninWallet));
    assertFalse(adapter.checkCredential(KEYRING_POLICY, roninWallet));

    adapter.setWhitelistStatus(roninWallet, true);
    assertFalse(adapter.whitelist(roninWallet), "admin cannot restore a grant during a listing");
  }

  /// @notice Unflagged wallets retain the existing whitelist and Keyring credential results.
  function testKeyringPreservesUnflaggedEligibility() external {
    vm.rollFork(KEYRING_FORK_BLOCK);
    KeyringIdleWhitelist adapter = new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
    address credentialed = makeAddr("credentialed lender");
    address lender = makeAddr("uncredentialed lender");
    _grantLegacyKeyringAccess(credentialed);

    assertFalse(adapter.whitelist(credentialed));
    assertTrue(adapter.checkCredential(KEYRING_POLICY, credentialed));
    assertFalse(adapter.checkCredential(KEYRING_POLICY, lender));

    adapter.setWhitelistStatus(lender, true);
    adapter.syncSanctions(lender);
    assertTrue(adapter.whitelist(lender));
    assertTrue(adapter.checkCredential(KEYRING_POLICY, lender));
  }

  /// @notice The adapter rejects Base before using even a responsive oracle at the Ethereum address.
  function testKeyringDeploymentRejectsUnsupportedNetwork() external {
    vm.chainId(8453);

    vm.expectRevert(abi.encodeWithSelector(KeyringIdleWhitelist.UnsupportedSanctionsNetwork.selector, uint256(8453)));
    new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
  }

  /// @notice A supported network still requires an available oracle at construction.
  function testKeyringDeploymentRejectsMissingOracle() external {
    vm.etch(CHAINALYSIS_SANCTIONS, hex"");

    vm.expectRevert();
    new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
  }

  /// @notice A response with the wrong ABI cannot satisfy the deployment probe.
  function testKeyringDeploymentRejectsInvalidOracleResponse() external {
    vm.mockCall(
      CHAINALYSIS_SANCTIONS,
      abi.encodeWithSelector(IChainalysisSanctionsList.isSanctioned.selector, address(0)),
      abi.encode(uint256(2))
    );

    vm.expectRevert();
    new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
  }

  /// @notice An oracle failure blocks grants while the admin can still revoke a stored grant.
  function testKeyringRevocationWorksWithoutOracle() external {
    KeyringIdleWhitelist adapter = new KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST, address(this));
    address lender = makeAddr("lender with a stored grant");
    adapter.setWhitelistStatus(lender, true);
    assertTrue(adapter.whitelist(lender));

    vm.etch(CHAINALYSIS_SANCTIONS, hex"");
    adapter.setWhitelistStatus(lender, false);
    assertFalse(adapter.whitelist(lender));

    vm.expectRevert();
    adapter.setWhitelistStatus(lender, true);
    assertFalse(adapter.whitelist(lender));
  }

  /// @dev Grants an eligible underlying credential through the deployed mainnet adapter on the fork.
  function _grantLegacyKeyringAccess(address entity) private {
    KeyringIdleWhitelist legacyAdapter = KeyringIdleWhitelist(LEGACY_KEYRING_WHITELIST);
    assertGt(address(legacyAdapter).code.length, 0, "legacy whitelist must be deployed");
    vm.prank(legacyAdapter.admin());
    legacyAdapter.setWhitelistStatus(entity, true);
    assertTrue(legacyAdapter.whitelist(entity), "legacy whitelist must grant the test credential");
  }

  /// @dev Deploys the oracle with the selected discount and returns its current price.
  function _price(uint256 discount) internal returns (uint256) {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(trancheToken, discount);
    (, int256 answer,,,) = oracle.latestRoundData();
    return uint256(answer);
  }

  /// @dev Supplies exact prices unavailable at the pinned fork for deterministic rounding and price-change cases.
  function _mockVirtualPrice(uint256 virtualPrice) internal {
    vm.mockCall(
      address(oracleCdo),
      abi.encodeWithSelector(IIdleCDO.virtualPrice.selector, trancheToken),
      abi.encode(virtualPrice)
    );
  }

  /// @notice Constructor wires the deployed contracts and preserves the 6-decimal loan token scaling.
  function testConstructor() external {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(trancheToken, 5e16);
    assertEq(oracle.collateralToken(), trancheToken);
    assertEq(address(oracle.cdo()), address(oracleCdo));
    assertEq(oracle.loanToken(), oracleCdo.token());
    assertEq(oracle.loanTokenDecimals(), 6);
    assertEq(oracle.decimals(), 6);
    assertEq(oracle.discount(), 5e16);
    assertEq(oracle.DISCOUNT_SCALE(), SCALE);
  }

  /// @notice A zero discount returns the deployed CDO's virtualPrice unchanged.
  function testZeroDiscountReturnsVirtualPrice() external {
    uint256 virtualPrice = oracleCdo.virtualPrice(trancheToken);
    assertGt(virtualPrice, 0);
    assertEq(_price(0), virtualPrice);
  }

  /// @notice A 5% discount prices the real USDC tranche at 95% of its virtualPrice, rounded down.
  function testFivePercentDiscount() external {
    uint256 virtualPrice = oracleCdo.virtualPrice(trancheToken);
    assertGt(virtualPrice, 0);
    assertEq(_price(5e16), virtualPrice * 95 / 100);
  }

  /// @notice The exact 1.0 to 0.95 example uses the deployed token's 6 decimals.
  function testFivePercentDiscountAtUnitPrice() external {
    _mockVirtualPrice(ONE);
    assertEq(_price(5e16), 950_000);
  }

  /// @notice An existing oracle reads the new virtualPrice when the CDO's price changes.
  function testDiscountTracksVirtualPrice() external {
    _mockVirtualPrice(ONE);
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(trancheToken, 5e16);
    (, int256 beforeAnswer,,,) = oracle.latestRoundData();
    assertEq(beforeAnswer, 950_000);
    _mockVirtualPrice(1_100_000);
    (, int256 afterAnswer,,,) = oracle.latestRoundData();
    assertEq(afterAnswer, 1_045_000);
  }

  /// @notice Zero and 5% discounts preserve the deployed Lido tranche's 18-decimal loan token scaling.
  function testDiscountWith18DecimalsLoanToken() external {
    // The Lido CDO is registered in utils/addresses.js.
    IIdleCDO lidoCdo = IIdleCDO(0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8);
    address lidoTranche = lidoCdo.AATranche();
    uint256 virtualPrice = lidoCdo.virtualPrice(lidoTranche);
    assertGt(virtualPrice, 0);

    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(lidoTranche, 5e16);
    (, int256 answer,,,) = oracle.latestRoundData();
    assertEq(oracle.loanToken(), lidoCdo.token());
    assertEq(oracle.decimals(), 18);
    assertEq(uint256(answer), virtualPrice * 95 / 100);

    TranchesChainlinkOracle undiscounted = new TranchesChainlinkOracle(lidoTranche, 0);
    (, int256 undiscountedAnswer,,,) = undiscounted.latestRoundData();
    assertEq(uint256(undiscountedAnswer), virtualPrice);
  }

  /// @notice A 100% discount is accepted and prices the real collateral at zero.
  function testFullDiscountIsAccepted() external {
    assertEq(_price(SCALE), 0);
  }

  /// @notice The smallest discount rounds the real USDC tranche's positive price down by one unit.
  function testSmallestDiscountRoundsDown() external {
    uint256 virtualPrice = oracleCdo.virtualPrice(trancheToken);
    assertGt(virtualPrice, 0);
    assertLt(virtualPrice, SCALE);
    assertEq(_price(1), virtualPrice - 1);
  }

  /// @notice The largest discount below 100% rounds the real USDC tranche's price down to zero.
  function testLargestDiscountBelowFull() external {
    assertLt(oracleCdo.virtualPrice(trancheToken), SCALE);
    assertEq(_price(SCALE - 1), 0);
  }

  /// @notice Discounts above 100% are rejected.
  function testDiscountAboveFullReverts() external {
    vm.expectRevert(TranchesChainlinkOracle.DiscountTooHigh.selector);
    new TranchesChainlinkOracle(trancheToken, SCALE + 1);
  }

  /// @notice The maximum uint256 discount is rejected.
  function testMaxUintDiscountReverts() external {
    vm.expectRevert(TranchesChainlinkOracle.DiscountTooHigh.selector);
    new TranchesChainlinkOracle(trancheToken, type(uint256).max);
  }

  /// @notice Exact fractional prices round down, and exact integer results remain unchanged.
  function testRoundingDown() external {
    _mockVirtualPrice(1); // 1 * 0.95 = 0.95 -> 0
    assertEq(_price(5e16), 0);
    _mockVirtualPrice(3); // 3 * 0.9 = 2.7 -> 2
    assertEq(_price(1e17), 2);
    _mockVirtualPrice(19); // 19 * 0.95 = 18.05 -> 18
    assertEq(_price(5e16), 18);
    _mockVirtualPrice(20); // 20 * 0.95 = 19 exactly
    assertEq(_price(5e16), 19);
  }

  /// @notice The freshly compiled oracle runtime fits within the EIP-170 contract size limit.
  function testRuntimeSizeBelowEip170() external {
    TranchesChainlinkOracle oracle = new TranchesChainlinkOracle(trancheToken, 5e16);
    assertGt(address(oracle).code.length, 0);
    assertLe(address(oracle).code.length, EIP170_LIMIT);
  }

  /// @notice The script forwards the discount into a working Morpho oracle deployed through the real factory.
  function testDeployOracleScriptForwardsDiscount() external {
    DeployMetamorphoVault deployer = new DeployMetamorphoVault();
    assertGt(address(deployer.ORACLE_FACTORY()).code.length, 0);
    IMorphoChainlinkOracleV2 marketOracle = deployer.deployOracle(trancheToken, deployer.ORACLE_FACTORY(), 5e16);
    assertGt(address(marketOracle).code.length, 0);

    TranchesChainlinkOracle adapter = TranchesChainlinkOracle(address(marketOracle.BASE_FEED_1()));
    assertEq(adapter.discount(), 5e16);
    assertEq(adapter.collateralToken(), trancheToken);
    assertEq(adapter.loanTokenDecimals(), 6);
    assertEq(IERC20Detailed(trancheToken).decimals(), 18);
    // Morpho scales the 6-decimal feed for an 18-decimal collateral and a 6-decimal loan token.
    assertEq(marketOracle.SCALE_FACTOR(), 1e18);
    uint256 expectedPrice = oracleCdo.virtualPrice(trancheToken) * 95 / 100;
    (, int256 answer,,,) = adapter.latestRoundData();
    assertEq(uint256(answer), expectedPrice);
    assertEq(marketOracle.price(), expectedPrice * 1e18);
  }

  /// @notice Any valid discount on the deployed tranche agrees with subtracting the rounded-up discount.
  function testFuzzDiscountedPrice(uint256 discount) external {
    discount = bound(discount, 0, SCALE);
    uint256 virtualPrice = oracleCdo.virtualPrice(trancheToken);
    uint256 reduction = virtualPrice * discount;
    uint256 expectedPrice = virtualPrice - reduction / SCALE - (reduction % SCALE == 0 ? 0 : 1);
    assertEq(_price(discount), expectedPrice);
  }

  /// @notice Any discount above 100% is rejected.
  function testFuzzDiscountAboveFullReverts(uint256 discount) external {
    discount = bound(discount, SCALE + 1, type(uint256).max);
    vm.expectRevert(TranchesChainlinkOracle.DiscountTooHigh.selector);
    new TranchesChainlinkOracle(trancheToken, discount);
  }
}
