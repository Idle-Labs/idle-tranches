// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

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

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

contract IdleMStableStrategy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy, IUniswapV3SwapCallback {
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

    uint256 public totalCredits;

    address public idleCDO;
    IUniswapV3Pool public uniswapPool;

    uint256 public thresholdGovTokenToSwap;

    constructor() {
        token = address(1);
    }

    event Deposit(address indexed user, uint256 amount, uint256 sharesRecevied);
    event Redeem(address indexed user, uint256 credits, uint256 received);

    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _govToken,
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
        govToken = _govToken;
        vault = IVault(_vault);
        idleCDO = _idleCDO;

        address _uniswapPool = IUniswapV3Factory(_uniswapV3Factory).getPool(_underlyingToken, _govToken, 3000); //only pool for 3000 is available
        require(_uniswapPool != address(0), "Cannot initialize if there is no uniswap pool available");
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        thresholdGovTokenToSwap = 0; // check latter
        //------//-------//

        transferOwnership(_owner);
    }

    // only claim gov token rewards
    function redeemRewards() external override onlyIdleCDO returns (uint256[] memory rewards) {
        rewards[0] = _swapGovTokenOnUniswap();
    }

    function pullStkAAVE() external override returns (uint256) {
        return 0;
    }

    function price() public view override returns (uint256) {
        return imUSD.exchangeRate();
    }

    function getRewardTokens() external view override returns (address[] memory) {
        address[] memory govTokens;
        govTokens[0] = vault.getRewardToken();
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

        uint256 rawBalanceBefore = vault.rawBalanceOf(address(this));
        vault.stake(interestTokenAvailable);
        uint256 rawBalanceAfter = vault.rawBalanceOf(address(this));
        uint256 rawBalanceIncreased = rawBalanceAfter.sub(rawBalanceBefore);

        totalCredits = vault.rawBalanceOf(address(this));

        emit Deposit(msg.sender, _amount, rawBalanceIncreased);
        return interestTokensReceived;
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
        uint256 availableCredits = totalCredits;
        require(availableCredits >= _amount, "Cannot redeem more than available");

        _claimGovernanceTokens(0, 0);

        totalCredits = totalCredits.sub(_amount);
        vault.withdraw(_amount);

        uint256 massetReceived = imUSD.redeem(_amount);
        underlyingToken.transfer(msg.sender, massetReceived);
        _swapGovTokenOnUniswap();
        emit Redeem(msg.sender, _amount, massetReceived);
        return massetReceived;
    }

    function _swapGovTokenOnUniswap() internal returns (uint256) {
        uint256 govTokensToSend = IERC20Detailed(govToken).balanceOf(address(this));
        IERC20Detailed(govToken).approve(address(uniswapPool), govTokensToSend);
        if (govTokensToSend < thresholdGovTokenToSwap) {
            return 0;
        }

        bytes memory data;
        // min tick math = 4295128739;
        // max tick math = 1461446703485210103287273052203988822378723970342;

        uniswapPool.swap(address(this), true, int256(govTokensToSend), 4295128740, data);
        // uniswapPool.swap(address(this), false, int256(govTokensToSend), 1461446703485210103287273052203988822378723970341, data);

        uint256 underlyingBalanceAfter = underlyingToken.balanceOf(address(this));
        uint256 newCredits = _depositToVault(underlyingBalanceAfter);
        totalCredits = totalCredits.add(newCredits);
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

    // modifiers
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}