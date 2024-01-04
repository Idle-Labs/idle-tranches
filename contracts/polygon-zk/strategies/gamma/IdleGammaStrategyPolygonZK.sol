// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../../interfaces/IIdleCDOStrategy.sol";
import "../../../interfaces/IERC20Detailed.sol";
import "../../../interfaces/gamma/IGammaChef.sol";
import "../../../interfaces/gamma/IUniProxy.sol";
import "../../../interfaces/gamma/IAlgebraPool.sol";
import "../../../interfaces/gamma/IAlgebraQuoter.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract IdleGammaStrategyPolygonZK is
  Initializable,
  OwnableUpgradeable,
  ERC20Upgradeable,
  ReentrancyGuardUpgradeable,
  IIdleCDOStrategy
{
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice gamma vault address (Hypervisor) eg 0x145d55ae4848f9782efcac785a655e3e5dce1bcd for USDT-USDC
  address public override token;

  /// @notice decimals of the underlying asset
  uint256 public override tokenDecimals;

  /// @notice one underlying token
  uint256 public override oneToken;

  /// @notice underlying ERC20 token contract (pool currency for Clearpool)
  IERC20Detailed public underlyingToken;

  /// @notice address of the IdleCDO
  address public idleCDO;

  /// @notice one year, used to calculate the APR
  uint256 public constant YEAR = 365 days;

  /// @notice address of the governance token (here QUICK / dQUICK?)
  address public govToken;

  address private constant WETH = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;
  address private constant USDT = 0x1E4a5963aBFD975d8c9021ce480b42188849D41d;
  address private constant USDC = 0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
  // address internal constant QUICK_V3_FACTORY = 0x4B9f4d2435Ef65559567e5DbFC1BbB37abC43B57;
  uint256 internal constant EXP_SCALE = 1e18;

  /// Gamma specific vars
  address private constant QUICK = 0x68286607A1d43602d880D349187c3c48c0fD05E6;
  /// @notice address of the quickswap algebra pool. Get it from 
  /// https://docs.gamma.xyz/gamma/learn/scans#vault-hypervisor-contracts or Gamma UI
  address public quickswapPool;
  /// @notice address proxy contract for depositing underlyings into gamma vault
  IUniProxy public constant uniProxy = IUniProxy(0x8480199E5D711399ABB4D51bDa329E064c89ad77);
  /// @notice address used for staking the LP tokens and get rewards
  IGammaChef public constant gammaChef = IGammaChef(0x1e2D8f84605D32a2CBf302E30bFd2387bAdF35dD);
  /// @notice index of the pool in the gammaChef contract (fetch via ZKUtils test)
  uint256 public gammaChefPid;
  /// @notice address of the LP token underlyings
  address public token0;
  address public token1;

  /// @notice address used to get rewards
  IAlgebraQuoter public constant quoter = IAlgebraQuoter(0x55BeE1bD3Eb9986f6d2d963278de09eE92a3eF1D);


  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    token = address(1);
  }

  /// @notice can be only called once
  /// @param _underlyingToken address of the underlying token (pool currency)
  /// @param _quickswapPool address of the quickswap pool
  /// @param _pid index of the pool in the gammaChef contract (fetch via ZKUtils.sol test)
  /// @param _owner address of the owner of the strategy
  function initialize(
    address _underlyingToken,
    address _quickswapPool,
    uint256 _pid,
    address _owner
  ) public virtual initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    require(token == address(0), "Token is already initialized");

    //----- // -------//
    quickswapPool = _quickswapPool;
    token = _underlyingToken;
    underlyingToken = IERC20Detailed(token);
    tokenDecimals = underlyingToken.decimals();
    oneToken = 10**(tokenDecimals);
    govToken = QUICK;

    gammaChefPid = _pid;
    token0 = IAlgebraPool(_quickswapPool).token0();
    token1 = IAlgebraPool(_quickswapPool).token1();

    ERC20Upgradeable.__ERC20_init(
      string(abi.encodePacked("Idle Gamma Strategy Token - ", IERC20Detailed(_underlyingToken).name())),
      string(abi.encodePacked("idle_", IERC20Detailed(_underlyingToken).symbol()))
    );
    //------//-------//
    underlyingToken.safeApprove(address(gammaChef), type(uint256).max);
    // approve gamma vault (not uniproxy) to get underlyings
    IERC20Detailed(token0).safeApprove(address(uniProxy), type(uint256).max);
    IERC20Detailed(token1).safeApprove(address(uniProxy), type(uint256).max);
    transferOwnership(_owner);
  }

  /// @notice strategy token address
  function strategyToken() external view override returns (address) {
    return address(this);
  }

  /// @notice redeem the rewards. Claims reward as per the _extraData
  /// @dev check that a path in quickswap v3 exists for the reward token to underlying
  /// @param _extraData encoded data with the min amount of LP tokens to receive for QUICK
  /// @return rewards we return an array with 2 elements
  /// - rewards[0] = amount of QUICK received
  /// - rewards[1] = amount of LP tokens minted for QUICK
  /// in this way we don't need to check min amounts received for each single swap
  /// but we do a single check at the end as we simulated the tx before to get the min 
  /// shares amount that should be minted and pass this value in _extraData
  function redeemRewards(bytes calldata _extraData)
    external
    override
    onlyIdleCDO
    returns (uint256[] memory rewards)
  {
    // Get QUICK rewards to this contract
    gammaChef.harvest(gammaChefPid, address(this));
    uint256 _amount = IERC20Detailed(govToken).balanceOf(address(this));

    // swap all QUICK for token0 
    address _token = token0;
    address t0 = token0;
    address t1 = token1;
    bytes memory path = t0 == WETH ? abi.encodePacked(QUICK, WETH) : abi.encodePacked(QUICK, t0);
    // we pass 0 here as we check that the LP minted are correct at the end
    _swap(QUICK, _amount, path, 0);

    // we try to sell half of t0Amount for token1 (include also previous token0 balance)
    uint256 toLp1 = _calcToken1SwapBalance(_token, t0, t1);

    // swap the calculated amount of token0 for token1
    // we pass 0 here as we check that the LP minted are correct at the end
    _swap(t0, toLp1, abi.encodePacked(t0, t1), 0);

    uint256 t1Bal = balance(t1);
    uint256 t0Bal = balance(t0);
    // TODO check if amounts are ok ie within boundaries



    // convert underlying in LP tokens (minIn is 0, we check at the end)
    (uint256 minShares) = abi.decode(_extraData, (uint256));
    uint[4] memory minIn;
    uint256 shares = uniProxy.deposit(t0Bal, t1Bal, address(this), _token, minIn);
    require(shares >= minShares, "Not enough shares");

    // stake the LP tokens in the pool and mint the equivalent strategyTokens to IdleCDO
    _mint(msg.sender, _depositAmount(IERC20Detailed(_token), shares));
  
    // return number of QUICK received and LP tokens minted for harvester bot
    rewards = new uint256[](2);
    rewards[0] = _amount;
    rewards[1] = shares;
  }

  /// @notice internal function to calculate the amount of token0 to swap for token1
  /// @param vault address of the vault (LP token) of Gamma
  /// @param t0 address of the token0
  /// @param t1 address of the token1
  /// @return toLp1 amount of token0 to swap for token1
  function _calcToken1SwapBalance(address vault, address t0, address t1) internal returns (uint256 toLp1) {
    uint256 t0Bal = balance(t0);
    uint256 amount0 = t0Bal / 2;
    // We need to calculate the correct ratio of amount1 given amount0
    (uint256 out1, ) = quoter.quoteExactInput(abi.encodePacked(t0, t1), t0Bal - amount0);
    // Get amount of token1 I need to deposit amount0
    (uint256 a1Start, uint256 a1End) = uniProxy.getDepositAmount(vault, t0, amount0);
    uint256 amount1 = (a1Start + a1End) / 2;
    // calculate the ratio between amount1 and out1
    uint256 ratio = amount1 * 1e18 / out1;
    uint256 toLp0 = t0Bal * 1e18 / (ratio + 1e18);
    toLp1 = t0Bal - toLp0;
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

  /// @notice unused in harvest strategy
  function pullStkAAVE() external pure override returns (uint256) {
    return 0;
  }

  /// @notice return the price from the strategy token contract
  /// @return price
  function price() public view virtual override returns (uint256) {
    return oneToken;
  }

  /// @notice Get the reward token
  /// @return array of reward token
  function getRewardTokens()
    external
    view
    override
    returns (address[] memory)
  {
    address[] memory govTokens = new address[](1);
    govTokens[0] = govToken;
    return govTokens;
  }

  function getApr() external view returns (uint256) {
    // // CPOOL per second (clearpool's contract has typo)
    // IPoolMaster _cpToken = IPoolMaster(cpToken);
    // uint256 rewardSpeed = _cpToken.rewardPerSecond();
    // uint256 rewardRate;
    // if (rewardSpeed > 0) {
    //     // Underlying tokens equivalent of rewards
    //     uint256 annualRewards = (rewardSpeed *
    //         YEAR *
    //         _tokenToUnderlyingRate()) / 10**18;
    //     // Pool's TVL as underlying tokens
    //     uint256 poolTVL = (IERC20Detailed(address(_cpToken)).totalSupply() *
    //         _cpToken.getCurrentExchangeRate()) / 10**18;
    //     // Annual rewards rate (as clearpool's 18-precision decimal)
    //     rewardRate = (annualRewards * 10**18) / poolTVL;
    // }

    // // Pool's annual interest rate
    // uint256 poolRate = _cpToken.getSupplyRate() * YEAR;

    // return (poolRate + rewardRate) * 100;
  }

  /// @notice Redeem Tokens
  /// @param _amount amount of LP tokens to redeem (LP tokens have price eq to 1)
  /// @return Amount of underlying tokens received
  function redeem(uint256 _amount)
    external
    override
    onlyIdleCDO
    returns (uint256)
  {
    return _amount > 0 ? _redeem(_amount) : 0;
  }

  /// @notice Redeem Tokens
  /// @dev price is oneToken so method is the same as redeem
  /// @param _amount amount of underlying tokens to redeem
  /// @return Amount of underlying tokens received
  function redeemUnderlying(uint256 _amount)
    external
    onlyIdleCDO
    returns (uint256)
  {
    return _amount > 0 ? _redeem(_amount) : 0;
  }

  /// @notice Internal function to redeem the underlying tokens
  /// @param _amount of LP tokens to redeem
  /// @return balanceReceived Amount of underlying tokens received
  function _redeem(uint256 _amount)
      virtual
      internal
      returns (uint256 balanceReceived)
  {
    // strategyToken (ie this contract) has 18 decimals
    _burn(msg.sender, (_amount * EXP_SCALE) / oneToken);
    IERC20Detailed _underlyingToken = underlyingToken;
    uint256 balanceBefore = _underlyingToken.balanceOf(address(this));
    // we could pass msg.sender here but we send underlyings here first 
    // to properly set the return value `balanceReceived`
    gammaChef.withdraw(gammaChefPid, _amount, address(this));
    balanceReceived = _underlyingToken.balanceOf(address(this)) - balanceBefore;
    _underlyingToken.safeTransfer(msg.sender, balanceReceived);
  }

  /// @notice Deposit the underlying token to vault
  /// @param _amount number of LP tokens to deposit
  /// @return minted number of reward tokens minted
  function deposit(uint256 _amount)
    external
    virtual
    override
    onlyIdleCDO
    returns (uint256 minted)
  {
    if (_amount > 0) {
      IERC20Detailed _underlyingToken = underlyingToken;
      _underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
      minted = _depositAmount(_underlyingToken, _amount);
      _mint(msg.sender, minted);
    }
  }

  /// @notice Deposit the underlying token to staking contract
  /// @param _token underlying LP token
  /// @param _amount number of LP tokens to stake
  /// @return minted number of LP tokens actually staked
  function _depositAmount(IERC20Detailed _token, uint256 _amount) internal returns (uint256 minted) {
    uint256 balanceBefore = _token.balanceOf(address(this));
    gammaChef.deposit(gammaChefPid, _amount, address(this));
    minted = (_token.balanceOf(address(this)) - balanceBefore) * EXP_SCALE / oneToken;
  }

  /// @notice allow to update whitelisted address
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    idleCDO = _cdo;
  }

  /// @notice Modifier to make sure that caller os only the idleCDO contract
  modifier onlyIdleCDO() {
    require(idleCDO == msg.sender, "Only IdleCDO can call");
    _;
  }
}
