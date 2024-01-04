// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import "../../contracts/polygon-zk/strategies/gamma/IdleGammaStrategyPolygonZK.sol";
import "../../contracts/polygon-zk/IdleCDOPolygonZK.sol";
import "../../contracts/interfaces/gamma/IGammaChef.sol";
import "../../contracts/interfaces/gamma/IUniProxy.sol";
import "../../contracts/interfaces/gamma/IAlgebraPool.sol";
import "../../contracts/interfaces/gamma/IAlgebraQuoter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract TestIdleGammaStrategyPolygonZK is TestIdleCDOBase {
  using stdStorage for StdStorage;
  using SafeERC20Upgradeable for IERC20Detailed;

  uint256 internal constant SELECTED_BLOCK = 8985029;
  address internal constant WETH = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;
  address internal constant USDC = 0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
  address internal constant MATIC = 0xa2036f0538221a77A3937F1379699f44945018d0;
  address internal constant USDT = 0x1E4a5963aBFD975d8c9021ce480b42188849D41d;
  address internal constant QUICK = 0x68286607A1d43602d880D349187c3c48c0fD05E6;
  IAlgebraQuoter public constant quoter = IAlgebraQuoter(0x55BeE1bD3Eb9986f6d2d963278de09eE92a3eF1D);

  // USDT-USDC
  address internal constant GAMMA_LP_USDT_USDC = 0x145d55aE4848f9782eFCAC785A655E3e5DcE1bCD;
  address internal constant QUICK_POOL_USDT_USDC = 0x9591b8A30c3a52256ea93E98dA49EE43Afa136A8;
  uint256 internal constant PID_USDT_USDC = 8;

  address internal defaultUnderlying = GAMMA_LP_USDT_USDC;
  address internal defaultQuickswapPool = QUICK_POOL_USDT_USDC;
  uint256 internal defaultPid = PID_USDT_USDC;


  function _selectFork() public override {
    vm.selectFork(vm.createFork('polygonzk', SELECTED_BLOCK));
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOPolygonZK();
  }

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    TL_MULTISIG = 0x13854835c508FC79C3E5C5Abf7afa54b4CcC1Fdf;
    strategy = new IdleGammaStrategyPolygonZK();
    _strategy = address(strategy);
    _underlying = defaultUnderlying; 
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleGammaStrategyPolygonZK(_strategy).initialize(_underlying, defaultQuickswapPool, defaultPid, _owner);
  }

  function testQuickRewards() external {
    IdleGammaStrategyPolygonZK strat = IdleGammaStrategyPolygonZK(address(strategy));
    IUniProxy uniProxy = IUniProxy(address(strat.uniProxy()));
    address t0 = strat.token0();
    address t1 = strat.token1();
    // approve the gamma vault (not uniproxy)
    IERC20Detailed(t0).safeApprove(address(defaultUnderlying), type(uint256).max);
    IERC20Detailed(t1).safeApprove(address(defaultUnderlying), type(uint256).max);

    // send QUICK to this contract
    uint256 _amount = 10000 * 1e18;
    deal(QUICK, address(this), _amount); // ~610$ at 0.061

    // swap all QUICK for token0 
    _swap(QUICK, _amount, abi.encodePacked(QUICK, WETH, t0), 0);
  
    // half of t0Amount for token1, include also previous token0 balance
    uint256 t0Bal = balance(t0);
    uint256 amount0 = t0Bal / 2;
    // uint256 amount1Pre = t0Bal - amount0;
    console.log('...amount0 ', amount0);
    console.log('.amount1Pre', t0Bal - amount0);

    // I need to calculate the correct ratio given amount0
    // out1 is the amount of token1 that I get for half amount0
    (uint256 out1,) = quoter.quoteExactInput(abi.encodePacked(t0, t1), t0Bal - amount0);
    console.log('out1       ', out1);

    console.log('---');
    // Get amount of token1 I need to deposit amount0
    (uint256 a1Start, uint256 a1End) = uniProxy.getDepositAmount(defaultUnderlying, t0, amount0);
    uint256 amount1 = (a1Start + a1End) / 2;
    console.log('a1Start    ', a1Start);
    console.log('a1End      ', a1End);
    console.log('amount1    ', amount1);
    console.log('---');

    uint256 ratio = amount1 * 1e18 / out1;
    uint256 toLp0 = t0Bal * 1e18 / (ratio + 1e18);
    uint256 toLp1 = t0Bal - toLp0;

    console.log('ratio      ', ratio);
    console.log('toLp0      ', toLp0);
    console.log('toLp1      ', toLp1);

    _swap(t0, toLp1, abi.encodePacked(t0, t1), 0);
    // uint256 t1Received = _swap(t0, toLp1, abi.encodePacked(t0, t1), minT1);
    uint256 t1Bal = balance(t1);
    t0Bal = balance(t0);
    console.log('t1Bal      ', t1Bal);
    console.log('t0Bal      ', t0Bal);
    // /// chek only 
    // (a1Start, a1End) = uniProxy.getDepositAmount(defaultUnderlying, t0, t0Bal);
    // console.log('--');
    // console.log('a1Start    ', a1Start);
    // console.log('a1End      ', a1End);
    // // if (t1Bal > a1End) {
    // //   console.log('t1Bal > a1End');
    // //   t1Bal = a1End;
    // // } else if (t1Bal < a1Start) {
    // //   console.log('t1Bal < a1Start');
    // //   t1Bal = a1Start;
    // //   (, lp0Bal) = uniProxy.getDepositAmount(defaultUnderlying, t1, t1Bal);
    // // }

    // (uint256 a0Start, uint256 a0End) = uniProxy.getDepositAmount(defaultUnderlying, t1, t1Bal);
    // // if (t0Bal > a0End) {
    // //   console.log('t0Bal > a0End');
    // //   t0Bal = a0End;
    // // }
    // console.log('--');
    // console.log('a0Start    ', a0Start);
    // console.log('a0End      ', a0End);
    // return;

    uint[4] memory minIn;
    uint256 shares = uniProxy.deposit(t0Bal, t1Bal, address(this), defaultUnderlying, minIn);
    assertGt(shares, 0, "Shares should be > 0");
    console.log('shares     ', shares);
  }

  function balance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
  }

  function _swap(address _from, uint256 _amount, bytes memory _path, uint256 _minAmount) internal returns (uint256) {
    // zkEVM Quickswap v3 swap (algebra.finance is used so _path should not include poolFees)
    ISwapRouter _swapRouter = ISwapRouter(0xF6Ad3CcF71Abb3E12beCf6b3D2a74C963859ADCd);
    IERC20Detailed(_from).safeIncreaseAllowance(address(_swapRouter), _amount);
    // multi hop swap params
    ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
      path: _path,
      recipient: address(this),
      deadline: block.timestamp + 100,
      amountIn: _amount,
      amountOutMinimum: _minAmount
    });
    return _swapRouter.exactInput(params);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleGammaStrategyPolygonZK(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function testOnlyOwner()
    public
    override
  {
    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    IdleGammaStrategyPolygonZK(address(strategy)).setWhitelistedCDO(address(0xcafe));
  }

  function testCantReinitialize()
    external
    override
  {
    address _strategy = address(strategy);
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleGammaStrategyPolygonZK(_strategy).initialize(defaultUnderlying, defaultQuickswapPool, defaultPid, owner);
  }
}