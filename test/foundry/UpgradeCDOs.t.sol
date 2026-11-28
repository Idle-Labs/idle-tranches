// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IIdleCDOStrategy} from "../../contracts/interfaces/IIdleCDOStrategy.sol";
import {GuardedLaunchUpgradable} from "../../contracts/GuardedLaunchUpgradable.sol";
import {IdleCDO} from "../../contracts/IdleCDO.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IProxyAdmin} from "../../contracts/interfaces/IProxyAdmin.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract TestQuickCDO is Test {
  using SafeERC20Upgradeable for IERC20Detailed;

  // Governance recovery fund configured on both forked proxies.
  address internal constant RECOVERY_FUND = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

  /// @notice Check recovery after upgrading the deployed Morpho USDC CDO.
  function testLegacyCDOTokenRecoveryAfterUpgrade() external {
    vm.createSelectFork("mainnet", 18412406);
    _testTokenRecoveryAfterUpgrade(IdleCDO(0x9C13Ff045C0a994AF765585970A5818E1dB580F8), address(new IdleCDO()));
  }

  /// @notice Check recovery after upgrading a deployed USDC Credit Vault.
  function testCreditVaultTokenRecoveryAfterUpgrade() external {
    vm.createSelectFork("mainnet", 26272200);
    _testTokenRecoveryAfterUpgrade(
      IdleCDO(0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d), address(new IdleCDOEpochVariant())
    );
  }

  /// @notice Verify the proxy retains its recovery configuration and protects the funded strategy position.
  function _testTokenRecoveryAfterUpgrade(IdleCDO cdo, address implementation) internal {
    address cdoAddress = address(cdo);
    address vaultOwner = cdo.owner();
    IERC20Detailed position = IERC20Detailed(cdo.strategyToken());
    IERC20Detailed cash = IERC20Detailed(cdo.token());
    uint256 positionBalance = position.balanceOf(cdoAddress);
    uint256 fundPositionBalance = position.balanceOf(RECOVERY_FUND);
    assertGt(positionBalance, 0, "fork vault must hold strategy tokens");

    assertLe(implementation.code.length, 24_576, "implementation exceeds EIP-170");
    _upgradeContract(cdoAddress, implementation);
    assertEq(cdo.owner(), vaultOwner, "owner changed on upgrade");
    assertEq(cdo.strategyToken(), address(position), "strategy token changed on upgrade");
    assertEq(cdo.token(), address(cash), "underlying changed on upgrade");

    vm.expectRevert(GuardedLaunchUpgradable.StrategyTokenProtected.selector);
    vm.prank(vaultOwner);
    cdo.transferToken(address(position), 1);
    assertEq(position.balanceOf(cdoAddress), positionBalance, "vault strategy balance changed");
    assertEq(position.balanceOf(RECOVERY_FUND), fundPositionBalance, "fund strategy balance changed");

    uint256 cashBalance = cash.balanceOf(cdoAddress);
    uint256 fundCashBalance = cash.balanceOf(RECOVERY_FUND);
    uint256 recoveryAmount = 1e6;
    deal(address(cash), cdoAddress, cashBalance + recoveryAmount, true);

    vm.expectRevert(GuardedLaunchUpgradable.NotAuthorized.selector);
    vm.prank(makeAddr("nonOwner"));
    cdo.transferToken(address(cash), recoveryAmount);
    assertEq(cash.balanceOf(cdoAddress), cashBalance + recoveryAmount, "non-owner moved vault cash");
    assertEq(cash.balanceOf(RECOVERY_FUND), fundCashBalance, "non-owner moved fund cash");

    vm.prank(vaultOwner);
    cdo.transferToken(address(cash), recoveryAmount);
    assertEq(cash.balanceOf(cdoAddress), cashBalance, "vault kept recovered cash");
    assertEq(cash.balanceOf(RECOVERY_FUND), fundCashBalance + recoveryAmount, "fund did not receive recovered cash");
  }

  function testAllCDOPrices() external {
    address[] memory cdos = new address[](10);
    // lido
    // cdos[0] = 0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8; // vm.deal not working
    // clearpool
    cdos[1] = 0x1329E8DB9Ed7a44726572D44729427F132Fa290D;
    cdos[2] = 0x5dcA0B3Ed7594A6613c1A2acd367d56E1f74F92D;
    cdos[3] = 0xc4574C60a455655864aB80fa7638561A756C5E61;
    cdos[4] = 0xE7C6A4525492395d65e736C3593aC933F33ee46e;
    cdos[5] = 0xd12f9248dEb1D972AA16022B399ee1662d51aD22;
    // morpho
    cdos[6] = 0x9C13Ff045C0a994AF765585970A5818E1dB580F8;
    cdos[7] = 0xDB82dDcb7e2E4ac3d13eBD1516CBfDb7b7CE0ffc;
    cdos[8] = 0x440ceAd9C0A0f4ddA1C81b892BeDc9284Fc190dd;
    cdos[9] = 0xb3F717a5064D2CBE1b8999Fdfd3F8f3DA98339a6;

    for (uint256 i = 0; i < cdos.length; i++) {
      if (cdos[i] == address(0)) continue;
      _testPrices(cdos[i]);
    }
  }

  function _testPrices(address addr) internal {
    // fork
    uint256 _block = 18412406;
    address newImpl = 0xc9f019Fa138Ba4FAc3B4e400705FbDD75B20Af8c;
    vm.createSelectFork("mainnet", _block);
    // setup pre deposits
    IdleCDO cdo = IdleCDO(addr);
    IIdleCDOStrategy strategy = IIdleCDOStrategy(cdo.strategy());
    address AA = cdo.AATranche();
    address BB = cdo.BBTranche();
    IERC20Detailed token = IERC20Detailed(cdo.token());
    // check prices pre
    console.log('########## Pre ', addr);
    uint256 preAA = cdo.virtualPrice(AA);
    uint256 preBB = cdo.virtualPrice(BB);
    uint256 preStrategy = strategy.price();
    console.log('tranchePriceAA', preAA);
    console.log('tranchePriceBB', preBB);
    console.log('strategyPrice ', preStrategy);
    // upgrade contract
    _upgradeContract(address(cdo), newImpl);
    // test user deposit
    address usr = makeAddr('user');
    uint256 amount = 2 * 10**(token.decimals());
    deal(cdo.token(), usr, amount);
    vm.startPrank(usr);
    token.safeApprove(address(cdo), amount);
    cdo.depositAA(amount / 2);
    cdo.depositBB(amount / 2);
    skip(1 days);
    vm.roll(block.number + 6400);
    cdo.withdrawAA(0);
    cdo.withdrawBB(0);
    vm.stopPrank();
    assertGe(token.balanceOf(usr), amount - 2, 'Amount >=');

    // check prices post
    console.log('########## Pos ', addr);
    uint256 postAA = cdo.virtualPrice(AA);
    uint256 postBB = cdo.virtualPrice(BB);
    uint256 postStrategy = strategy.price();
    
    int256 diffAA = int256(postAA) - int256(preAA);
    int256 diffBB = int256(postBB) - int256(preBB);
    int256 diffStrategy = int256(postStrategy) - int256(preStrategy);
    
    console.log('tranchePriceAA', postAA, diffAA > 0 ? 'Diff   +' : 'Diff   -', diffAA > 0 ? uint256(diffAA) : uint256(-diffAA));
    console.log('tranchePriceBB', postBB, diffBB > 0 ? 'Diff   +' : 'Diff   -', diffBB > 0 ? uint256(diffBB) : uint256(-diffBB));
    console.log('strategyPrice ', postStrategy, diffStrategy > 0 ? 'Diff   +' : 'Diff   -', diffStrategy > 0 ? uint256(diffStrategy) : uint256(-diffStrategy));
    assertGe(postAA, preAA, 'AA Price not increasing');
    assertGe(postBB, preBB, 'BB Price not increasing');
    console.log('--------------');
  }

  function _logDiff(uint256 pre, uint256 post, string memory label) internal view {
    int256 diff = int256(post) - int256(pre);
    console.log(label, diff > 0 ? 'Diff   +' : 'Diff   -', diff > 0 ? uint256(diff) : uint256(-diff));
  }

  function _upgradeContract(address proxy, address newInstance) internal {
    // Upgrade the proxy to the new contract
    IProxyAdmin admin = IProxyAdmin(0x9438904ABC7d8944A6E2A89671fEf51C629af351);
    vm.prank(admin.owner());
    admin.upgrade(proxy, newInstance);
  }
}