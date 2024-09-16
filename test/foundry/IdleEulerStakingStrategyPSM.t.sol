// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import "../../contracts/strategies/euler/IdleEulerStakingStrategyPSM.sol";

contract TestIdleEulerStakingStrategyPSM is TestIdleCDOBase {
  using stdStorage for StdStorage;
  address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public constant EUL = 0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b;
  address public constant EULER_MAIN = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
  // euler eUSDC
  address public constant eToken = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716;
  address public constant stakingRewards = 0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570;

  function _selectFork() public override {
    // IdleUSDC deposited all in compund
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16527983));
  }

  function _deployLocalContracts() internal override returns (IdleCDO _cdo) {
    address _owner = address(2);
    address _rebalancer = address(3);
    (address _strategy, ) = _deployStrategy(_owner);
    bytes[] memory _extraPath = new bytes[](1);
    _extraPath[0] = abi.encodePacked(EUL, uint24(10000), WETH, uint24(500), DAI);
    extraDataSell = abi.encode(_extraPath);
    // deploy idleCDO and tranches
    _cdo = _deployCDO();
    stdstore
      .target(address(_cdo))
      .sig(_cdo.token.selector)
      .checked_write(address(0));
    address[] memory incentiveTokens = new address[](0);
    _cdo.initialize(
      0,
      // underlying is DAI here
      DAI,
      address(this), // governanceFund,
      _owner, // owner,
      _rebalancer, // rebalancer,
      _strategy, // strategyToken
      20000 // apr split: 100000 is 100% to AA
    );

    vm.startPrank(_owner);
    _cdo.setIsAYSActive(true);
    _cdo.setUnlentPerc(0);
    _cdo.setFee(0);
    vm.stopPrank();

    _postDeploy(address(_cdo), _owner);
  }

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    _underlying = USDC;
    strategy = new IdleEulerStakingStrategyPSM();
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleEulerStakingStrategyPSM(_strategy).initialize(eToken, _underlying, EULER_MAIN, stakingRewards, _owner);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleEulerStakingStrategyPSM(address(strategy)).setWhitelistedCDO(address(_cdo));
    vm.prank(_owner);
    // we ask for quantity in DAI but we swap an USDC amount
    // in PSM, which have 6 decimals, so we set the tolerance to 
    // 100 wei of USDC 'in DAI'
    IdleCDO(_cdo).setLiquidationTolerance(10**12 * 100);
  }

  function testOnlyOwner()
    public
    override
  {
    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    IdleEulerStakingStrategyPSM(address(strategy)).setWhitelistedCDO(address(0xcafe));
  }

  function testCantReinitialize()
    external
    override
  {
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleEulerStakingStrategyPSM(address(strategy)).initialize(eToken, USDC, EULER_MAIN, stakingRewards, owner);
  }

  function testDepositsGetUSDC() 
    public
  {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    // funds in lending
    _cdoHarvest(true);

    assertEq(
      IStakingRewards(stakingRewards).balanceOf(address(strategy)), // eToken balance
      IEToken(eToken).convertUnderlyingToBalance(amount / 10**12), 
      'Not enough eTokens'
    );
  }
}