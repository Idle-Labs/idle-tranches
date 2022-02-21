// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/convex/IBooster.sol";
import "../../interfaces/convex/IBaseRewardPool.sol";
import "../../interfaces/curve/IMainRegistry.sol";

/// @author @dantop114
/// @title ConvexStrategy
/// @notice IIdleCDOStrategy to deploy funds in Convex Finance
/// @dev This contract should not have any funds at the end of each tx.
/// The contract is upgradable, to add storage slots, add them after the last `###### End of storage VXX`
abstract contract ConvexBaseStrategy is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable,
    IIdleCDOStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;

    /// ###### Storage V1
    /// @notice one curve lp token
    /// @dev we use this as base unit of the strategy token too
    uint256 public ONE_CURVE_LP_TOKEN;
    /// @notice convex rewards pool id for the underlying curve lp token
    uint256 public poolID;
    /// @notice curve lp token to deposit in convex
    address public curveLpToken;
    /// @notice deposit token address to deposit into curve pool
    address public curveDeposit;
    /// @notice depositor contract used to deposit underlyings
    address public depositor;
    /// @notice deposit token array position
    uint256 public depositPosition;
    /// @notice convex crv rewards pool address
    address public rewardPool;
    /// @notice decimals of the underlying asset
    uint256 public curveLpDecimals;
    /// @notice Curve main registry
    address public constant MAIN_REGISTRY = address(0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5);
    /// @notice convex booster address
    address public constant BOOSTER =
        address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    /// @notice weth token address
    address public constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    /// @notice curve ETH mock address
    address public constant ETH = 
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
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

    /// @notice total LP tokens staked
    uint256 public totalLpTokensStaked;
    /// @notice total LP tokens locked
    uint256 public totalLpTokensLocked;
    /// @notice harvested LP tokens release delay
    uint256 public releaseBlocksPeriod;
    /// @notice latest harvest
    uint256 public latestHarvestBlock;

    /// ###### End of storage V1

    /// ###### Storage V2
    /// @notice blocks per year
    uint256 public BLOCKS_PER_YEAR;
    /// @notice latest harvest price gain in LP tokens
    uint256 public latestPriceIncrease;
    /// @notice latest estimated harvest interval
    uint256 public latestHarvestInterval;

    // ###################
    // Modifiers
    // ###################

    modifier onlyWhitelistedCDO() {
        require(msg.sender == whitelistedCDO, "Not whitelisted CDO");

        _;
    }

    // Used to prevent initialization of the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        curveLpToken = address(1);
    }

    // ###################
    // Initializer
    // ###################

    // Struct used to set Curve deposits
    struct CurveArgs {
        address deposit;
        address depositor;
        uint256 depositPosition;
    }

    // Struct used to initialize rewards swaps
    struct Reward {
        address reward;
        address router;
        address[] path;
    }

    // Struct used to initialize WETH -> deposit swaps
    struct Weth2Deposit {
        address router;
        address[] path;
    }

    /// @notice can only be called once
    /// @dev Initialize the upgradable contract. If `_deposit` equals WETH address, _weth2Deposit is ignored as param.
    /// @param _poolID convex pool id
    /// @param _owner owner address
    /// @param _curveArgs curve addresses and deposit details
    /// @param _rewards initial rewards (with paths and routers)
    /// @param _weth2Deposit initial WETH -> deposit paths and routers
    function initialize(
        uint256 _poolID,
        address _owner,
        uint256 _releasePeriod,
        CurveArgs memory _curveArgs,
        Reward[] memory _rewards,
        Weth2Deposit memory _weth2Deposit
    ) public initializer {
        // Sanity checks
        require(curveLpToken == address(0), "Initialized");
        require(_curveArgs.depositPosition < _curveUnderlyingsSize(), "Deposit token position invalid");

        // Initialize contracts
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        // Check Curve LP Token and Convex PoolID
        (address _crvLp, , , address _rewardPool, , bool shutdown) = IBooster(BOOSTER).poolInfo(_poolID);
        curveLpToken = _crvLp;

        // Pool and deposit asset checks
        address _deposit = _curveArgs.deposit == WETH ? ETH : _curveArgs.deposit;

        require(!shutdown, "Convex Pool is not active");
        require(_deposit == _curveUnderlyingCoins(_crvLp, _curveArgs.depositPosition), "Deposit token invalid");

        ERC20Upgradeable.__ERC20_init(
            string(abi.encodePacked("Idle ", IERC20Detailed(_crvLp).name(), " Convex Strategy")),
            string(abi.encodePacked("idleCvx", IERC20Detailed(_crvLp).symbol()))
        );

        // Set basic parameters
        poolID = _poolID;
        rewardPool = _rewardPool;
        curveLpDecimals = IERC20Detailed(_crvLp).decimals();
        ONE_CURVE_LP_TOKEN = 10**(curveLpDecimals);
        curveDeposit = _curveArgs.deposit;
        depositor = _curveArgs.depositor;
        depositPosition = _curveArgs.depositPosition;
        releaseBlocksPeriod = _releasePeriod;
        setBlocksPerYear(2465437); // given that blocks are mined at a 13.15s/block rate

        // set approval for curveLpToken
        IERC20Detailed(_crvLp).approve(BOOSTER, type(uint256).max);

        // set initial rewards
        for (uint256 i = 0; i < _rewards.length; i++) {
            addReward(_rewards[i].reward, _rewards[i].router, _rewards[i].path);
        }

        if (_curveArgs.deposit != WETH) setWeth2Deposit(_weth2Deposit.router, _weth2Deposit.path);

        // transfer ownership
        transferOwnership(_owner);
    }

    // ###################
    // Interface implementation
    // ###################

    function strategyToken() external view override returns (address) {
        return address(this);
    }

    function oneToken() external view override returns (uint256) {
        return ONE_CURVE_LP_TOKEN;
    }

    // @notice Underlying token
    function token() external view override returns (address) {
        return curveLpToken;
    }

    // @notice Underlying token decimals
    function tokenDecimals() external view override returns (uint256) {
        return curveLpDecimals;
    }

    function decimals() public view override returns (uint8) {
        return uint8(curveLpDecimals); // should be safe
    }

    // ###################
    // Public methods
    // ###################

    /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
    /// @param _amount amount of `token` to deposit
    /// @return minted amount of strategy tokens minted
    function deposit(uint256 _amount)
        external
        override
        onlyWhitelistedCDO
        returns (uint256 minted)
    {
        if (_amount > 0) {
            /// get `tokens` from msg.sender
            IERC20Detailed(curveLpToken).safeTransferFrom(msg.sender, address(this), _amount);
            minted = _depositAndMint(msg.sender, _amount, price());
        }
    }

    /// @dev msg.sender doesn't need to approve the spending of strategy token
    /// @param _amount amount of strategyTokens to redeem
    /// @return redeemed amount of underlyings redeemed
    function redeem(uint256 _amount) external onlyWhitelistedCDO override returns (uint256 redeemed) {
        if(_amount > 0) {
            redeemed = _redeem(msg.sender, _amount, price());
        }
    }

    /// @dev msg.sender should approve this contract first
    /// to spend `_amount * ONE_IDLE_TOKEN / price()` of `strategyToken`
    /// @param _amount amount of underlying tokens to redeem
    /// @return redeemed amount of underlyings redeemed
    function redeemUnderlying(uint256 _amount)
        external
        override
        onlyWhitelistedCDO
        returns (uint256 redeemed)
    {
        if (_amount > 0) {
            uint256 _cachedPrice = price();
            uint256 _shares = (_amount * ONE_CURVE_LP_TOKEN) / _cachedPrice;
            redeemed = _redeem(msg.sender, _shares, _cachedPrice);
        }
    }

    /// @notice Anyone can call this because this contract holds no strategy tokens and so no 'old' rewards
    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`.
    /// redeem rewards and transfer them to msg.sender
    /// @param _extraData extra data to be used when selling rewards for min amounts
    /// @return _balances array of minAmounts to use for swapping rewards to WETH, then weth to depositToken, then depositToken to curveLpToken
    function redeemRewards(bytes calldata _extraData)
        external
        override
        onlyWhitelistedCDO
        returns (uint256[] memory _balances)
    {
        address[] memory _convexRewards = convexRewards;
        // +2 for converting rewards to depositToken and then Curve LP Token
        _balances = new uint256[](_convexRewards.length + 2); 
        // decode params from _extraData to get the min amount for each convexRewards
        uint256[] memory _minAmountsWETH = new uint256[](_convexRewards.length);
        bool[] memory _skipSell = new bool[](_convexRewards.length);
        uint256 _minDepositToken;
        uint256 _minLpToken;
        (_minAmountsWETH, _skipSell, _minDepositToken, _minLpToken) = abi.decode(_extraData, (uint256[], bool[], uint256, uint256));

        IBaseRewardPool(rewardPool).getReward();

        address _reward;
        IERC20Detailed _rewardToken;
        uint256 _rewardBalance;
        IUniswapV2Router02 _router;

        for (uint256 i = 0; i < _convexRewards.length; i++) {
            if (_skipSell[i]) continue;

            _reward = _convexRewards[i];

            // get reward balance and safety check
            _rewardToken = IERC20Detailed(_reward);
            _rewardBalance = _rewardToken.balanceOf(address(this));

            if (_rewardBalance == 0) continue;

            _router = IUniswapV2Router02(
                rewardRouter[_reward]
            );

            // approve to v2 router
            _rewardToken.safeApprove(address(_router), 0);
            _rewardToken.safeApprove(address(_router), _rewardBalance);

            address[] memory _reward2WethPath = reward2WethPath[_reward];
            uint256[] memory _res = new uint256[](_reward2WethPath.length);
            _res = _router.swapExactTokensForTokens(
                _rewardBalance,
                _minAmountsWETH[i],
                _reward2WethPath,
                address(this),
                block.timestamp
            );
            // save in returned value the amount of weth receive to use off-chain
            _balances[i] = _res[_res.length - 1];
        }

        if (curveDeposit != WETH) {
            IERC20Detailed _weth = IERC20Detailed(WETH);
            IUniswapV2Router02 _wethRouter = IUniswapV2Router02(
                weth2DepositRouter
            );

            uint256 _wethBalance = _weth.balanceOf(address(this));
            _weth.safeApprove(address(_wethRouter), 0);
            _weth.safeApprove(address(_wethRouter), _wethBalance);

            address[] memory _weth2DepositPath = weth2DepositPath;
            uint256[] memory _res = new uint256[](_weth2DepositPath.length);
            _res = _wethRouter.swapExactTokensForTokens(
                _wethBalance,
                _minDepositToken,
                _weth2DepositPath,
                address(this),
                block.timestamp
            );
            // save in _balances the amount of depositToken to use off-chain
            _balances[_convexRewards.length] = _res[_res.length - 1];
        }

        IERC20Detailed _curveLpToken = IERC20Detailed(curveLpToken);
        uint256 _curveLpBalanceBefore = _curveLpToken.balanceOf(address(this));
        _depositInCurve(_minLpToken);
        uint256 _curveLpBalanceAfter = _curveLpToken.balanceOf(address(this));
        uint256 _gainedLpTokens = (_curveLpBalanceAfter - _curveLpBalanceBefore);

        // save in _balances the amount of curveLpTokens received to use off-chain
        _balances[_convexRewards.length + 1] = _gainedLpTokens;
        
        if (_curveLpBalanceAfter > 0) {
            // deposit in curve and stake on convex
            _stakeConvex(_curveLpBalanceAfter);

            // update locked lp tokens and apr computation variables
            latestHarvestInterval = (block.number - latestHarvestBlock);
            latestHarvestBlock = block.number;
            totalLpTokensLocked = _gainedLpTokens;
            
            // inline price increase calculation
            latestPriceIncrease = (_gainedLpTokens * ONE_CURVE_LP_TOKEN) / totalSupply();
        }
    }

    // ###################
    // Views
    // ###################

    /// @return _price net price in underlyings of 1 strategyToken
    function price() public view override returns (uint256 _price) {
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            _price = ONE_CURVE_LP_TOKEN;
        } else {
            _price =
                ((totalLpTokensStaked - _lockedLpTokens()) *
                    ONE_CURVE_LP_TOKEN) /
                _totalSupply;
        }
    }

    /// @return returns an APR estimation.
    /// @dev values returned by this method should be taken as an imprecise estimation.
    ///      For client integration something more complex should be done to have a more precise
    ///      estimate (eg. computing APR using historical APR data).
    ///      Also it does not take into account compounding (APY).
    function getApr() external view override returns (uint256) {
        // apr = rate * blocks in a year / harvest interval
        return latestPriceIncrease * (BLOCKS_PER_YEAR / latestHarvestInterval) * 100;
    }

    /// @return rewardTokens tokens array of reward token addresses
    function getRewardTokens()
        external
        view
        override
        returns (address[] memory rewardTokens) {}

    // ###################
    // Protected
    // ###################

    /// @notice Allow the CDO to pull stkAAVE rewards. Anyone can call this
    /// @return 0, this function is a noop in this strategy
    function pullStkAAVE() external pure override returns (uint256) {
        return 0;
    }

    /// @notice This contract should not have funds at the end of each tx (except for stkAAVE), this method is just for leftovers
    /// @dev Emergency method
    /// @param _token address of the token to transfer
    /// @param value amount of `_token` to transfer
    /// @param _to receiver address
    function transferToken(
        address _token,
        uint256 value,
        address _to
    ) external onlyOwner nonReentrant {
        IERC20Detailed(_token).safeTransfer(_to, value);
    }

    /// @notice This method can be used to change the value of BLOCKS_PER_YEAR
    /// @param blocksPerYear the new blocks per year value
    function setBlocksPerYear(uint256 blocksPerYear) public onlyOwner {
        require(blocksPerYear != 0, "Blocks per year cannot be zero");
        BLOCKS_PER_YEAR = blocksPerYear;
    }

    function setRouterForReward(address _reward, address _newRouter)
        external
        onlyOwner
    {
        require(_newRouter != address(0), "Router is address zero");
        rewardRouter[_reward] = _newRouter;
    }

    function setPathForReward(address _reward, address[] memory _newPath)
        external
        onlyOwner
    {
        _validPath(_newPath, WETH);
        reward2WethPath[_reward] = _newPath;
    }

    function setWeth2Deposit(address _router, address[] memory _path)
        public
        onlyOwner
    {
        address _curveDeposit = curveDeposit;

        require(_curveDeposit != WETH, "Deposit asset is WETH");

        _validPath(_path, _curveDeposit);
        weth2DepositRouter = _router;
        weth2DepositPath = _path;
    }

    function addReward(
        address _reward,
        address _router,
        address[] memory _path
    ) public onlyOwner {
        _validPath(_path, WETH);

        convexRewards.push(_reward);
        rewardRouter[_reward] = _router;
        reward2WethPath[_reward] = _path;
    }

    function removeReward(address _reward) external onlyOwner {
        address[] memory _newConvexRewards = new address[](
            convexRewards.length - 1
        );

        uint256 currentI = 0;
        for (uint256 i = 0; i < convexRewards.length; i++) {
            if (convexRewards[i] == _reward) continue;
            _newConvexRewards[currentI] = convexRewards[i];
            currentI += 1;
        }

        convexRewards = _newConvexRewards;

        delete rewardRouter[_reward];
        delete reward2WethPath[_reward];
    }

    /// @notice allow to update whitelisted address
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        whitelistedCDO = _cdo;
    }

    function setReleaseBlocksPeriod(uint256 _period) external onlyOwner {
        releaseBlocksPeriod = _period;
    }

    // ###################
    // Internal
    // ###################

    /// @dev Virtual method to override in specific pool implementation.
    /// @return number of underlying coins depending on Curve pool
    function _curveUnderlyingsSize() internal pure virtual returns (uint256);

    /// @dev Virtual method to override in specific pool implementation.
    ///      This method should implement the deposit in the curve pool.
    function _depositInCurve(uint256 _minLpTokens) internal virtual;

    /// @dev Virtual method to override if needed (eg. pool address is equal to lp token address)
    /// @return address of pool from LP token
    function _curvePool(address _curveLpToken) internal view virtual returns (address) {
        return IMainRegistry(MAIN_REGISTRY).get_pool_from_lp_token(_curveLpToken);
    }

    /// @dev Virtual method to override if needed (eg. pool is not in the main registry)
    /// @return address of the nth underlying coin for _curveLpToken
    function _curveUnderlyingCoins(address _curveLpToken, uint256 _position) internal view virtual returns (address) {
        address[8] memory _coins = IMainRegistry(MAIN_REGISTRY).get_underlying_coins(_curvePool(_curveLpToken));
        return _coins[_position];
    }

    /// @notice Internal helper function to deposit in convex and update total LP tokens staked
    /// @param _lpTokens number of LP tokens to stake
    function _stakeConvex(uint256 _lpTokens) internal {
        // update total staked lp tokens and deposit in convex
        totalLpTokensStaked += _lpTokens;
        IBooster(BOOSTER).depositAll(poolID, true);
    }

    /// @notice Internal function to deposit in the Convex Booster and mint shares
    /// @dev Used for deposit and during an harvest
    /// @param _lpTokens amount to mint
    /// @param _price we give the price as input to save on gas when calculating price
    function _depositAndMint(
        address _account,
        uint256 _lpTokens,
        uint256 _price
    ) internal returns (uint256 minted) {
        // deposit in convex
        _stakeConvex(_lpTokens);

        // mint strategy tokens to msg.sender
        minted = (_lpTokens * ONE_CURVE_LP_TOKEN) / _price;
        _mint(_account, minted);
    }

    /// @dev msg.sender does not need to approve this contract to spend `_amount` of `strategyToken`
    /// @param _shares amount of strategyTokens to redeem
    /// @param _price we give the price as input to save on gas when calculating price
    /// @return redeemed amount of underlyings redeemed
    function _redeem(
        address _account,
        uint256 _shares,
        uint256 _price
    ) internal returns (uint256 redeemed) {
        // update total staked lp tokens
        redeemed = (_shares * _price) / ONE_CURVE_LP_TOKEN;
        totalLpTokensStaked -= redeemed;

        IERC20Detailed _curveLpToken = IERC20Detailed(curveLpToken);

        // burn strategy tokens for the msg.sender
        _burn(_account, _shares);

        // exit reward pool (without claiming) and unwrap staking position
        IBaseRewardPool(rewardPool).withdraw(redeemed, false);
        IBooster(BOOSTER).withdraw(poolID, redeemed);

        // transfer underlying lp tokens to msg.sender
        _curveLpToken.safeTransfer(_account, redeemed);
    }

    function _lockedLpTokens() internal view returns (uint256 _locked) {
        uint256 _releaseBlocksPeriod = releaseBlocksPeriod;
        uint256 _blocksSinceLastHarvest = block.number - latestHarvestBlock;
        uint256 _totalLockedLpTokens = totalLpTokensLocked;

        if (_totalLockedLpTokens > 0 && _blocksSinceLastHarvest < _releaseBlocksPeriod) {
            // progressively release harvested rewards
            _locked = _totalLockedLpTokens * (_releaseBlocksPeriod - _blocksSinceLastHarvest) / _releaseBlocksPeriod;
        }
    }

    function _validPath(address[] memory _path, address _out) internal pure {
        require(_path.length >= 2, "Path length less than 2");
        require(_path[_path.length - 1] == _out, "Last asset should be WETH");
    }
}
