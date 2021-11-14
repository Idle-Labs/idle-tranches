// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

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

    /// ###### End of storage V1

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
        CurveArgs memory _curveArgs,
        Reward[] memory _rewards,
        Weth2Deposit memory _weth2Deposit
    ) public initializer {
        require(curveLpToken == address(0), "Initialized");
        require(_curveArgs.depositPosition < _curveUnderlyingsSize(), "Deposit token position invalid");

        // Initialize contracts
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        // Check Curve LP Token and Convex PoolID
        (address _crvLp, , , address _rewardPool, , bool shutdown) = IBooster(BOOSTER).poolInfo(_poolID);

        // Check if Convex pool is active
        require(!shutdown, "Convex Pool is not active");

        ERC20Upgradeable.__ERC20_init(
            string(abi.encodePacked("Idle ", IERC20Detailed(_crvLp).name(), " Convex Strategy")),
            string(abi.encodePacked("idleCvx", IERC20Detailed(_crvLp).symbol()))
        );

        // Set basic parameters
        curveLpToken = _crvLp;
        poolID = _poolID;
        rewardPool = _rewardPool;
        curveLpDecimals = IERC20Detailed(_crvLp).decimals();
        ONE_CURVE_LP_TOKEN = 10**(curveLpDecimals);
        curveDeposit = _curveArgs.deposit;
        depositor = _curveArgs.depositor;
        depositPosition = _curveArgs.depositPosition;

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

    function strategyToken() external view override returns(address) {
        return address(this);
    }

    function oneToken() external view override returns (uint256) {
        return ONE_CURVE_LP_TOKEN;
    }

    function token() external view override returns (address) {
        return curveLpToken;
    }

    function tokenDecimals() external view override returns (uint256) {
        return curveLpDecimals;
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
            IERC20Detailed(curveLpToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            /// deposit those in convex and stake
            IBooster(BOOSTER).depositAll(poolID, true);
            /// mint strategy tokens to msg.sender
            _mint(msg.sender, _amount);

            minted = _amount;
        }
    }

    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
    /// @param _amount amount of strategyTokens to redeem
    /// @return amount of underlyings redeemed
    function redeem(uint256 _amount) external override returns (uint256) {
        return _redeem(_amount);
    }

    /// @notice Anyone can call this because this contract holds no strategy tokens and so no 'old' rewards
    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`.
    /// redeem rewards and transfer them to msg.sender
    function redeemRewards()
        external
        override
        onlyWhitelistedCDO
        returns (uint256[] memory _balances)
    {
        IBaseRewardPool(rewardPool).getReward();

        for (uint256 i = 0; i < convexRewards.length; i++) {
            address _reward = convexRewards[i];

            // get reward balance and safety check
            IERC20Detailed _rewardToken = IERC20Detailed(_reward);
            uint256 _rewardBalance = _rewardToken.balanceOf(address(this));

            if (_rewardBalance == 0) continue;

            IUniswapV2Router02 _router = IUniswapV2Router02(
                rewardRouter[_reward]
            );

            // approve to v2 router
            _rewardToken.safeApprove(address(_router), 0);
            _rewardToken.safeApprove(address(_router), _rewardBalance);

            // we accept 1 as minimum because this is executed by a trusted CDO
            _router.swapExactTokensForTokens(
                _rewardBalance,
                1,
                reward2WethPath[_reward],
                address(this),
                block.timestamp
            );
        }

        if (curveDeposit != WETH) {
            IERC20Detailed _weth = IERC20Detailed(WETH);
            IUniswapV2Router02 _wethRouter = IUniswapV2Router02(
                weth2DepositRouter
            );

            uint256 _wethBalance = _weth.balanceOf(address(this));
            _weth.safeApprove(address(_wethRouter), 0);
            _weth.safeApprove(address(_wethRouter), _wethBalance);

            _wethRouter.swapExactTokensForTokens(
                _wethBalance,
                1,
                weth2DepositPath,
                address(this),
                block.timestamp
            );
        }

        _depositInCurve();

        IERC20Detailed _curveLpToken = IERC20Detailed(curveLpToken);
        uint256 _curveLpBalance = _curveLpToken.balanceOf(address(this));
        _curveLpToken.safeTransfer(whitelistedCDO, _curveLpBalance);

        _balances = new uint256[](1);
        _balances[0] = _curveLpBalance;
    }

    /// @dev msg.sender should approve this contract first
    /// to spend `_amount * ONE_IDLE_TOKEN / price()` of `strategyToken`
    /// @param _amount amount of underlying tokens to redeem
    /// @return amount of underlyings redeemed
    function redeemUnderlying(uint256 _amount)
        external
        override
        returns (uint256)
    {
        // we are getting price before transferring so price of msg.sender
        return _redeem(_amount);
    }

    // ###################
    // Views
    // ###################

    /// @return net price in underlyings of 1 strategyToken
    function price() public view override returns (uint256) {
        return ONE_CURVE_LP_TOKEN;
    }

    /// @return returns 0, don't know if there are ways you can calculate APR on-chain for Convex
    function getApr() external pure override returns (uint256) {
        return 0;
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

    // ###################
    // Internal
    // ###################

    /// @return number of underlying coins depending on Curve pool
    function _curveUnderlyingsSize() internal virtual returns (uint256);

    /// @notice Virtual method that implements deposit in Curve
    function _depositInCurve() internal virtual;

    /// @return address of pool from LP token
    function _curvePool() internal returns (address) {        
        return IMainRegistry(MAIN_REGISTRY).get_pool_from_lp_token(curveLpToken);
    }

    /// @dev msg.sender does not need to approve this contract to spend `_amount` of `strategyToken`
    /// @param _amount amount of strategyTokens to redeem
    /// @return redeemed amount of underlyings redeemed
    function _redeem(uint256 _amount)
        internal
        onlyWhitelistedCDO
        returns (uint256 redeemed)
    {
        if (_amount > 0) {
            IERC20Detailed _curveLpToken = IERC20Detailed(curveLpToken);

            // burn strategy tokens for the msg.sender
            _burn(msg.sender, _amount);
            // exit reward pool (without claiming)
            IBaseRewardPool(rewardPool).withdraw(_amount, false);
            // withdraw underlying lp tokens from Convex Booster
            IBooster(BOOSTER).withdraw(poolID, _amount);

            // get current balance and transfer it
            redeemed = _curveLpToken.balanceOf(address(this));

            // transfer underlying lp tokens to msg.sender
            _curveLpToken.safeTransfer(msg.sender, redeemed);
        }
    }

    function _validPath(address[] memory _path, address _out) internal pure {
        require(_path.length >= 2, "Path length less than 2");
        require(_path[_path.length - 1] == _out, "Last asset should be WETH");
    }
}
