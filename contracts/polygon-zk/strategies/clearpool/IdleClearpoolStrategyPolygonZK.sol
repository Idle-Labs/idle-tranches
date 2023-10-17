// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../../interfaces/IIdleCDOStrategy.sol";
import "../../../interfaces/IERC20Detailed.sol";
import "../../../interfaces/clearpool/IPoolFactory.sol";
import "../../../interfaces/clearpool/IPoolMaster.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
// One line change is needed for solidity 0.8.X to make it compile check here 
// https://ethereum.stackexchange.com/questions/96642/unary-operator-minus-cannot-be-applied-to-type-uint256
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

contract IdleClearpoolStrategyPolygonZK is
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
    
    address private constant WETH = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;
    address private constant USDC = 0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
    address private constant CPOOL = 0xc3630b805F10E91c2de084Ac26C66bCD91F3D3fE;
    address internal constant QUICK_V3_FACTORY = 0x4B9f4d2435Ef65559567e5DbFC1BbB37abC43B57;
    uint256 internal constant EXP_SCALE = 1e18;
    address private constant MATIC = 0xa2036f0538221a77A3937F1379699f44945018d0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice can be only called once
    /// @param _cpToken address of the strategy token (lending pool)
    /// @param _underlyingToken address of the underlying token (pool currency)
    /// @param _owner address of the owner of the strategy
    function initialize(
        address _cpToken,
        address _underlyingToken,
        address _owner
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

        // govToken = IPoolMaster(_cpToken).factory().cpool();

        ERC20Upgradeable.__ERC20_init(
            "Idle Clearpool Strategy Token",
            string(abi.encodePacked("idle_", IERC20Detailed(_cpToken).symbol()))
        );
        //------//-------//

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
        // address pool = cpToken;
        // address[] memory pools = new address[](1);
        // pools[0] = pool;
        // IPoolMaster(pool).factory().withdrawReward(pools);

        // rewards = new uint256[](2); // 2 rewards CPOOL and MATIC (manually sent to CDO)
        // rewards[0] = IERC20Detailed(CPOOL).balanceOf(address(this));
        // if (rewards[0] != 0) {
        //     IERC20Detailed(CPOOL).safeTransfer(msg.sender, rewards[0]);
        // }
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
        govTokens[0] = MATIC;
        return govTokens;
    }

    function getApr() external view returns (uint256) {
        // CPOOL per second (clearpool's contract has typo)
        IPoolMaster _cpToken = IPoolMaster(cpToken);
        uint256 rewardSpeed = _cpToken.rewardPerSecond();
        uint256 rewardRate;
        if (rewardSpeed > 0) {
            // Underlying tokens equivalent of rewards
            uint256 annualRewards = (rewardSpeed *
                YEAR *
                _tokenToUnderlyingRate()) / 10**18;
            // Pool's TVL as underlying tokens
            uint256 poolTVL = (IERC20Detailed(address(_cpToken)).totalSupply() *
                _cpToken.getCurrentExchangeRate()) / 10**18;
            // Annual rewards rate (as clearpool's 18-precision decimal)
            rewardRate = (annualRewards * 10**18) / poolTVL;
        }

        // Pool's annual interest rate
        uint256 poolRate = _cpToken.getSupplyRate() * YEAR;

        return (poolRate + rewardRate) * 100;
    }

    function _tokenToUnderlyingRate() internal virtual view returns (uint256 _price) {
        address _token = token;
        _price = _getPriceUniV3(address(CPOOL), WETH, uint24(10000));
        if (address(_token) != WETH) {
            // 0.05% fee pool. This returns a price with tokenDecimals
            uint256 wethToUnderlying = _getPriceUniV3(WETH, address(_token), uint24(500));
            _price = _price * wethToUnderlying / EXP_SCALE; // in underlyings
        }
    }

    /// @notice this price is not safe from flash loan attacks, but it is used only for showing the apr on the UI
    function _getPriceUniV3(address tokenIn, address tokenOut, uint24 _fee)
        internal
        view
        returns (uint256 _price)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(QUICK_V3_FACTORY).getPool(tokenIn, tokenOut, _fee));
        (uint160 sqrtPriceX96,,,,,,) =  pool.slot0();
        uint256 _scaledPrice = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        if (tokenOut == pool.token0()) {
            // token1Price -> ratio of token0 over token1
            _price = FullMath.mulDiv(2**192, EXP_SCALE, _scaledPrice);
        } else {
            // token0Price -> ratio of token1 over token0 
            _price = FullMath.mulDiv(EXP_SCALE, _scaledPrice, 2**192);
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
