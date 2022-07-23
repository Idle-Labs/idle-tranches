// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/interfaces/IProxyAdmin.sol";
import "forge-std/Test.sol";

interface Lido {
  function getBeaconStat() external view returns (
    uint256 depositedValidators,
    uint256 beaconValidators,
    uint256 beaconBalance
  );
}

// @notice contract used to test the update of lido PYT to the new 
// IdleCDO implementation with the adaptive yield split strategy and referrals
contract TestUpdateLidoPYT is Test {
  using stdStorage for StdStorage;
  event Referral(uint256 _amount, address _ref);

  uint256 internal constant FULL_ALLOC = 100000;
  uint256 internal constant MAINNET_CHIANID = 1;
  uint256 internal initialBal;
  uint256 internal decimals;
  uint256 internal ONE_SCALE;
  address[] internal rewards;
  address[] internal incentives; // incentives is a subset of rewards
  address public owner;
  IdleCDO internal idleCDO;
  IERC20Detailed internal underlying;
  IERC20Detailed internal strategyToken;
  IdleCDOTranche internal AAtranche;
  IdleCDOTranche internal BBtranche;
  IIdleCDOStrategy internal strategy;

  modifier runOnForkingNetwork(uint256 networkId) {
    // solhint-disable-next-line
    if (block.chainid == networkId) {
      _;
    }
  }

  function setUp() public virtual runOnForkingNetwork(MAINNET_CHIANID) {
    idleCDO = IdleCDO(0x34dCd573C5dE4672C8248cd12A99f875Ca112Ad8);

    // deploy new implementation
    address _cdoAYSImpl = address(new IdleCDO());
    // or use an existing implementation with AYS only
    // address _cdoAYSImpl = 0x6F322059CaF329B598b3C09De27C4F851780b62f;
    IProxyAdmin admin = IProxyAdmin(0x9438904ABC7d8944A6E2A89671fEf51C629af351);
    vm.prank(admin.owner());
    admin.upgrade(address(idleCDO), _cdoAYSImpl);

    // activate AYS and remove fees and unlet perc for easy testing
    vm.startPrank(idleCDO.owner());
    idleCDO.setIsAYSActive(true);
    idleCDO.setUnlentPerc(0);
    idleCDO.setFee(0);
    vm.stopPrank();

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

    // fund (deal cheatcode is not working directly for stETH apparently)
    initialBal = 10000 * ONE_SCALE;
    vm.prank(0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2);
    underlying.transfer(address(this), initialBal);
    underlying.approve(address(idleCDO), type(uint256).max);

    // put all unlent funds in lido contract
    _cdoHarvest(false);

    // label
    vm.label(address(idleCDO), "idleCDO");
    vm.label(address(AAtranche), "AAtranche");
    vm.label(address(BBtranche), "BBtranche");
    vm.label(address(strategy), "strategy");
    vm.label(address(underlying), "underlying");
    vm.label(address(strategyToken), "strategyToken");
  }

  function testInitialize() external runOnForkingNetwork(MAINNET_CHIANID) {
    assertEq(idleCDO.token(), address(underlying));
    assertGt(strategy.price(), ONE_SCALE);
    assertGt(idleCDO.tranchePrice(address(AAtranche)), ONE_SCALE);
    assertGt(idleCDO.tranchePrice(address(BBtranche)), ONE_SCALE);
  }

  function testDepositsReferral() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 1000 * ONE_SCALE;
    vm.expectEmit(true, true, true, true);
    emit Referral(amount, address(1));
    idleCDO.depositAARef(amount, address(1));
    vm.expectEmit(true, true, true, true);
    emit Referral(amount, address(2));
    idleCDO.depositBBRef(amount, address(2));
  }

  function testDeposits() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 1000 * ONE_SCALE;
    uint256 aaPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 bbPrice = idleCDO.virtualPrice(address(BBtranche));
    uint256 initialStrategyBal = underlying.balanceOf(address(strategy));
    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 totAmount = amount * 2;
    assertEq(IERC20(AAtranche).balanceOf(address(this)), amount * 1e18 / aaPrice, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), amount * 1e18 / bbPrice, "BBtranche bal");
    assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal - totAmount, 1, "underlying bal of contract");
    assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), totAmount, 1, "underlying bal of idleCDO");
    // strategy bal is unchanged
    assertApproxEqAbs(underlying.balanceOf(address(strategy)), initialStrategyBal, 1, "strategy bal");
    uint256 strategyPrice = strategy.price();

    _cdoHarvest(true);
    assertApproxEqAbs(underlying.balanceOf(address(idleCDO)), 0, 1, "underlying bal of idleCDO after harvest");
    // Skip 7 day forward to accrue interest
    skip(7 days); 
    vm.roll(block.number + 1);

    assertGt(strategy.price(), strategyPrice, "strategy price");
    // virtualPrice should increase too
    assertGt(idleCDO.virtualPrice(address(AAtranche)), aaPrice, "AA virtual price");
    assertGt(idleCDO.virtualPrice(address(BBtranche)), bbPrice, "BB virtual price");
  }

  function testRedeems() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 1000 * ONE_SCALE;
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
    assertGt(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  function _cdoHarvest(bool triggerRebase) internal {
    uint256 numOfRewards = 0;
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](numOfRewards);
    uint256[] memory _minAmount = new uint256[](numOfRewards);
    uint256[] memory _sellAmounts = new uint256[](numOfRewards);
    bytes memory _extraData;

    vm.prank(idleCDO.rebalancer());
    idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

    // linearly release all sold rewards
    vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1); 

    if (triggerRebase) {
      // trigger a rebalance see here https://github.com/lidofinance/lido-dao/blob/816bf1d0995ba5cfdfc264de4acda34a7fe93eba/contracts/0.4.24/Lido.sol#L78
      address lido = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
      uint256 beaconBal;
      (,,beaconBal) = Lido(lido).getBeaconStat();
      vm.store(lido, keccak256("lido.Lido.beaconBalance"), bytes32(beaconBal + 1e18));
    }
  }
}