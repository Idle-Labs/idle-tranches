// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/ICToken.sol";
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/strategies/idle/IdleStrategy.sol";
import "../../contracts/IdleTokenFungible.sol";
import "../../contracts/IdleCDO.sol";
import "./TestIdleCDOBase.sol";
import "../../contracts/interfaces/IProxyAdmin.sol";
import "forge-std/Test.sol";

contract TestIdleCDODefaultMgmt is Test {
  using stdStorage for StdStorage;
  using SafeERC20Upgradeable for IERC20Detailed;

  // Idle-USDC Best-Yield v4
  address internal constant UNDERLYING = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant idleToken = 0x5274891bEC421B39D23760c04A6755eCB444797C;
  address internal constant idleTokenJunior = 0xDc7777C771a6e4B3A82830781bDDe4DBC78f320e;
  address internal constant aToken = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
  address internal constant maToken = 0xA5269A8e31B93Ff27B887B56720A25F844db0529;
  address internal constant cdo = 0xf615a552c000B114DdAa09636BBF4205De49333c;

  // uint256 internal constant BLOCK_FOR_TEST = 16818361; // pre Euler pause otherwise revert
  uint256 internal constant BLOCK_FOR_TEST = 16814098; // pre Euler hack
  IdleCDO public idleCDO = IdleCDO(cdo);
  IdleTokenFungible public _idleToken = IdleTokenFungible(idleToken);
  IdleTokenFungible public _idleTokenJunior = IdleTokenFungible(idleTokenJunior);
  uint256 public initialContractValue;

  function setUp() public virtual {
    _forkAt(BLOCK_FOR_TEST);

    deal(UNDERLYING, address(this), 101_000 * 1e6);
    IERC20Detailed(UNDERLYING).approve(cdo, type(uint256).max);
    idleCDO.depositAA(100_000 * 1e6);
    idleCDO.depositBB(1_000 * 1e6);

    // set all allocations to aave (cUSDC is paused at this block)
    uint256[] memory allocs = new uint256[](3);
    (allocs[0], allocs[1], allocs[2]) = (0, 100000, 0);
    vm.prank(_idleToken.rebalancer());
    _idleToken.setAllocations(allocs);

    // set all allocations to morpho aave
    uint256[] memory allocsJun = new uint256[](2);
    (allocsJun[0], allocsJun[1]) = (0, 100000);
    vm.prank(_idleTokenJunior.rebalancer());
    _idleTokenJunior.setAllocations(allocsJun);

    initialContractValue = idleCDO.getContractValue();

    // trigger shutdown and pause on BY to simulate last state
    vm.prank(idleCDO.owner());
    idleCDO.emergencyShutdown();
  }

  function _forkAt(uint256 _block) internal {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _block));
  }

  function _upgradeContract(address proxy, address newInstance) internal {
    // Upgrade the proxy to the new contract
    IProxyAdmin admin = IProxyAdmin(0x9438904ABC7d8944A6E2A89671fEf51C629af351);
    vm.prank(admin.owner());
    admin.upgrade(proxy, newInstance);
  }

  function testSetRedemptioRates() external {
    _upgradeContract(cdo, address(new IdleCDO()));
    IIdleCDOStrategy strategy = IIdleCDOStrategy(IdleCDO(cdo).strategy());

    // now let's simulate a loss by decreasing strategy price
    // curr price - ~50%
    vm.mockCall(
      address(strategy),
      abi.encodeWithSelector(IIdleCDOStrategy.price.selector),
      abi.encode(5e5) // 0.5 underlyings
    );

    uint256 postAAPrice = idleCDO.virtualPrice(idleCDO.AATranche());
    uint256 postBBPrice = idleCDO.virtualPrice(idleCDO.BBTranche());
    assertEq(idleCDO.priceAA(), postAAPrice, 'AA price changed');
    assertEq(idleCDO.priceBB(), postBBPrice, 'BB price changed');

    vm.startPrank(idleCDO.owner());
    idleCDO.setRedemptionRates();
    idleCDO.setAllowAAWithdraw(true);
    idleCDO.setAllowBBWithdraw(true);
    vm.stopPrank();

    uint256 redemptionRateAA = idleCDO.virtualPrice(idleCDO.AATranche());
    uint256 redemptionRateBB = idleCDO.virtualPrice(idleCDO.BBTranche());

    // assertLt(redemptionRateAA, postAAPrice, 'AA did not decrease');
    assertApproxEqAbs(
      redemptionRateAA, 
      postAAPrice / 2,
      1e5, // 0.1 underlyings so price between ~0.4 and ~0.6 
      'AA did not decrease'
    );
    // seniors are way more than juniors
    assertEq(redemptionRateBB, 0, 'BB should be 0');

    // test multiple redeems AA
    // redeem with BY
    vm.roll(block.number + 1);
    uint256 balPre = IERC20Detailed(aToken).balanceOf(idleToken);
    _idleToken.rebalance();
    // all balance is now in aave 
    uint256 balPost = IERC20Detailed(aToken).balanceOf(idleToken);
    // aToken price is 1, we had about 4.6M so with a tokenPrice of 0.5 we should have 2.3M
    assertApproxEqAbs(balPost - balPre, initialContractValue / 2, 50_000 * 1e6, 'aToken bal is not half the initial val');
    // tranche price should not change
    assertEq(idleCDO.priceAA(), redemptionRateAA, 'AA price changed');
    assertEq(idleCDO.priceBB(), redemptionRateBB, 'BB price changed');

    vm.clearMockedCalls();

    // We now simulate and increase in eToken price to test
    // curr price - ~10%
    vm.mockCall(
      address(strategy),
      abi.encodeWithSelector(IIdleCDOStrategy.price.selector),
      abi.encode(9e5) // 0.9 underlyings
    );

    vm.roll(block.number + 1);
    // test another redeem AA (we deposited 100k on setUp)
    balPre = IERC20Detailed(UNDERLYING).balanceOf(address(this));
    idleCDO.withdrawAA(0);
    balPost = IERC20Detailed(UNDERLYING).balanceOf(address(this));
    assertApproxEqAbs(balPost - balPre, 50_000 * 1e6, 5_000 * 1e6, 'underlying bal is not 0.5M');

    // tranche price should not change
    assertEq(idleCDO.priceAA(), redemptionRateAA, 'AA price changed');
    assertEq(idleCDO.priceBB(), redemptionRateBB, 'BB price changed');

    // test multiple redeem BB
    vm.roll(block.number + 1);

    // redeem with BY junior
    balPre = IERC20Detailed(maToken).balanceOf(idleTokenJunior);
    _idleTokenJunior.rebalance();
    balPost = IERC20Detailed(maToken).balanceOf(idleTokenJunior);
    assertEq(balPost - balPre, 0, 'maToken bal diff should be 0');

    // redeem with this contract
    balPre = IERC20Detailed(UNDERLYING).balanceOf(address(this));
    idleCDO.withdrawBB(0);
    balPost = IERC20Detailed(UNDERLYING).balanceOf(address(this));
    assertEq(balPost - balPre, 0, 'juniors bal diff should be 0');

    vm.clearMockedCalls();
  }
}
