// SPDX-License-Identifier: MIT

// Notice old 'type' of test. For new tests inherit from TestIdleCDOBase.sol contract
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/strategies/euler/IdleEulerStrategy.sol";
import "forge-std/Test.sol";

contract TestIdleCDO is Test {
  using stdStorage for StdStorage;

  uint256 internal constant AA_RATIO_LIM_UP = 99000;
  uint256 internal constant AA_RATIO_LIM_DOWN = 50000;
  uint256 internal constant FULL_ALLOC = 100000;
  uint256 internal constant ONE_SCALE = 1e6;
  uint256 internal constant MAINNET_CHIANID = 1;
  address private constant owner = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address private constant rebalancer = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;
  address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address private constant eUSDC = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716;
  address private constant EULER_MAIN = 0x27182842E098f60e3D576794A5bFFb0777E025d3;

  IERC20Detailed internal underlying;
  IERC20Detailed internal strategyToken;
  IdleCDO internal idleCDO;
  IdleEulerStrategy internal strategy;
  IdleCDOTranche internal AAtranche;
  IdleCDOTranche internal BBtranche;
  uint256 public initialApr;
  uint256 public initialAAApr;
  uint256 public initialBBApr;
  uint256 public initialSplitRatio = 20000;

  modifier runOnForkingNetwork(uint256 networkId) {
    // solhint-disable-next-line
    if (block.chainid == networkId) {
      _;
    }
  }

  function setUp() public virtual runOnForkingNetwork(MAINNET_CHIANID) {
    underlying = IERC20Detailed(USDC);
    strategyToken = IERC20Detailed(eUSDC);
    // deploy strategy
    // `token` is address(1) to prevent initialization of the implementation contract.
    // it need to be reset mannualy.
    strategy = new IdleEulerStrategy();
    stdstore
      .target(address(strategy))
      .sig(strategy.token.selector)
      .checked_write(address(0));
    strategy.initialize(
      address(strategyToken),
      address(underlying),
      EULER_MAIN,
      owner // owner
    );

    // deploy idleCDO and tranches
    idleCDO = new IdleCDO();
    stdstore
      .target(address(idleCDO))
      .sig(idleCDO.token.selector)
      .checked_write(address(0));

    address[] memory incentiveTokens = new address[](0);
    idleCDO.initialize(
      10000 * ONE_SCALE,
      address(underlying),
      address(this), // governanceFund,
      owner, // owner,
      rebalancer, // rebalancer,
      address(strategy), // strategyToken
      initialSplitRatio, // apr split: 100000 is 100% to AA
      50000, // ideal value: 50% AA and 50% BB tranches
      incentiveTokens
    );

    // get tranche ref
    AAtranche = IdleCDOTranche(idleCDO.AATranche());
    BBtranche = IdleCDOTranche(idleCDO.BBTranche());

    vm.prank(owner);
    strategy.setWhitelistedCDO(address(idleCDO));
    vm.prank(owner);
    idleCDO.setIsAYSActive(true);

    // fund
    deal(address(underlying), address(this), 10000 * ONE_SCALE, true);
    underlying.approve(address(idleCDO), type(uint256).max);

    // get initial aprs
    initialApr = strategy.getApr();
    initialAAApr = idleCDO.getApr(address(AAtranche));
    initialBBApr = idleCDO.getApr(address(BBtranche));

    /// label
    vm.label(address(idleCDO), "idleCDO");
    vm.label(address(AAtranche), "AAtranche");
    vm.label(address(BBtranche), "BBtranche");
    vm.label(address(strategy), "strategy");
    vm.label(address(underlying), "underlying");
    vm.label(USDC, "USDC");
    vm.label(eUSDC, "eUSDC");
  }

  function testInitialize() external runOnForkingNetwork(MAINNET_CHIANID) {
    assertEq(strategy.owner(), owner);
    assertEq(strategy.whitelistedCDO(), address(idleCDO));
    assertEq(idleCDO.strategy(), address(strategy));
    assertEq(idleCDO.token(), address(underlying));
    assertGt(strategy.price(), ONE_SCALE);
    assertEq(idleCDO.tranchePrice(address(AAtranche)), ONE_SCALE);
    assertEq(idleCDO.tranchePrice(address(BBtranche)), ONE_SCALE);
    assertGt(initialApr, 0);
    assertEq(initialAAApr, 0);
    assertEq(initialBBApr, initialApr);
  }

  function testSetIsAYSActive() external runOnForkingNetwork(MAINNET_CHIANID) {
    vm.prank(address(1));
    vm.expectRevert(bytes("6")); // not authorized
    idleCDO.setIsAYSActive(false);
    vm.prank(owner);
    idleCDO.setIsAYSActive(true);
  }

  function testDepositAprCalculations() external runOnForkingNetwork(MAINNET_CHIANID) {
    // AARatio 50%
    idleCDO.depositAA(1e6);
    idleCDO.depositBB(1e6);

    // check that trancheAPRSplitRatio and aprs are updated 
    assertEq(idleCDO.trancheAPRSplitRatio(), 25000, "split ratio");
    // limit is 50% of the strategy apr if AAratio is <= 50%
    assertEq(idleCDO.getApr(address(AAtranche)), initialApr / 2, "AA apr");
    // apr will be 150% of the strategy apr if AAratio is == 50%
    assertEq(idleCDO.getApr(address(BBtranche)), initialApr * 3 / 2, "BB apr");
  }

  function testAPRSplitRatioDeposits(
    uint16 _ratio
  ) external runOnForkingNetwork(MAINNET_CHIANID) {
    vm.assume(_ratio <= 1000);
    uint256 amount = 1000e6;
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

    uint256 amount = 1000e6;
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
}