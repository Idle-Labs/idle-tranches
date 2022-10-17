// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleCDO.sol";
import "forge-std/Test.sol";

interface IIdleCDOStrategyEnhanced is IIdleCDOStrategy {
  function setWhitelistedCDO(address _cdo) external;
  function transferToken(address, uint256, address) external;
}

abstract contract TestIdleCDOBase is Test {
  using stdStorage for StdStorage;

  uint256 internal constant AA_RATIO_LIM_UP = 99000;
  uint256 internal constant AA_RATIO_LIM_DOWN = 50000;
  uint256 internal constant FULL_ALLOC = 100000;
  uint256 internal constant MAINNET_CHIANID = 1;
  uint256 internal initialBal;
  uint256 public initialApr;
  uint256 public initialAAApr;
  uint256 public initialBBApr;
  uint256 internal decimals;
  uint256 internal ONE_SCALE;
  uint256 internal extraRewards;
  address[] internal rewards;
  address[] internal incentives; // incentives is a subset of rewards
  address public owner;
  IdleCDO internal idleCDO;
  IERC20Detailed internal underlying;
  IERC20Detailed internal strategyToken;
  IdleCDOTranche internal AAtranche;
  IdleCDOTranche internal BBtranche;
  IIdleCDOStrategy internal strategy;
  bytes internal extraData;
  bytes internal extraDataSell;

  // override these methods in derived contracts
  function _deployStrategy(address _owner) internal virtual returns (
    address _strategy,
    address _underlying
  );

  function _postDeploy(address _cdo, address _owner) virtual internal;
  function _deployCDO() internal virtual returns (IdleCDO _cdo) {
    _cdo = new IdleCDO();
  }
  // end override

  modifier runOnForkingNetwork(uint256 networkId) {
    // solhint-disable-next-line
    if (block.chainid == networkId) {
      _;
    }
  }

  function setUp() public virtual runOnForkingNetwork(MAINNET_CHIANID) {
    idleCDO = _deployLocalContracts();

    owner = idleCDO.owner();
    underlying = IERC20Detailed(idleCDO.token());
    decimals = underlying.decimals();
    ONE_SCALE = 10 ** decimals;
    strategy = IIdleCDOStrategy(idleCDO.strategy());
    strategyToken = IERC20Detailed(strategy.strategyToken());
    AAtranche = IdleCDOTranche(idleCDO.AATranche());
    BBtranche = IdleCDOTranche(idleCDO.BBTranche());
    rewards = strategy.getRewardTokens();
    incentives = idleCDO.getIncentiveTokens();

    // fund
    initialBal = 1000000 * ONE_SCALE;
    deal(address(underlying), address(this), initialBal, true);
    underlying.approve(address(idleCDO), type(uint256).max);

    // get initial aprs
    initialApr = strategy.getApr();
    initialAAApr = idleCDO.getApr(address(AAtranche));
    initialBBApr = idleCDO.getApr(address(BBtranche));

    // label
    vm.label(address(idleCDO), "idleCDO");
    vm.label(address(AAtranche), "AAtranche");
    vm.label(address(BBtranche), "BBtranche");
    vm.label(address(strategy), "strategy");
    vm.label(address(underlying), "underlying");
    vm.label(address(strategyToken), "strategyToken");
  }

  function testInitialize() external virtual runOnForkingNetwork(MAINNET_CHIANID) {
    assertEq(idleCDO.token(), address(underlying));
    assertGe(strategy.price(), ONE_SCALE);
    assertEq(idleCDO.tranchePrice(address(AAtranche)), ONE_SCALE);
    assertEq(idleCDO.tranchePrice(address(BBtranche)), ONE_SCALE);
    assertEq(initialAAApr, 0);
    assertEq(initialBBApr, initialApr);
  }

  function testCantReinitialize() external virtual;

  function testDeposits() external virtual runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 totAmount = amount * 2;

    assertEq(IERC20(AAtranche).balanceOf(address(this)), 10000 * 1e18, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, "BBtranche bal");
    assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal");
    assertEq(underlying.balanceOf(address(idleCDO)), totAmount, "underlying bal");
    // strategy is still empty with no harvest
    assertEq(strategyToken.balanceOf(address(idleCDO)), 0, "strategy bal");
    uint256 strategyPrice = strategy.price();

    // check that trancheAPRSplitRatio and aprs are updated 
    assertEq(idleCDO.trancheAPRSplitRatio(), 25000, "split ratio");
    // limit is 50% of the strategy apr if AAratio is <= 50%
    assertEq(idleCDO.getApr(address(AAtranche)), initialApr / 2, "AA apr");
    // apr will be 150% of the strategy apr if AAratio is == 50%
    assertEq(idleCDO.getApr(address(BBtranche)), initialApr * 3 / 2, "BB apr");

    // skip rewards and deposit underlyings to the strategy
    _cdoHarvest(true);

    // claim rewards
    _cdoHarvest(false);
    assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal after harvest");    

    // Skip 7 day forward to accrue interest
    skip(7 days);
    vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);

    assertGt(strategy.price(), strategyPrice, "strategy price");

    // virtualPrice should increase too
    assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
    assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
  }

  function testRedeems() external virtual runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // funds in lending
    _cdoHarvest(true);
    skip(7 days); 
    vm.roll(block.number + 1);

    idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
    idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));
  
    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
    assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  function testRedeemRewards() external virtual runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    // funds in lending
    _cdoHarvest(true);
    skip(7 days); 
    vm.roll(block.number + 1);

    // sell some rewards
    uint256 pricePre = idleCDO.virtualPrice(address(AAtranche));
    _cdoHarvest(false);

    uint256 pricePost = idleCDO.virtualPrice(address(AAtranche));
    if (_numOfSellableRewards() > 0) {
      assertGt(pricePost, pricePre, "virtual price increased");
    } else {
      assertEq(pricePost, pricePre, "virtual price equal");
    }
  }

  function testOnlyIdleCDO()
      public
      virtual
      runOnForkingNetwork(MAINNET_CHIANID)
  {
    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Only IdleCDO can call"));
    strategy.deposit(1e10);

    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Only IdleCDO can call"));
    strategy.redeem(1e10);

    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Only IdleCDO can call"));
    strategy.redeemRewards(bytes(""));

    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Only IdleCDO can call"));
    strategy.redeemUnderlying(1);
  }

  function testOnlyOwner() public virtual {
    vm.startPrank(address(0xbabe));

    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    IIdleCDOStrategyEnhanced(address(strategy)).setWhitelistedCDO(address(0xcafe));

    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    IIdleCDOStrategyEnhanced(address(strategy)).transferToken(
      address(underlying),
      1e6,
      address(0xbabe)
    );
    vm.stopPrank();
  }

  function testEmergencyShutdown() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // call with non owner
    vm.expectRevert(bytes("6"));
    vm.prank(address(0xbabe));
    idleCDO.emergencyShutdown();

    // call with owner
    vm.prank(owner);
    idleCDO.emergencyShutdown();

    vm.expectRevert(bytes("Pausable: paused")); // default
    idleCDO.depositAA(amount);
    vm.expectRevert(bytes("Pausable: paused")); // default
    idleCDO.depositBB(amount);
    vm.expectRevert(bytes("3")); // default
    idleCDO.withdrawAA(amount);
    vm.expectRevert(bytes("3")); // default
    idleCDO.withdrawBB(amount);
  }

  function testRestoreOperations() external virtual runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 1000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // call with non owner
    vm.expectRevert(bytes("6"));
    vm.prank(address(0xbabe));
    idleCDO.restoreOperations();

    // call with owner
    vm.startPrank(owner);
    idleCDO.emergencyShutdown();
    idleCDO.restoreOperations();
    vm.stopPrank();

    vm.roll(block.number + 1);

    idleCDO.withdrawAA(amount);
    idleCDO.withdrawBB(amount);
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);
  }

  function testAPR() external virtual runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    // funds in lending
    _cdoHarvest(true);
    // claim rewards
    _cdoHarvest(false);
    
    skip(7 days); 
    vm.roll(block.number + 1);
    uint256 apr = idleCDO.getApr(address(AAtranche));
    console.log('apr', apr);
    assertGe(apr / 1e16, 0, "apr is > 0.01% and with 18 decimals");
  }

  function testSetIsAYSActive() external runOnForkingNetwork(MAINNET_CHIANID) {
    vm.prank(address(1));
    vm.expectRevert(bytes("6")); // not authorized
    idleCDO.setIsAYSActive(false);
    vm.prank(owner);
    idleCDO.setIsAYSActive(true);
  }

  function testAPRSplitRatioDeposits(
    uint16 _ratio
  ) external runOnForkingNetwork(MAINNET_CHIANID) {
    vm.assume(_ratio <= 1000);
    uint256 amount = 1000 * ONE_SCALE;
    // to have the same scale as FULL_ALLOC and avoid 
    // `Too many global rejects` error in forge
    uint256 ratio = uint256(_ratio) * 100; 
    uint256 amountAA = amount * ratio / FULL_ALLOC;
    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amount - amountAA);

    assertEq(
      idleCDO.trancheAPRSplitRatio(), 
      _calcNewAPRSplit(ratio),
      "split ratio on deposits"
    );
  }

  function testAPRSplitRatioRedeems(
    uint16 _ratio,
    uint16 _redeemRatioAA,
    uint16 _redeemRatioBB
  ) external runOnForkingNetwork(MAINNET_CHIANID) {
    vm.assume(_ratio <= 1000 && _ratio > 0);
    // > 0 because it's a requirement of the withdraw
    vm.assume(_redeemRatioAA <= 1000 && _redeemRatioAA > 0);
    vm.assume(_redeemRatioBB <= 1000 && _redeemRatioBB > 0);

    uint256 amount = 1000 * ONE_SCALE;
    // to have the same scale as FULL_ALLOC and avoid 
    // `Too many global rejects` error in forge
    uint256 ratio = uint256(_ratio) * 100; 
    uint256 amountAA = amount * ratio / FULL_ALLOC;
    uint256 amountBB = amount - amountAA;
    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);

    // Set new block.height to avoid reentrancy check on deposit/withdraw
    vm.roll(block.number + 1);

    uint256 ratioRedeemAA = uint256(_redeemRatioAA) * 100; 
    uint256 ratioRedeemBB = uint256(_redeemRatioBB) * 100; 
    amountAA = AAtranche.balanceOf(address(this)) * ratioRedeemAA / FULL_ALLOC;
    amountBB = BBtranche.balanceOf(address(this)) * ratioRedeemBB / FULL_ALLOC;
    if (amountAA > 0) {
      idleCDO.withdrawAA(amountAA);
    }
    if (amountBB > 0) {
      idleCDO.withdrawBB(amountBB);
    }
    
    assertEq(
      idleCDO.trancheAPRSplitRatio(), 
      _calcNewAPRSplit(idleCDO.getCurrentAARatio()), 
      "split ratio on redeem"
    );
  }

  function _cdoHarvest(bool _skipRewards) internal {
    uint256 numOfRewards = rewards.length;
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](numOfRewards);
    uint256[] memory _minAmount = new uint256[](numOfRewards);
    uint256[] memory _sellAmounts = new uint256[](numOfRewards);
    bytes[] memory _extraData = new bytes[](2);
    if(!_skipRewards){
      _extraData[0] = extraData;
      _extraData[1] = extraDataSell;
    }
    // skip fees distribution
    _skipFlags[3] = _skipRewards;

    vm.prank(idleCDO.rebalancer());
    idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

    // linearly release all sold rewards
    vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1); 
  }

  function _deployLocalContracts() internal virtual returns (IdleCDO _cdo) {
    address _owner = address(2);
    address _rebalancer = address(3);
    (address _strategy, address _underlying) = _deployStrategy(_owner);
    
    // deploy idleCDO and tranches
    _cdo = _deployCDO();
    stdstore
      .target(address(_cdo))
      .sig(_cdo.token.selector)
      .checked_write(address(0));
    address[] memory incentiveTokens = new address[](0);
    _cdo.initialize(
      0,
      _underlying,
      address(this), // governanceFund,
      _owner, // owner,
      _rebalancer, // rebalancer,
      _strategy, // strategyToken
      20000, // apr split: 100000 is 100% to AA
      50000, // ideal value: 50% AA and 50% BB tranches
      incentiveTokens
    );

    vm.startPrank(_owner);
    _cdo.setIsAYSActive(true);
    _cdo.setUnlentPerc(0);
    _cdo.setFee(0);
    vm.stopPrank();

    _postDeploy(address(_cdo), _owner);
  }

  function _numOfSellableRewards() internal view returns (uint256 num) {
    for (uint256 i = 0; i < rewards.length; i++) {
      if (!_includesAddress(incentives, rewards[i])) {
        num++;
      }
    }
    
    if (extraRewards > 0) {
      num = num + extraRewards;
    }
  }

  function _includesAddress(address[] memory _array, address _val) internal pure returns (bool) {
    for (uint256 i = 0; i < _array.length; i++) {
      if (_array[i] == _val) {
        return true;
      }
    }
    // explicit return to fix linter
    return false;
  }

  function _calcNewAPRSplit(uint256 ratio) internal pure returns (uint256 _new){
    uint256 aux;
    if (ratio >= AA_RATIO_LIM_UP) {
      aux = AA_RATIO_LIM_UP;
    } else if (ratio > AA_RATIO_LIM_DOWN) {
      aux = ratio;
    } else {
      aux = AA_RATIO_LIM_DOWN;
    }
    _new = aux * ratio / FULL_ALLOC;
  }

  function _strategyReleaseBlocksPeriod() internal returns (uint256 releaseBlocksPeriod) {
    (bool success, bytes memory returnData) = address(strategy).staticcall(abi.encodeWithSignature("releaseBlocksPeriod()"));
    if (success){
      releaseBlocksPeriod = abi.decode(returnData, (uint32));
    } else {
      emit log("can't find releaseBlocksPeriod() on strategy");
      emit logs(returnData);
    }
  }
}