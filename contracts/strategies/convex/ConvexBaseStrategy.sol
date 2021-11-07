// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/convex/IBooster.sol";
import "../../interfaces/convex/IBaseRewardPool.sol";

/// @author @dantop114
/// @title ConvexStrategy
/// @notice IIdleCDOStrategy to deploy funds in Convex Finance
/// @dev This contract should not have any funds at the end of each tx.
/// The contract is upgradable, to add storage slots, add them after the last `###### End of storage VXX`
abstract contract ConvexBaseStrategy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC20Upgradeable, IIdleCDOStrategy {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// ###### Storage V1
  /// @notice one curve lp token
  uint256 public ONE_CURVE_LP_TOKEN;
  /// @notice convex rewards pool id for the underlying curve lp token
  uint256 public poolID;
  /// @notice curve lp token to deposit in convex
  address public curvePool;
  /// @notice curve pool ERC20 contract
  IERC20Detailed public curvePoolToken;
  /// @notice deposit token address to deposit into curve pool
  address public curveDeposit;
  /// @notice deposit token array position
  uint256 public depositPosition;
  /// @notice convex crv rewards pool address
  address public rewardPool;
  /// @notice address of the tokenized strategy position, in this case this contract address
  address public override strategyToken;
  /// @notice decimals of the underlying asset
  uint256 public curvePoolDecimals;
  /// @notice convex booster address
  address internal constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
  /// @notice weth token address
  address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  /// @notice whitelisted CDO for this strategy
  address public whitelistedCDO;

  /// @notice convex rewards for this specific lp token (cvx should be included in this list)
  address[] public convexRewards;
  /// @notice WETH to deposit token path
  address[] public weth2DepositPath;  
  /// @notice univ2 router for weth to deposit swap
  address public weth2DepositRouter;
  /// @notice reward liquidation to WETH path
  mapping(address => address[]) public reward2WethPath;
  /// @notice univ2-like router for each reward
  mapping(address => address) public rewardRouter;

  /// @notice this contract rewards (should include only curve pool token address)
  address[] public rewards;

  /// ###### End of storage V1

  // ###################
  // Modifiers
  // ###################

  modifier onlyWhitelistedCDO {
    require(msg.sender == whitelistedCDO, "Not whitelisted CDO");

    _;
  }

  // Used to prevent initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    curvePool = address(1);
  }

  // ###################
  // Initializer
  // ###################

  /// @notice can only be called once
  /// @dev Initialize the upgradable contract
  /// @param _poolID convex pool id
  /// @param _deposit deposit token to use for Curve pool
  /// @param _owner owner address
  function initialize(uint256 _poolID, address _deposit, uint256 _depositPosition, address _owner) public initializer {
    require(curvePool == address(0), 'Initialized');
    require(_depositPosition < _curveUnderlyingsSize(), 'Deposit token position invalid');

    // Initialize contracts
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    
    // Check Curve LP Token and Convex PoolID
    (address _crvLp,,, address _rewardPool,, bool shutdown) = IBooster(BOOSTER).poolInfo(_poolID);
    
    // Check if Convex pool is active
    require(!shutdown, 'Convex Pool is not active');

    string memory _name = string(abi.encodePacked("Idle ", curvePoolToken.name(), " Convex Strategy"));
    string memory _symbol = string(abi.encodePacked("idleCvx", curvePoolToken.symbol()));
    ERC20Upgradeable.__ERC20_init(_name, _symbol);

    // Set basic parameters
    curvePool = _crvLp;
    poolID = _poolID;
    rewardPool = _rewardPool;
    strategyToken = address(this); // this contract is tokenizing the position
    curvePoolDecimals = IERC20Detailed(curvePool).decimals();
    ONE_CURVE_LP_TOKEN = 10**(curvePoolDecimals);
    curveDeposit = _deposit;
    depositPosition = _depositPosition;

    // set rewards to give back to CDO 
    rewards.push(curvePool);

    // transfer ownership
    transferOwnership(_owner);
  }

  // ###################
  // Interface implementation
  // ###################

  function oneToken() external override view returns(uint256) {
    return ONE_CURVE_LP_TOKEN;
  }

  function token() external override view returns(address) {
    return curvePool;
  }

  function tokenDecimals() external override view returns(uint256) {
    return curvePoolDecimals;
  }

  // ###################
  // Public methods
  // ###################

  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return minted amount of strategy tokens minted
  function deposit(uint256 _amount) external onlyWhitelistedCDO override returns (uint256 minted) {
    if (_amount > 0) {
      /// get `tokens` from msg.sender
      curvePoolToken.safeTransferFrom(msg.sender, address(this), _amount);
      /// deposit those in convex and stake
      IBooster(BOOSTER).depositAll(poolID, true);
      /// mint strategy tokens to msg.sender
      _mint(msg.sender, _amount);
    }

    return _amount;
  }

  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
  /// @param _amount amount of strategyTokens to redeem
  /// @return amount of underlyings redeemed
  function redeem(uint256 _amount) external override returns(uint256) {
    return _redeem(_amount);
  }

  /// @notice Anyone can call this because this contract holds no strategy tokens and so no 'old' rewards
  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`. 
  /// redeem rewards and transfer them to msg.sender
  function redeemRewards() external onlyWhitelistedCDO override returns (uint256[] memory _balances) {
    IBaseRewardPool(rewardPool).getReward();

    for(uint256 i = 0; i < convexRewards.length; i++) {
      address _reward = convexRewards[i];
      
      // get reward balance and safety check
      IERC20Detailed _rewardToken = IERC20Detailed(_reward);
      uint256 _rewardBalance = _rewardToken.balanceOf(address(this));

      if(_rewardBalance == 0) continue;

      IUniswapV2Router02 _router = IUniswapV2Router02(rewardRouter[_reward]);

      // approve to v2 router
      _rewardToken.safeApprove(address(_router), 0);
      _rewardToken.safeApprove(address(_router), _rewardBalance);

      // we accept 1 as minimum because this is executed by a trusted CDO
      _router.swapExactTokensForTokens(_rewardBalance, 1, reward2WethPath[_reward], address(this), block.timestamp);
    }

    IERC20Detailed _weth = IERC20Detailed(WETH);
    IUniswapV2Router02 _wethRouter = IUniswapV2Router02(weth2DepositRouter);
    
    uint256 _wethBalance = _weth.balanceOf(address(this));
    _weth.safeApprove(address(_wethRouter), 0);
    _weth.safeApprove(address(_wethRouter), _wethBalance);

    _wethRouter.swapExactTokensForTokens(_wethBalance, 1, weth2DepositPath, address(this), block.timestamp);

    _curveDeposit();

    IERC20Detailed _curvePool = IERC20Detailed(curvePool);
    uint256 _curvePoolBalance = _curvePool.balanceOf(address(this));
    _curvePool.safeTransfer(whitelistedCDO, _curvePoolBalance);

    _balances = new uint256[](1);
    _balances[0] = _curvePoolBalance;
  }

  /// @dev msg.sender should approve this contract first
  /// to spend `_amount * ONE_IDLE_TOKEN / price()` of `strategyToken`
  /// @param _amount amount of underlying tokens to redeem
  /// @return amount of underlyings redeemed
  function redeemUnderlying(uint256 _amount) external override returns(uint256) {
    // we are getting price before transferring so price of msg.sender
    return _redeem(_amount);
  }

  // ###################
  // Internal
  // ###################

  /// @return N_COINS for curve pool
  function _curveUnderlyingsSize() virtual internal returns(uint256);

  function _curveDeposit() virtual internal;


  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
  /// @param _amount amount of strategyTokens to redeem
  /// @return redeemed amount of underlyings redeemed
  function _redeem(uint256 _amount) internal onlyWhitelistedCDO returns(uint256 redeemed) {
    if (_amount > 0) {
      IERC20Detailed _curvePoolToken = curvePoolToken;
      
      // burn strategy tokens for the msg.sender
      _burn(msg.sender, _amount);

      // withdraw underlying lp tokens from Convex Booster
      IBooster(BOOSTER).withdraw(poolID, _amount);
      
      // check for balance and transfer it
      redeemed = _curvePoolToken.balanceOf(address(this));
      require(redeemed == _amount, "Wrong amount withdrawn");

      // transfer underlying lp tokens to msg.sender
      _curvePoolToken.safeTransfer(msg.sender, redeemed);
    }

    return redeemed;
  }

  // ###################
  // Views
  // ###################

  /// @return net price in underlyings of 1 strategyToken
  function price() public override view returns(uint256) {
    return ONE_CURVE_LP_TOKEN;
  }

  /// @return returns 0, don't know if there are ways you can calculate APR on-chain for Convex
  function getApr() external override pure returns(uint256) {
      return 0;
  }

  /// @return tokens array of reward token addresses
  function getRewardTokens() external override view returns(address[] memory) {
    return rewards;
  }

  // ###################
  // Protected
  // ###################

  /// @notice Allow the CDO to pull stkAAVE rewards. Anyone can call this
  /// @return 0, this function is a noop in this strategy
  function pullStkAAVE() external pure override returns(uint256) {
    return 0;
  }

  /// @notice This contract should not have funds at the end of each tx (except for stkAAVE), this method is just for leftovers
  /// @dev Emergency method
  /// @param _token address of the token to transfer
  /// @param value amount of `_token` to transfer
  /// @param _to receiver address
  function transferToken(address _token, uint256 value, address _to) external onlyOwner nonReentrant {
    IERC20Detailed(_token).safeTransfer(_to, value);
  }

  function setRouterForReward(address _reward, address _newRouter) external onlyOwner {
    require(rewardRouter[_reward] != address(0), "Router not set for reward");
    rewardRouter[_reward] = _newRouter;
  }

  function setPathForReward(address _reward, address[] memory _newPath) external onlyOwner {
    require(reward2WethPath[_reward].length > 0, "Path not set for reward");
    reward2WethPath[_reward] = _newPath;
  }

  function setWeth2Deposit(address _router, address[] memory _weth2DepositPath) external onlyOwner {
    weth2DepositRouter = _router;
    weth2DepositPath = _weth2DepositPath;
  }

  function addReward(address _reward, address _router, address[] memory _path) external onlyOwner {
    require(_path.length > 0, "Path length equals 0");

    convexRewards.push(_reward);
    rewardRouter[_reward] = _router;
    reward2WethPath[_reward] = _path;
  }

  function removeReward(address _reward) external onlyOwner {
    address[] memory _newConvexRewards = new address[](convexRewards.length - 1);
    
    uint256 currentI = 0;
    for(uint256 i = 0; i < convexRewards.length; i++) {
      if(convexRewards[i] == _reward) continue;
      _newConvexRewards[currentI] = convexRewards[i];
      currentI += 1;
    }

    convexRewards = _newConvexRewards;

    delete rewardRouter[_reward];
    delete reward2WethPath[_reward];
  }

  /// @notice allow to update address whitelisted to pull stkAAVE rewards
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    whitelistedCDO = _cdo;
  }
}