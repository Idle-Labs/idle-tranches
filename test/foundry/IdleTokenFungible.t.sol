// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleTokenFungible.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/interfaces/IProxyAdmin.sol";
import "forge-std/Test.sol";

import {IdlePYTClear} from "best-yield-PYT-strategy/ClearpoolStrategy.sol";

contract TestIdleTokenFungible is Test {
  using stdStorage for StdStorage;

  event Referral(uint256 _amount, address _ref);

  uint256 internal mainnetFork;
  address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public constant CPOOL = 0x66761Fa41377003622aEE3c7675Fc7b5c1C2FaC5;
  address public constant RBN = 0x6123B0049F904d730dB3C36a31167D9d4121fA6B;
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  address public constant DL_MULTISIG = 0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b;
  address public constant REBALANCER = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;
  uint256 public constant FULL_ALLOC = 100000;
  uint256 public ONE_TOKEN;
  uint256 public decimals;
  address public owner;
  address public dude = address(0xdead);
  IdleTokenFungible public idleToken;
  IERC20Detailed public underlying = IERC20Detailed(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  // cpwinusdc
  IdleCDO public cdo1 = IdleCDO(0xDBCEE5AE2E9DAf0F5d93473e08780C9f45DfEb93);
  // bb tranche
  address public protocolToken1 = 0x4D9d9AA17c3fcEA05F20a87fc1991A045561167d;
  IERC20Detailed public lendToken1 = IERC20Detailed(0xCb288b6d30738db7E3998159d192615769794B5b);
  IdlePYTClear public wrap1;

  // rfolusdc
  IdleCDO public cdo2 = IdleCDO(0x4bC5E595d2e0536Ea989a7a9741e9EB5c3CAea33);
  // bb tranche
  address protocolToken2 = 0x982E46e81E99fbBa3Fb8Af031A7ee8dF9041bb0C;
  IERC20Detailed public lendToken2 = IERC20Detailed(0x3CD0ecf1552D135b8Da61c7f44cEFE93485c616d);
  IdlePYTClear public wrap2;

  function setUp() public virtual {
    // setup local fork at specific block
    uint256 blockForTest = 15_867_256;
    mainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"), blockForTest);
    vm.selectFork(mainnetFork);

    // create IdleToken
    idleToken = new IdleTokenFungible();
    address _idleToken = address(idleToken);
  
    // deploy and initialize wrappers 
    wrap1 = new IdlePYTClear();
    stdstore.target(address(wrap1)).sig(wrap1.token.selector).checked_write(address(0));
    wrap1.initialize(protocolToken1, _idleToken, address(cdo1));

    wrap2 = new IdlePYTClear();
    stdstore.target(address(wrap2)).sig(wrap2.token.selector).checked_write(address(0));
    wrap2.initialize(protocolToken2, _idleToken, address(cdo2));

    // set protocol tokens
    address[] memory _protocolTokens = new address[](2);
    (_protocolTokens[0], _protocolTokens[1]) = (protocolToken1, protocolToken2);
    // set wrappers
    address[] memory _wrappers = new address[](2);
    (_wrappers[0], _wrappers[1]) = (address(wrap1), address(wrap2));
    // all on clearpool
    uint256[] memory _lastAlloc = new uint256[](2);
    (_lastAlloc[0], _lastAlloc[1]) = (100000, 0);

    // reset storage to be able to manually initialize
    stdstore.target(_idleToken).sig(idleToken.token.selector).checked_write(false);
  
    // initialize idleToken
    idleToken._init(
      "Idle BY junior", "idleUSDCJunior", address(underlying), 
      _protocolTokens, _wrappers, _lastAlloc
    );

    // remove fees and unlent perc for easy testing
    vm.startPrank(idleToken.owner());
    idleToken.setMaxUnlentPerc(0);
    idleToken.setFee(0);
    vm.stopPrank();

    // set globals
    decimals = underlying.decimals();
    ONE_TOKEN = 10 ** decimals;

    // give underlyings to this contract and to user
    deal(address(underlying), address(this), 10_000_000 * 1e6);
    deal(address(underlying), dude, 10_000_000 * 1e6);

    // approve idleToken to spend underlying from this contract
    underlying.approve(_idleToken, type(uint256).max);
    vm.prank(dude);
    underlying.approve(_idleToken, type(uint256).max);

    // labels
    vm.label(address(idleToken), "idleToken");
    vm.label(address(protocolToken1), "AA_cpwinusdc");
    vm.label(address(lendToken1), "cpwinusdc");
    vm.label(address(wrap1), "cpwin_wrapper");
    vm.label(address(wrap2), "rfol_wrapper");
    vm.label(address(protocolToken2), "AA_rfolusdc");
    vm.label(address(lendToken2), "rfolusdc");
    vm.label(address(underlying), "underlying");
    vm.label(address(cdo1), "cpwin_cdo");
    vm.label(address(cdo2), "rfol_cdo");
  }

  function testInitialize() external {
    assertEq(idleToken.token(), address(underlying));
    assertEq(idleToken.feeAddress(), TL_MULTISIG);
    assertEq(idleToken.rebalancer(), REBALANCER);
    assertEq(idleToken.getAllAvailableTokens().length, 2);
    assertEq(idleToken.protocolWrappers(protocolToken1), address(wrap1));
    assertEq(idleToken.protocolWrappers(protocolToken2), address(wrap2));

    uint256[] memory _a = idleToken.getAllocations();
    assertEq(_a[0], 100000);
    assertEq(_a[1], 0);
    assertEq(idleToken.lastAllocations(0), 100000);
    assertEq(idleToken.lastAllocations(1), 0);
  }

  function testSkipRedeemMinAmount() external {
    vm.prank(address(0x1));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    idleToken.setSkipRedeemMinAmount(true);

    vm.prank(idleToken.owner());
    idleToken.setSkipRedeemMinAmount(true);

    assertEq(idleToken.skipRedeemMinAmount(), true);
  }

  function testPause() external {
    vm.prank(address(0x1));
    vm.expectRevert(bytes("6"));
    idleToken.pause();

    vm.prank(TL_MULTISIG);
    idleToken.pause();

    assertEq(idleToken.paused(), true, 'Not paused');
  }

  function testUnpause() external {
    vm.prank(idleToken.owner());
    idleToken.pause();

    vm.prank(address(0x1));
    vm.expectRevert(bytes("6"));
    idleToken.unpause();

    vm.prank(DL_MULTISIG);
    idleToken.unpause();

    assertEq(idleToken.paused(), false, 'Paused');
  }

  function testSetAllAvailableTokensAndWrappers() external {
    address[] memory _protocolTokens = new address[](2);
    address[] memory _wrappers = new address[](2);
    (_protocolTokens[0], _protocolTokens[1]) = (address(1), address(2));
    (_wrappers[0], _wrappers[1]) = (address(111), address(222));
    vm.prank(address(0x1));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    idleToken.setAllAvailableTokensAndWrappers(_protocolTokens, _wrappers);

    vm.prank(idleToken.owner());
    idleToken.setAllAvailableTokensAndWrappers(_protocolTokens, _wrappers);

    assertEq(idleToken.protocolWrappers(address(1)), address(111), 'Protocol wrap 1 is wrong');
    assertEq(idleToken.protocolWrappers(address(2)), address(222), 'Protocol wrap 2 is wrong');
    address[] memory _allTokens = idleToken.getAllAvailableTokens();

    assertEq(_allTokens[0], address(1));
    assertEq(_allTokens[1], address(2));
  }

  function testGetAPRs() external {
    (address[] memory addresses, uint256[] memory aprs) = idleToken.getAPRs();
    assertEq(addresses[0], protocolToken1, 'Protocol token 1 is wrong');
    assertEq(addresses[1], protocolToken2, 'Protocol token 2 is wrong');
    assertGt(aprs[0], 1e18, 'Apr for protocol 1 is less than 1%');
    assertGt(aprs[1], 1e18, 'Apr for protocol 2 is less than 1%');
  }

  function testGetAvgAPR() external {
    assertEq(idleToken.getAvgAPR(), 0);

    // do a deposit to have non zero balance
    idleToken.mintIdleToken(ONE_TOKEN / 1000, true, address(0));
    _rebalance(100000, 0);

    (, uint256[] memory aprs) = idleToken.getAPRs();
    // there is a single protocol in use
    assertEq(idleToken.getAvgAPR(), aprs[0], 'Apr of protocol 1 is wrong');

    vm.roll(block.number + 1);
    // all on second protocol
    _rebalance(0, 100000);
    // we use approx eq because at current block there is low tvl on protocol 2
    assertApproxEqAbs(
      idleToken.getAvgAPR(),
      aprs[1],
      1e17, // 0.1
      'Apr of protocol 2 is wrong'
    );

    vm.roll(block.number + 1);
    // half on first protocol and half on second
    _rebalance(50000, 50000);
    assertApproxEqAbs(
      idleToken.getAvgAPR(),
      (aprs[0] + aprs[1]) / 2,
      1e17, // 0.1
      'Apr of protocol 2 + protocol 1 is wrong'
    );
  }

  function testTokenPrice() external {
    assertEq(idleToken.tokenPrice(), ONE_TOKEN, 'Token price is not 1');

    // do a deposit, price should not change
    idleToken.mintIdleToken(ONE_TOKEN * 1_000_000, true, address(0));
    assertEq(idleToken.tokenPrice(), ONE_TOKEN, 'Token price changed after mint');

    // send funds in lending provider via rebalance
    _rebalance(50000, 50000);
    assertApproxEqAbs(idleToken.tokenPrice(), ONE_TOKEN, 5, 
      'Token price changed after rebalance');

    // accrue some interest
    _harvestCDO(address(cdo1));
    _harvestCDO(address(cdo2));
    vm.warp(block.timestamp + 2 days); 

    // price should be increased
    uint256 priceAfterHarvest = idleToken.tokenPrice();
    assertGt(priceAfterHarvest, ONE_TOKEN, 'Token price did not increase');
    
    // add funds to have some liquidity left after redeem
    vm.prank(dude);
    idleToken.mintIdleToken(ONE_TOKEN * 100_000, true, address(0));

    // avoid reentrancy block
    vm.roll(block.number + 1);

    // redeem 
    idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));
    assertGe(idleToken.tokenPrice(), priceAfterHarvest, 
      'Token price changed after redeem');

    // avoid reentrancy block
    vm.roll(block.number + 1);

    // redeem last balance 
    uint256 dudeBal = idleToken.balanceOf(dude);
    vm.prank(dude);
    idleToken.redeemIdleToken(dudeBal);
    assertEq(idleToken.tokenPrice(), ONE_TOKEN, 'Token price is not 1 after last redeem');
  }

  function testMintIdleToken() external {
    idleToken.mintIdleToken(ONE_TOKEN * 1_000_000, true, address(0));
    assertEq(idleToken.balanceOf(address(this)), 1_000_000 * 1e18, 'Idle token balance not correct');
    assertEq(idleToken.lastNAV(), ONE_TOKEN * 1_000_000, 'lastNAV is not correct');

    // funds in lending
    _rebalance(50000, 50000);
    // accrue some interest
    _harvestCDO(address(cdo1));
    vm.warp(block.timestamp + 2 days); 

    vm.prank(dude);
    idleToken.mintIdleToken(ONE_TOKEN * 1_000_000, true, address(0));
    assertGt(idleToken.lastNAV(), ONE_TOKEN * 1_000_000 * 2, 'lastNAV did not accrue interest');
    assertGt(idleToken.balanceOf(address(this)), idleToken.balanceOf(dude), 'Minted amount is not less than first mint');
  }

  function testRedeemIdleTokenLowLiquidity() public {
    uint256 amount = ONE_TOKEN * 1_000_000;
    idleToken.mintIdleToken(amount, true, address(0));

    // deposit with another user to have non 0 balance after redeem
    vm.prank(dude);
    idleToken.mintIdleToken(amount, true, address(0));

    // funds in lending
    _rebalance(50000, 50000);
    // accrue some interest
    _harvestCDO(address(cdo1));
    vm.warp(block.timestamp + 2 days);

    // set available liquidity for first protocol to a small value 
    // we deposited 1M in each protocol, so we set available liquidity 
    // to 500k on first protocol
    vm.mockCall(
      address(wrap1),
      abi.encodeWithSelector(IdlePYTClear.availableLiquidity.selector),
      abi.encode(500_000 * 1e6) // USDC
    );

    uint256 balPre = underlying.balanceOf(address(this));
    idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));
    assertGe(underlying.balanceOf(address(this)), balPre + amount, 'Balance is not increased after redeem');
    vm.clearMockedCalls();

    // Test another redeem
    // set available liquidity for second protocol to a small value 
    // we deposited 1M in each protocol, so we set available liquidity 
    // to 500k on second protocol
    vm.mockCall(
      address(wrap2),
      abi.encodeWithSelector(IdlePYTClear.availableLiquidity.selector),
      abi.encode(500_000 * 1e6) // USDC
    );

    balPre = underlying.balanceOf(dude);
    uint256 idleTokenAmount = idleToken.balanceOf(address(this));
    vm.prank(dude);
    idleToken.redeemIdleToken(idleTokenAmount);
    assertGe(underlying.balanceOf(address(this)), balPre + amount, 'Balance is not increased after redeem');
    vm.clearMockedCalls();
  }

  function testRedeemIdleToken() public {
    uint256 balPre = underlying.balanceOf(address(this));
    uint256 amount = ONE_TOKEN * 1_000_000;
    idleToken.mintIdleToken(amount, true, address(0));

    // deposit with another user to have non 0 balance after redeem
    uint256 dudeBalUnderl = underlying.balanceOf(dude);
    vm.prank(dude);
    idleToken.mintIdleToken(amount, true, address(0));

    // funds in lending
    _rebalance(50000, 50000);
    // accrue some interest
    _harvestCDO(address(cdo1));
    uint256 price = idleToken.tokenPrice();
    vm.warp(block.timestamp + 2 days);

    idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));
    assertGt(idleToken.lastNAV(), amount, 'lastNAV is not correct');
    assertGt(underlying.balanceOf(address(this)), balPre, 'Balance did not increase');

    uint256 dudeBal = idleToken.balanceOf(dude);
    vm.prank(dude);
    idleToken.redeemIdleToken(dudeBal/2);
    assertGt(idleToken.lastNAV(), amount/2, 'lastNAV is > than the amount deposited by dude');
    assertGt(idleToken.tokenPrice(), price, 'Token price did not increase');
    vm.prank(dude);
    idleToken.redeemIdleToken(dudeBal/2);
    assertEq(idleToken.tokenPrice(), 1e6, 'Token price is not 1');
    assertGt(underlying.balanceOf(dude), dudeBalUnderl, 'Dude balance did not increase');
  }

  function testRebalance() external {
    idleToken.mintIdleToken(ONE_TOKEN * 1_000_000, true, address(0));
    // funds in lending in both protocols
    _rebalance(50000, 50000);
    uint256 cdo1Bal = IERC20Detailed(cdo1.BBTranche()).balanceOf(address(idleToken));
    uint256 cdo2Bal = IERC20Detailed(cdo2.BBTranche()).balanceOf(address(idleToken));
    assertGt(cdo1Bal, 0, 'Cdo1 bal is 0');
    assertGt(cdo2Bal, 0, 'Cdo2 bal is 0');
    assertEq(underlying.balanceOf(address(idleToken)), 0, 'underlying bal is 0');

    vm.roll(block.number + 1);

    // funds in lending all in first protocol
    _rebalance(100000, 0);
    cdo1Bal = IERC20Detailed(cdo1.BBTranche()).balanceOf(address(idleToken));
    cdo2Bal = IERC20Detailed(cdo2.BBTranche()).balanceOf(address(idleToken));
    assertGt(cdo1Bal, 0, 'Cdo1 bal is 0');
    assertLt(cdo2Bal, 1e18 * 0.00001, 'Cdo2 bal is not almost 0');

    vm.roll(block.number + 1);

    // funds in lending all in second protocol
    _rebalance(0, 100000);
    cdo1Bal = IERC20Detailed(cdo1.BBTranche()).balanceOf(address(idleToken));
    cdo2Bal = IERC20Detailed(cdo2.BBTranche()).balanceOf(address(idleToken));
    assertGt(cdo2Bal, 0, 'Cdo1 bal is 0');
    assertLt(cdo1Bal, 1e18 * 0.00001, 'Cdo1 bal is not almost 0');
  }

  function testFeeMgmtOnMint() external {
    vm.prank(idleToken.owner());
    idleToken.setFee(10000); // 10%
    
    uint256 amount = ONE_TOKEN * 1_000_000;
    idleToken.mintIdleToken(amount, true, address(0));
    assertEq(idleToken.lastNAV(), amount, 'lastNav after mint is not correct');
    // funds in lending
    _rebalance(100000, 0);

    // accrue some interest
    _harvestCDO(address(cdo1));
    vm.warp(block.timestamp + 2 days);

    // do another mint to mint fees
    idleToken.mintIdleToken(amount, true, address(0));
    uint256 fees = idleToken.balanceOf(idleToken.feeAddress());
    assertGt(fees, 0, 'Fees not minted');
    assertApproxEqAbs(
      idleToken.lastNAV(),
      // 2 deposits of `amount` + gain (which is feebal, in idleToken, * 10 * tokenPrice)
      amount * 2 + (fees * idleToken.tokenPrice() / 1e18) * 10, 
      400,
      'lastNAV is not correct'
    );
  }

  function testFeeMgmtOnRedeem() external {
    vm.prank(idleToken.owner());
    idleToken.setFee(10000); // 10%
    
    uint256 amount = ONE_TOKEN * 1_000_000;
    idleToken.mintIdleToken(amount, true, address(0));
    // deposit with another user to have non 0 balance after redeem
    vm.prank(dude);
    idleToken.mintIdleToken(ONE_TOKEN, true, address(0));

    // funds in lending
    _rebalance(100000, 0);

    // accrue some interest
    _harvestCDO(address(cdo1));
    uint256 poolValPre = idleToken.tokenPrice() * idleToken.totalSupply() / 1e18;
    vm.warp(block.timestamp + 2 days);
    uint256 pricePre = idleToken.tokenPrice();
    uint256 poolValPost = pricePre * idleToken.totalSupply() / 1e18;
    uint256 gain = poolValPost - poolValPre;
    gain = gain + gain / 9; // ~10% fee
    // redeem to mint fees
    idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));
    uint256 fees = idleToken.balanceOf(idleToken.feeAddress());
    assertGt(fees, 0, 'Fees not minted');
    uint256 pricePost = idleToken.tokenPrice();
    assertApproxEqRel(
      fees,
      gain / 10 * 1e18 / pricePost, // + interest gained for ONE_TOKEN
      1e17, // 0.1%
      'Fees not correct'
    );

    assertGe(pricePost, pricePre, 'tokenPrice decreased');
    uint256 feesUnderlying = fees * idleToken.tokenPrice() / 1e18;
    assertApproxEqRel(
      idleToken.lastNAV(),
      ONE_TOKEN + feesUnderlying, // ONE_TOKEN from `dude` + interest gained for ONE_TOKEN + fees
      1e15, // 0.001%
      'lastNAV is not correct'
    );
  }

  function testRebalanceWithUnlent() external {
    vm.prank(idleToken.owner());
    idleToken.setMaxUnlentPerc(10000); // 10%

    uint256 amount = ONE_TOKEN * 1_000_000;
    idleToken.mintIdleToken(amount, true, address(0));
    // funds in lending in both protocols
    _rebalance(50000, 50000);
    uint256 cdo1Bal = IERC20Detailed(cdo1.BBTranche()).balanceOf(address(idleToken));
    uint256 cdo2Bal = IERC20Detailed(cdo2.BBTranche()).balanceOf(address(idleToken));
    assertGt(cdo1Bal, 0, 'Cdo1 bal is 0');
    assertGt(cdo2Bal, 0, 'Cdo2 bal is 0');
    assertEq(underlying.balanceOf(address(idleToken)), amount / 10, 'underlying bal is not 10%');
  }

  function testRedeemIdleTokenWithUnlent() external {
    vm.prank(idleToken.owner());
    idleToken.setMaxUnlentPerc(10000); // 10%

    testRedeemIdleToken();
  }

  function testRebalanceFeeMgmt() external {
    vm.prank(idleToken.owner());
    idleToken.setFee(10000); // 10%

    uint256 amount = ONE_TOKEN * 1_000_000;
    idleToken.mintIdleToken(amount, true, address(0));
    // funds in lending in both protocols
    _rebalance(100000, 0);

    // accrue some interest
    _harvestCDO(address(cdo1));
    vm.warp(block.timestamp + 2 days);

    // do another harvest to distribute fees
    _rebalance(100000, 0);
    assertGt(idleToken.balanceOf(idleToken.feeAddress()), 0, 'Fees not minted');
    assertEq(idleToken.unclaimedFees(), 0, 'unclaimedFees not resetted');
  }

  function testMintFees() external {
    vm.prank(idleToken.owner());
    idleToken.setFee(10000);

    idleToken.mintIdleToken(ONE_TOKEN * 1_000, true, address(0));
    // funds in lending earning some interest for 1 year (~10USDC of fees)
    _rebalance(100000, 0);
    _harvestCDO(address(cdo1));
    vm.warp(block.timestamp + 365 days);
 
    uint256 tokenPricePre = idleToken.tokenPrice();
    // rebalance to mint fees
    _rebalance(100000, 0);
    uint256 tokenPricePost = idleToken.tokenPrice();
    assertGe(tokenPricePost, tokenPricePre, 'Token price decreased');
    assertGt(idleToken.balanceOf(idleToken.feeAddress()), 0, 'no fees distributed');
  }

  function _harvestCDO(address _cdo) internal {
    IdleCDO idleCDO = IdleCDO(_cdo);
    uint256 numOfRewards = 1;
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](numOfRewards);
    uint256[] memory _minAmount = new uint256[](numOfRewards);
    uint256[] memory _sellAmounts = new uint256[](numOfRewards);
    bytes[] memory _extraData = new bytes[](2);
    bytes[] memory _extraPath = new bytes[](1);

    if (_cdo == address(cdo1)) {
      _extraPath[0] = abi.encodePacked(CPOOL, uint24(10000), USDC, uint24(100), DAI);
    } else {
      _extraPath[0] = abi.encodePacked(RBN, uint24(3000), USDC, uint24(100), DAI);
    }
    // _extraData[0] = 0x
    _extraData[1] = abi.encode(_extraPath);

    // skip fees distribution
    _skipFlags[3] = true;
    // do harvest to put funds in lending
    vm.prank(idleCDO.rebalancer());
    idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);
    // linearly release all sold rewards if any
    vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1); 
  }

  function _rebalance(uint256 alloc1, uint256 alloc2) public {
    uint256[] memory allocations = new uint256[](2);
    (allocations[0], allocations[1]) = (alloc1, alloc2);
    vm.startPrank(REBALANCER);
    idleToken.setAllocations(allocations);
    idleToken.rebalance();
    vm.stopPrank();
  }
}