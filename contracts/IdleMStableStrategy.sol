// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IMAsset.sol";
import "./interfaces/ISavingsContractV2.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IUniswapV3Interface.sol";
import "./interfaces/IUniswapV3Pool.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

contract IdleMStableStrategy is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IIdleCDOStrategy,
    IUniswapV3SwapCallback
{
    using SafeERC20Upgradeable for IERC20Detailed;
    using SafeMath for uint256;

    /// @notice underlying token address (eg mUSD)
    address public override token;

    /// @notice address of the strategy used, in this case imUSD
    address public override strategyToken;

    /// @notice decimals of the underlying asset
    uint256 public override tokenDecimals;

    /// @notice one underlying token
    uint256 public override oneToken;

    /// @notice idleToken contract
    ISavingsContractV2 public imUSD;

    /// @notice underlying ERC20 token contract
    IERC20Detailed public underlyingToken;

    /* ------------Extra declarations ---------------- */
    address public govToken;
    IVault public vault;

    address public idleCDO;
    IUniswapV3Pool public uniswapPool;

    constructor() {
        token = address(1);
    }

    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _vault,
        address _idleCDO,
        address _uniswapV3Factory,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        //----- // -------//
        strategyToken = _strategyToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);
        imUSD = ISavingsContractV2(_strategyToken);
        vault = IVault(_vault);
        govToken = vault.getRewardToken();
        idleCDO = _idleCDO;

        address _uniswapPool = IUniswapV3Factory(_uniswapV3Factory).getPool(_underlyingToken, govToken, 3000); //only pool for 3000 is available
        require(_uniswapPool != address(0), "Cannot initialize if there is no uniswap pool available");
        uniswapPool = IUniswapV3Pool(_uniswapPool);

        ERC20Upgradeable.__ERC20_init("Idle MStable Strategy Token", string(abi.encodePacked("idleMS", underlyingToken.symbol())));

        //------//-------//

        transferOwnership(_owner);
    }

    // only claim gov token rewards
    function redeemRewards() external onlyIdleCDO returns (uint256[] memory rewards) {
        _claimGovernanceTokens(0, 0);
        rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(4295128740); // will redeem whatever possible reward is available
    }

    function redeemRewards(bytes calldata _extraData) external override onlyIdleCDO returns (uint256[] memory rewards) {
        (uint256 minLiquidityTokenToReceive, uint256 startRound, uint256 endRound, uint160 minTickMath) = abi.decode(
            _extraData,
            (uint256, uint256, uint256, uint160)
        );
        _claimGovernanceTokens(startRound, endRound);
        rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(minTickMath);
        require(rewards[0] >= minLiquidityTokenToReceive, "Should received more reward from uniswap than minLiquidityTokenToReceive");
    }

    function pullStkAAVE() external override returns (uint256) {
        return 0;
    }

    function price() public view override returns (uint256) {
        return imUSD.exchangeRate();
    }

    function getRewardTokens() external view override returns (address[] memory) {
        address[] memory govTokens;
        govTokens[0] = govToken;
        return govTokens;
    }

    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 minted) {
        require(_amount != 0, "Deposit amount should be greater than 0");
        underlyingToken.transferFrom(msg.sender, address(this), _amount);
        return _depositToVault(_amount);
    }

    function _depositToVault(uint256 _amount) internal returns (uint256) {
        underlyingToken.approve(address(imUSD), _amount);
        uint256 interestTokensReceived = imUSD.depositSavings(_amount);

        uint256 interestTokenAvailable = imUSD.balanceOf(address(this));
        imUSD.approve(address(vault), interestTokenAvailable);

        vault.stake(interestTokenAvailable);

        _mint(msg.sender, interestTokenAvailable);
        return interestTokenAvailable;
    }

    // _amount is strategy token
    function redeem(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        return _redeem(_amount);
    }

    // _amount in underlying token
    function redeemUnderlying(uint256 _amount) external override returns (uint256) {
        uint256 _underlyingAmount = _amount.mul(oneToken).div(price());
        return _redeem(_underlyingAmount);
    }

    function getApr() external view override returns (uint256) {
        return oneToken;
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(uniswapPool), "Only uniswap pool can call");
        if (amount0Delta > 0) {
            IERC20Detailed(govToken).transfer(address(uniswapPool), uint256(amount0Delta));
            return;
        }

        if (amount1Delta > 0) {
            IERC20Detailed(address(underlyingToken)).transfer(address(uniswapPool), uint256(amount1Delta));
            return;
        }
    }

    /* -------- internal functions ------------- */

    // here _amount means credits, will redeem any governance token if there
    function _redeem(uint256 _amount) internal returns (uint256) {
        require(_amount != 0, "Amount shuld be greater than 0");
        _burn(msg.sender, _amount);
        vault.withdraw(_amount);

        uint256 massetReceived = imUSD.redeem(_amount);
        underlyingToken.transfer(msg.sender, massetReceived);

        return massetReceived;
    }

    // min tick math = 4295128739;
    // max tick math = 1461446703485210103287273052203988822378723970342;
    // decides slippage
    function _swapGovTokenOnUniswapAndDepositToVault(uint160 minTickMath) internal returns (uint256) {
        uint256 govTokensToSend = IERC20Detailed(govToken).balanceOf(address(this));
        IERC20Detailed(govToken).approve(address(uniswapPool), govTokensToSend);

        bytes memory data;

        uniswapPool.swap(address(this), true, int256(govTokensToSend), minTickMath, data);
        // uniswapPool.swap(address(this), false, int256(govTokensToSend), 1461446703485210103287273052203988822378723970341, data);

        uint256 underlyingBalanceAfter = underlyingToken.balanceOf(address(this));
        uint256 newCredits = _depositToVault(underlyingBalanceAfter);
        _mint(msg.sender, newCredits);
        return newCredits;
    }

    function claimGovernanceTokens(uint256 startRound, uint256 endRound) public onlyOwner {
        _claimGovernanceTokens(startRound, endRound);
    }

    // pass (0,0) as paramsif you want to claim for all epochs
    function _claimGovernanceTokens(uint256 startRound, uint256 endRound) internal {
        require(startRound >= endRound, "Start Round Cannot be more the end round");

        if (startRound == 0 && endRound == 0) {
            vault.claimRewards(); // this be a infy gas call,
        } else {
            vault.claimRewards(startRound, endRound);
        }
    }

    function changeIdleCDO(address _idleCDO) external onlyOwner {
        idleCDO = _idleCDO;
    }

    function changeUniswapPool(
        address uniswapV3Factory,
        address token1,
        address token2,
        uint24 rewardRate
    ) external onlyOwner {
        address _uniswapPool = IUniswapV3Factory(uniswapV3Factory).getPool(token1, token2, rewardRate);
        require(_uniswapPool != address(0), "Should a pool that is already created");
        uniswapPool = IUniswapV3Pool(_uniswapPool);
    }

    // modifiers
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
