// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/harvest/IHarvestVault.sol";
import "../../interfaces/harvest/IRewardPool.sol";

import "../../interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "hardhat/console.sol";

contract IdleHarvestStrategy is Initializable, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    // ex: DAI
    address public override token;

    // ex: fDAI
    address public override strategyToken;

    uint256 public override tokenDecimals;

    uint256 public override oneToken;

    IERC20Detailed public underlyingToken;

    address public rewardPool;

    uint256 public lastIndexAmount;

    uint256 public lastIndexedTime;

    address public idleCDO;

    uint256 public constant YEAR = 365 days;

    address public govToken;

    address[] public uniswapRouterPath;

    IUniswapV2Router02 public uniswapV2Router02;

    constructor() {
        token = address(1);
    }

    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _rewardPool,
        address _uniswapV2Router02,
        address[] calldata _routerPath,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        strategyToken = _strategyToken;
        rewardPool = _rewardPool;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        govToken = IRewardPool(rewardPool).rewardToken();

        ERC20Upgradeable.__ERC20_init("Idle Harvest Strategy Token", string(abi.encodePacked("idleHS", underlyingToken.symbol())));
        //------//-------//

        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);
        uniswapRouterPath = _routerPath;

        transferOwnership(_owner);
        lastIndexedTime = block.timestamp;
    }

    function redeemRewards() external onlyIdleCDO returns (uint256[] memory rewards) {
        rewards = _redeemRewards(0);
    }

    function redeemRewards(bytes calldata _extraData) external override onlyIdleCDO returns (uint256[] memory rewards) {
        uint256 minLiquidityTokenToReceive = abi.decode(_extraData, (uint256));
        rewards = _redeemRewards(minLiquidityTokenToReceive);
    }

    function _redeemRewards(uint256 minLiquidityTokenToReceive) internal returns (uint256[] memory) {
        IRewardPool(rewardPool).getReward();
        uint256[] memory rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(minLiquidityTokenToReceive);
        return rewards;
    }

    function _swapGovTokenOnUniswapAndDepositToVault(uint256 minLiquidityTokenToReceive) internal returns (uint256) {
        uint256 govTokensToSend = IERC20Detailed(govToken).balanceOf(address(this));
        IERC20Detailed(govToken).approve(address(uniswapV2Router02), govTokensToSend);

        uint256 underlyingTokenBalanceBefore = underlyingToken.balanceOf(address(this));
        console.log("before::swapping on unswap::underlyingTokenBalanceBefore", underlyingTokenBalanceBefore);
        uniswapV2Router02.swapExactTokensForTokens(
            govTokensToSend,
            minLiquidityTokenToReceive,
            uniswapRouterPath,
            address(this),
            block.timestamp
        );
        uint256 underlyingTokenBalanceAfter = underlyingToken.balanceOf(address(this));
        console.log("before::swapping on unswap::underlyingTokenBalanceAfter", underlyingTokenBalanceAfter);

        console.log("amount received from uniswap", underlyingTokenBalanceAfter - underlyingTokenBalanceBefore);
        require(
            underlyingTokenBalanceAfter - underlyingTokenBalanceBefore >= minLiquidityTokenToReceive,
            "Should received more reward from uniswap than minLiquidityTokenToReceive"
        );
        uint256 uniswapAmountToVault = _depositToVault(underlyingTokenBalanceAfter);
        console.log("interest tokens received from uniswap", uniswapAmountToVault);
        return uniswapAmountToVault;
    }

    function pullStkAAVE() external pure override returns (uint256) {
        return 0;
    }

    function price() public view override returns (uint256) {
        return IHarvestVault(strategyToken).getPricePerFullShare();
    }

    function getRewardTokens() external view override returns (address[] memory) {
        address[] memory govTokens = new address[](1);
        govTokens[0] = govToken;
        return govTokens;
    }

    function getApr() external view returns (uint256) {
        uint256 rawBalance = IRewardPool(rewardPool).balanceOf(address(this));
        uint256 expectedUnderlyingAmount = (price() * rawBalance) / oneToken;

        if (expectedUnderlyingAmount <= lastIndexAmount) {
            return 0;
        }

        uint256 gain = expectedUnderlyingAmount - lastIndexAmount;
        console.log("gain", gain);
        uint256 time = block.timestamp - lastIndexedTime;
        console.log("time", time);
        uint256 gainPerc = (gain * 10**20) / lastIndexAmount;
        console.log("gainPerc", gainPerc);
        uint256 apr = (YEAR / time) * gainPerc;
        return apr;
    }

    function redeem(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        return _redeem(_amount);
    }

    function redeemUnderlying(uint256 _amount) external returns (uint256) {
        uint256 _underlyingAmount = (_amount * oneToken) / price();
        return _redeem(_underlyingAmount);
    }

    function _redeem(uint256 _amount) internal returns (uint256) {
        lastIndexAmount = lastIndexAmount - _amount;
        lastIndexedTime = block.timestamp;
        _burn(msg.sender, _amount);
        IRewardPool(rewardPool).withdraw(_amount);
        uint256 balanceBefore = underlyingToken.balanceOf(address(this));
        IHarvestVault(strategyToken).withdraw(_amount);
        uint256 balanceAfter = underlyingToken.balanceOf(address(this));
        uint256 balanceReceived = balanceAfter - balanceBefore;
        underlyingToken.transfer(msg.sender, balanceReceived);
        return balanceReceived;
    }

    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 minted) {
        if (_amount > 0) {
            console.log("amount being deposited", _amount);
            console.log("underlying token", address(underlyingToken));
            console.log("msg.sender", msg.sender);
            console.log("Check allowance", underlyingToken.allowance(msg.sender, address(this)));
            underlyingToken.transferFrom(msg.sender, address(this), _amount);
            console.log("Transfer complete");
            lastIndexAmount = lastIndexAmount + _amount;
            minted = _depositToVault(_amount);
        }
    }

    function _depositToVault(uint256 _amount) internal returns (uint256) {
        underlyingToken.approve(strategyToken, _amount);
        IHarvestVault(strategyToken).deposit(_amount);
        lastIndexedTime = block.timestamp;

        uint256 interestTokenAvailable = IERC20Detailed(strategyToken).balanceOf(address(this));
        IERC20Detailed(strategyToken).approve(rewardPool, interestTokenAvailable);

        IRewardPool(rewardPool).stake(interestTokenAvailable);

        _mint(msg.sender, interestTokenAvailable);
        return interestTokenAvailable;
    }

    function changeIdleCDO(address _idleCDO) external onlyOwner {
        idleCDO = _idleCDO;
    }

    /// @notice allow to update whitelisted address
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        idleCDO = _cdo;
    }

    function changeUniswapRouterPath(address[] memory newPath) public onlyOwner {
        uniswapRouterPath = newPath;
    }

    /// @notice Modifier to make sure that caller os only the idleCDO contract
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
