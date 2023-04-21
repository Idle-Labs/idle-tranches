// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/strategies/idle/IdleStrategy.sol";
import "../../contracts/strategies/euler/IdleEulerStakingStrategy.sol";
import "../../contracts/strategies/euler/IdleEulerStrategy.sol";
import "../../contracts/IdleTokenFungible.sol";
import "../../contracts/IdleCDO.sol";
import "./TestIdleCDOBase.sol";
import "../../contracts/interfaces/IProxyAdmin.sol";
import "forge-std/Test.sol";

contract TestIdleCDODefaultMgmt is Test {
  using stdStorage for StdStorage;
  using SafeERC20Upgradeable for IERC20Detailed;

  // Idle-USDC Best-Yield v4
  address internal constant DEV_MULTISIG = 0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b;
  address internal constant GUARDIAN_MULTISIG = 0xaDa343Cb6820F4f5001749892f6CAA9920129F2A;  
  uint256 internal constant PRE_EULER_PAUSE = 16818362; // pre hack
  uint256 internal constant BLOCK_FOR_TEST = 17065314; // post recovery
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address internal constant AGEUR = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;

  function setUp() public virtual {
    _forkAt(PRE_EULER_PAUSE);
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

  function testRedeemsUSDCStaking() public {
    uint256 amount = 4667395913064; // eulerusdcstaking PYT
    address cdo = 0xf615a552c000B114DdAa09636BBF4205De49333c;
    address idleTokenSenior = 0x5274891bEC421B39D23760c04A6755eCB444797C;
    address idleTokenJunior = 0xDc7777C771a6e4B3A82830781bDDe4DBC78f320e;

    IdleCDO idleCDO = IdleCDO(cdo);
    IdleTokenFungible _idleToken = IdleTokenFungible(idleTokenSenior);
    IdleTokenFungible _idleTokenJunior = IdleTokenFungible(idleTokenJunior);

    // set all allocations to aave
    uint256[] memory allocs = new uint256[](3);
    (allocs[0], allocs[1], allocs[2]) = (0, 100000, 0);
    vm.prank(_idleToken.rebalancer());
    _idleToken.setAllocations(allocs);

    // set all allocations to morpho aave
    uint256[] memory allocsJun = new uint256[](2);
    (allocsJun[0], allocsJun[1]) = (0, 100000);
    vm.prank(_idleTokenJunior.rebalancer());
    _idleTokenJunior.setAllocations(allocsJun);
  
    _genericRedeemStakingTest(USDC, amount, idleCDO, _idleToken, _idleTokenJunior);
  }

  function testRedeemsUSDTStaking() public {
    uint256 amount = 458120705798; // eulerusdtstaking PYT
    address cdo = 0x860B1d25903DbDFFEC579d30012dA268aEB0d621;
    address idleTokenSenior = 0xF34842d05A1c888Ca02769A633DF37177415C2f8;
    address idleTokenJunior = 0xfa3AfC9a194BaBD56e743fA3b7aA2CcbED3eAaad;

    IdleCDO idleCDO = IdleCDO(cdo);
    IdleTokenFungible _idleToken = IdleTokenFungible(idleTokenSenior);
    IdleTokenFungible _idleTokenJunior = IdleTokenFungible(idleTokenJunior);

    // set all allocations to aave
    uint256[] memory allocs = new uint256[](3);
    (allocs[0], allocs[1], allocs[2]) = (0, 100000, 0);
    vm.prank(_idleToken.rebalancer());
    _idleToken.setAllocations(allocs);

    // set all allocations to morpho aave
    uint256[] memory allocsJun = new uint256[](2);
    (allocsJun[0], allocsJun[1]) = (0, 100000);
    vm.prank(_idleTokenJunior.rebalancer());
    _idleTokenJunior.setAllocations(allocsJun);
  
    _genericRedeemStakingTest(USDT, amount, idleCDO, _idleToken, _idleTokenJunior);
  }

  function testRedeemsWETHStaking() public {
    uint256 amount = 321324195182366363917; // eulerwethstaking PYT
    address cdo = 0xec964d06cD71a68531fC9D083a142C48441F391C;
    address idleTokenSenior = 0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80;
    address idleTokenJunior = 0x62A0369c6BB00054E589D12aaD7ad81eD789514b;

    IdleCDO idleCDO = IdleCDO(cdo);
    IdleTokenFungible _idleToken = IdleTokenFungible(idleTokenSenior);
    IdleTokenFungible _idleTokenJunior = IdleTokenFungible(idleTokenJunior);

    // set all allocations to aave
    uint256[] memory allocs = new uint256[](3);
    (allocs[0], allocs[1], allocs[2]) = (0, 100000, 0);
    vm.prank(_idleToken.rebalancer());
    _idleToken.setAllocations(allocs);

    // set all allocations to morpho aave
    uint256[] memory allocsJun = new uint256[](2);
    (allocsJun[0], allocsJun[1]) = (0, 100000);
    vm.prank(_idleTokenJunior.rebalancer());
    _idleTokenJunior.setAllocations(allocsJun);
  
    _genericRedeemStakingTest(WETH, amount, idleCDO, _idleToken, _idleTokenJunior);
  }

  function testRedeemsUSDC() public {
    uint256 amount = 39572620928; // eulerusdc PYT
    address cdo = 0xF5a3d259bFE7288284Bd41823eC5C8327a314054;
    address[] memory users = new address[](2);
    (users[0], users[1]) = (
      0x442Aea0Fd2AFbd3391DAE768F7046f132F0a6300, 
      0x3F0a27C1bFF8e1AcaB07e688E52406Ab9c326be5
    );
    _genericRedeemTest(USDC, amount, IdleCDO(cdo), users);
  }

  function testRedeemsUSDT() public {
    uint256 amount = 1121131420; // eulerusdt PYT
    address cdo = 0xD5469DF8CA36E7EaeDB35D428F28E13380eC8ede;
    address[] memory users = new address[](2);
    (users[0], users[1]) = (
      0x442Aea0Fd2AFbd3391DAE768F7046f132F0a6300, 
      0x8997e31E7E93b8B7E70A157F42CD44B2eFD78220
    );
    _genericRedeemTest(USDT, amount, IdleCDO(cdo), users);
  }

  function testRedeemsDAI() public {
    uint256 amount = 669187816235681547267; // eulerusdc PYT
    address cdo = 0x46c1f702A6aAD1Fd810216A5fF15aaB1C62ca826;
    address[] memory users = new address[](2);
    (users[0], users[1]) = (
      0x442Aea0Fd2AFbd3391DAE768F7046f132F0a6300, 
      0xc286b8926c15E2509629f2209C2D57dec12E4ff8
    );
    _genericRedeemTest(DAI, amount, IdleCDO(cdo), users);
  }

  function testRedeemsAGEUR() public {
    uint256 amount = 250297909170804501147234; // eulerusdc PYT
    address cdo = 0x2398Bc075fa62Ee88d7fAb6A18Cd30bFf869bDa4;
    address[] memory users = new address[](2);
    (users[0], users[1]) = (
      0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8, 
      0x442Aea0Fd2AFbd3391DAE768F7046f132F0a6300
    );
    _genericRedeemTest(AGEUR, amount, IdleCDO(cdo), users);
  }

  function _genericRedeemTest(
    address under, 
    uint256 amount, 
    IdleCDO idleCDO,
    address[] memory users
  ) internal {
    address AA = idleCDO.AATranche();
    address BB = idleCDO.BBTranche();
    // fetch prices pre hack
    uint256 preAAPrice = idleCDO.virtualPrice(AA);
    uint256 preBBPrice = idleCDO.virtualPrice(BB);

    // fetch user tranches value before hack 
    uint256[] memory preUserAA = new uint256[](users.length);
    uint256[] memory preUserBB = new uint256[](users.length);
    for (uint256 i = 0; i < users.length; i++) {
      preUserAA[i] = IERC20Detailed(AA).balanceOf(users[i]) * preAAPrice / 1e18;
      preUserBB[i] = IERC20Detailed(BB).balanceOf(users[i]) * preBBPrice / 1e18;
    }

    // for at current block, post hack
    _forkAt(BLOCK_FOR_TEST);

    // Upgrade strategy. strategy price and apr will be set to 0
    _upgradeContract(IdleCDO(address(idleCDO)).strategy(), address(new IdleEulerStrategy()));
    // NOTE: we upgrade also CDO here to remove calls to eToken contract
    _upgradeContract(address(idleCDO), address(new IdleCDO()));
    // send funds from dev multisig to cdo. Amount is calculated at block 16818362
    vm.prank(DEV_MULTISIG);
    IERC20Detailed(under).safeTransfer(address(idleCDO), amount);

    // check that price did not decrease
    uint256 postAAPrice = idleCDO.virtualPrice(AA);
    uint256 postBBPrice = idleCDO.virtualPrice(BB);
    assertGe(postAAPrice, preAAPrice, 'AA price did not decrease');
    assertGe(postBBPrice, preBBPrice, 'BB price did not decrease');

    vm.startPrank(idleCDO.owner());
    idleCDO.setAllowAAWithdraw(true);
    idleCDO.setAllowBBWithdraw(true);
    vm.stopPrank();

    // redeem with all users
    uint256 redeemed;
    for (uint256 i = 0; i < users.length; i++) {
      vm.startPrank(users[i]);
      // check if has AA or BB tranches
      if (IERC20Detailed(idleCDO.AATranche()).balanceOf(users[i]) > 0) {
        redeemed = idleCDO.withdrawAA(0);
        // check that redeemed value is >= preUserAA
        assertGe(redeemed, preUserAA[i], 'AA redeemed value is less than pre hack');
      } else {
        redeemed = idleCDO.withdrawBB(0);
        // check that redeemed value is >= preUserBB
        assertGe(redeemed, preUserBB[i], 'BB redeemed value is less than pre hack');
      }
      vm.stopPrank();
    }

    // check that price is equal to preXXPrices
    uint256 postAAPrice2 = idleCDO.virtualPrice(AA);
    uint256 postBBPrice2 = idleCDO.virtualPrice(BB);
    // NOTE: this branch is needed because AGEUR PYT has only 2 users so when
    // they both redeem the price will be 1
    if (under != AGEUR) {
      assertEq(postAAPrice2, preAAPrice, 'AA price changed');
    }
    assertEq(postBBPrice2, preBBPrice, 'BB price changed');
  }

  struct VaultDatas {
    address AA;
    address BB;
    uint256 AAPrice;
    uint256 BBPrice;
    uint256 BYPriceAA;
    uint256 BYPriceBB;
    uint256 UserAA;
    uint256 UserBB;
  }

  // @notice we test both junior and senior BY redeems to check that everything is working
  // with multiple redeems for the same PYT
  // @dev we use a struct here to avoid stack too deep error
  function _genericRedeemStakingTest(
    address under, 
    uint256 amount, 
    IdleCDO idleCDO, 
    IdleTokenFungible _idleToken,
    IdleTokenFungible _idleTokenJunior
  ) internal {
    // fetch data pre Euler pause
    VaultDatas memory preData = _fetchDatas(idleCDO, _idleToken, _idleTokenJunior);
    // fork at recent block, post hack, post rescue
    _forkAt(BLOCK_FOR_TEST);
    // Upgrade strategy. Strategy price will be set to 0
    _upgradeContract(IdleCDO(address(idleCDO)).strategy(), address(new IdleEulerStakingStrategy()));
    // send funds from dev multisig to cdo. Amount is calculated at PRE_EULER_PAUSE block
    vm.prank(DEV_MULTISIG);
    IERC20Detailed(under).safeTransfer(address(idleCDO), amount);

    // refetch datas post transfer
    VaultDatas memory postData = _fetchDatas(idleCDO, _idleToken, _idleTokenJunior);
    // post values should be >= pre values
    assertGe(postData.AAPrice, preData.AAPrice, 'AA price decreased');
    assertGe(postData.BBPrice, preData.BBPrice, 'BB price decreased');
    assertGe(postData.BYPriceAA, preData.BYPriceAA, 'BY AA price decreased');
    assertGe(postData.BYPriceBB, preData.BYPriceBB, 'BY BB price decreased');
    assertGe(postData.UserBB, preData.UserBB, 'BY BB user value decreased');

    // NOTE: this is not true on all BY seniors which uses staking because some 
    // users redeemed interest bearing tokens so the contract value decreased
    // assertGe(postData.UserAA, preData.UserAA, 'BY AA user value decreased');

    // unpause PYT contract
    vm.startPrank(idleCDO.owner());
    idleCDO.setAllowAAWithdraw(true);
    idleCDO.setAllowBBWithdraw(true);
    vm.stopPrank();

    // unpause BY contract
    vm.roll(block.number + 1);
    vm.prank(GUARDIAN_MULTISIG);
    _idleToken.unpause();

    // redeem with BY senior
    // we need to check that total value of the pool is the same pre and post rebalance 
    _idleToken.rebalance();
    VaultDatas memory postRebalanceData = _fetchDatas(idleCDO, _idleToken, _idleTokenJunior);

    assertEq(postRebalanceData.BYPriceAA, postData.BYPriceAA, 'BY AA price post rebalance changed');
    assertEq(postRebalanceData.UserAA, postData.UserAA, 'BY AA user value post rebalance changed');

    // burned all (or almost all) tranche tokens (18 decimals)
    assertLt(IERC20Detailed(preData.AA).balanceOf(address(_idleToken)), 1e18, 'tranche tokens burned');
    // tranche price should not change
    assertEq(postRebalanceData.AAPrice, postData.AAPrice, 'AA price changed');
    assertEq(postRebalanceData.BBPrice, postData.BBPrice, 'BB price changed');

    if (address(_idleTokenJunior) == address(0)) {
      return;
    }

    // unpause BY
    vm.prank(_idleTokenJunior.owner());
    _idleTokenJunior.unpause();

    // redeem with BY junior
    // we need to check that total value of the pool is the same pre and post rebalance 
    _idleTokenJunior.rebalance();
    postRebalanceData = _fetchDatas(idleCDO, _idleToken, _idleTokenJunior);

    assertEq(postRebalanceData.BYPriceBB, postData.BYPriceBB, 'BY BB price post rebalance changed');
    assertGe(postRebalanceData.UserBB, postData.UserBB, 'underlying BB pool value changed');
    // burned all or almost all tranche tokens
    assertLt(IERC20Detailed(preData.BB).balanceOf(address(_idleToken)), 1e18, 'tranche tokens burned');
    // tranche price should not change
    assertEq(postRebalanceData.AAPrice, postData.AAPrice, 'AA price changed');
    assertEq(postRebalanceData.BBPrice, postData.BBPrice, 'BB price changed');
  }

  function _fetchDatas(
    IdleCDO idleCDO,
    IdleTokenFungible _idleToken,
    IdleTokenFungible _idleTokenJunior
  ) internal view returns (VaultDatas memory data) {
    data.AA = idleCDO.AATranche();
    data.BB = idleCDO.BBTranche();
    data.AAPrice = idleCDO.virtualPrice(data.AA);
    data.BBPrice = idleCDO.virtualPrice(data.BB);
    data.BYPriceAA = _idleToken.tokenPrice();
    data.BYPriceBB = _idleTokenJunior.tokenPrice();
    data.UserAA = IERC20Detailed(address(_idleToken)).totalSupply() * data.BYPriceAA / 1e18;
    data.UserBB = IERC20Detailed(address(_idleTokenJunior)).totalSupply() * data.BYPriceBB / 1e18;
  }
}
