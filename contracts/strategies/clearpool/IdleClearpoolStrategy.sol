// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/clearpool/IPoolFactory.sol";
import "../../interfaces/clearpool/IPoolMaster.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract IdleClearpoolStrategy is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IIdleCDOStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice underlying token address (pool currency for Clearpool)
    address public override token;

    /// @notice strategy token address (lending pool address for Clearpool)
    address public cpToken;

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

    /// @notice address of the governance token (here CPOOL)
    address public govToken;

    /// @notice latest saved apr
    uint256 public lastApr;

    /// @notice UniswapV2 router, used for APY calculation
    IUniswapV2Router02 public uniswapRouter;
    
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice can be only called once
    /// @param _cpToken address of the strategy token (lending pool)
    /// @param _underlyingToken address of the underlying token (pool currency)
    function initialize(
        address _cpToken,
        address _underlyingToken,
        address _owner,
        address _uniswapV2Router
    ) public virtual initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        cpToken = _cpToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        govToken = IPoolMaster(_cpToken).factory().cpool();

        ERC20Upgradeable.__ERC20_init(
            "Idle Clearpool Strategy Token",
            string(abi.encodePacked("idle_", IERC20Detailed(_cpToken).symbol()))
        );
        //------//-------//

        uniswapRouter = IUniswapV2Router02(_uniswapV2Router);

        transferOwnership(_owner);
    }

    /// @notice strategy token address
    function strategyToken() external view override returns (address) {
        return address(this);
    }

    /// @notice redeem the rewards. Claims reward as per the _extraData
    /// @return rewards amount of reward that is deposited to vault
    function redeemRewards(bytes calldata)
        external
        override
        onlyIdleCDO
        returns (uint256[] memory rewards)
    {
        address pool = cpToken;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        IPoolMaster(pool).factory().withdrawReward(pools);

        rewards = new uint256[](1);
        rewards[0] = IERC20Detailed(govToken).balanceOf(address(this));
        IERC20Detailed(govToken).safeTransfer(msg.sender, rewards[0]);
    }

    /// @notice unused in harvest strategy
    function pullStkAAVE() external pure override returns (uint256) {
        return 0;
    }

    /// @notice return the price from the strategy token contract
    /// @return price
    function price() public view virtual override returns (uint256) {
        return
            (IPoolMaster(cpToken).getCurrentExchangeRate() * oneToken) / 10**18;
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
        // CPOOL per second (clearpool's contract has typo)
        IPoolMaster _cpToken = IPoolMaster(cpToken);
        uint256 rewardSpeed = _cpToken.rewardPerSecond();
        // Underlying tokens equivalent of rewards
        uint256 annualRewards = (rewardSpeed *
            YEAR *
            _tokenToUnderlyingRate()) / 10**18;
        // Pool's TVL as underlying tokens
        uint256 poolTVL = (IERC20Detailed(address(_cpToken)).totalSupply() *
            _cpToken.getCurrentExchangeRate()) / 10**18;
        // Annual rewards rate (as clearpool's 18-precision decimal)
        uint256 rewardRate = (annualRewards * 10**18) / poolTVL;

        // Pool's annual interest rate
        uint256 poolRate = _cpToken.getSupplyRate() * YEAR;

        return (poolRate + rewardRate) * 100;
    }

    function _tokenToUnderlyingRate() internal virtual view returns (uint256) {
        address _token = token;
        if (_token == USDC) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = (govToken, _token);
            uint256[] memory amountsOut = uniswapRouter.getAmountsOut(10**18, path);
            return amountsOut[1];
        } else {
            address[] memory path = new address[](3);
            // in uniV2 the only pool is CPOOL/USDC
            (path[0], path[1], path[2]) = (govToken, USDC, _token);
            uint256[] memory amountsOut = uniswapRouter.getAmountsOut(10**18, path);
            return amountsOut[2];
        }
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of cpTokens to redeem
    /// @return Amount of underlying tokens received
    function redeem(uint256 _amount)
        external
        override
        onlyIdleCDO
        returns (uint256)
    {
        if (_amount > 0) {
            return _redeem(_amount);
        }
        return 0;
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of underlying tokens to redeem
    /// @return Amount of underlying tokens received
    function redeemUnderlying(uint256 _amount)
        external
        onlyIdleCDO
        returns (uint256)
    {
        if (_amount > 0) {
            uint256 _cpTokens = (_amount * oneToken) / price();
            return _redeem(_cpTokens);
        }
        return 0;
    }

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of cpTokens (underlying decimals)
    /// @return balanceReceived Amount of underlying tokens received
    function _redeem(uint256 _amount)
        virtual
        internal
        returns (uint256 balanceReceived)
    {
        // strategyToken (ie this contract) has 18 decimals
        _burn(msg.sender, (_amount * 1e18) / oneToken);
        IERC20Detailed _underlyingToken = underlyingToken;
        uint256 balanceBefore = _underlyingToken.balanceOf(address(this));
        IPoolMaster(cpToken).redeem(_amount);
        balanceReceived =
            _underlyingToken.balanceOf(address(this)) -
            balanceBefore;
        _underlyingToken.safeTransfer(msg.sender, balanceReceived);
    }

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount)
        external
        virtual
        override
        onlyIdleCDO
        returns (uint256 minted)
    {
        if (_amount > 0) {
            underlyingToken.safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            minted = _depositToVault(_amount);
        }
    }

    /// @notice internal function to deposit the funds to the vault
    /// @param _amount Amount of underlying tokens to deposit
    /// @return minted number of reward tokens minted
    function _depositToVault(uint256 _amount)
        virtual
        internal
        returns (uint256 minted)
    {
        address _cpToken = cpToken;
        underlyingToken.safeApprove(_cpToken, _amount);

        uint256 balanceBefore = IERC20Detailed(_cpToken).balanceOf(
            address(this)
        );
        IPoolMaster(_cpToken).provide(_amount);
        minted =
            IERC20Detailed(_cpToken).balanceOf(address(this)) -
            balanceBefore;
        minted = (minted * 10**18) / oneToken;
        _mint(msg.sender, minted);
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
