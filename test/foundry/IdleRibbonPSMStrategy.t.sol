// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import "../../contracts/strategies/ribbon/IdleRibbonPSMStrategy.sol";

contract TestIdleRibbonPSMStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;
  address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public constant RBN = 0x6123B0049F904d730dB3C36a31167D9d4121fA6B;
  // ribbon Windermute USDC pool
  address public constant cpToken = 0x0Aea75705Be8281f4c24c3E954D1F8b1D0f8044C;

  function _selectFork() public override {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 15831007));
  }

  function _deployLocalContracts() internal override returns (IdleCDO _cdo) {
    address _owner = address(2);
    address _rebalancer = address(3);
    (address _strategy, ) = _deployStrategy(_owner);
    bytes[] memory _extraPath = new bytes[](1);
    _extraPath[0] = abi.encodePacked(RBN, uint24(3000), USDC, uint24(100), DAI);
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

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address univ2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    strategy = new IdleRibbonPSMStrategy();
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleRibbonPSMStrategy(_strategy).initialize(cpToken, _underlying, _owner, univ2Router);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleRibbonPSMStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
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
    IdleRibbonPSMStrategy(address(strategy)).setWhitelistedCDO(address(0xcafe));
  }

  function testCantReinitialize()
    external
    override
  {
    address _strategy = address(strategy);
    address univ2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleRibbonPSMStrategy(_strategy).initialize(
      address(1),
      address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D),
      owner,
      univ2Router
    );
  }

  function testDepositsGetUSDC() 
    public
  {
    uint256 oneToken = 10**6; // 1 USDC
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);

    // funds in lending
    _cdoHarvest(true); 
    uint256 cpBal = IERC20(cpToken).balanceOf(address(strategy));
    uint256 cpPrice = IPoolMaster(cpToken).getCurrentExchangeRate();
    assertEq(cpBal, amount * oneToken / cpPrice, 'Not enough cpTokens');
  }
}