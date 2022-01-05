// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IMAsset.sol";
import "../../interfaces/ISavingsContractV2.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/IVault.sol";

import "../../interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IdleMStableStrategy is Initializable, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

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
    address[] public uniswapRouterPath;
    IUniswapV2Router02 public uniswapV2Router02;

    uint256 public lastIndexAmount;
    uint256 public lastIndexedTime;

    uint256 constant YEAR = 365 days;

    constructor() {
        token = address(1);
    }

    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _vault,
        address _idleCDO,
        address _uniswapV2Router02,
        address[] calldata routerPath,
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

        uniswapRouterPath = routerPath;
        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);

        ERC20Upgradeable.__ERC20_init("Idle MStable Strategy Token", string(abi.encodePacked("idleMS", underlyingToken.symbol())));
        lastIndexedTime = block.timestamp;
        //------//-------//

        transferOwnership(_owner);
    }

    // only claim gov token rewards
    function redeemRewards() external onlyIdleCDO returns (uint256[] memory rewards) {
        _claimGovernanceTokens(0, 0);
        rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(0); // will redeem whatever possible reward is available
    }

    function redeemRewards(bytes calldata _extraData) external override onlyIdleCDO returns (uint256[] memory rewards) {
        (uint256 minLiquidityTokenToReceive, uint256 startRound, uint256 endRound) = abi.decode(_extraData, (uint256, uint256, uint256));
        _claimGovernanceTokens(startRound, endRound);
        rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(minLiquidityTokenToReceive);
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
        if (_amount > 0) {
            underlyingToken.transferFrom(msg.sender, address(this), _amount);
            return _depositToVault(_amount);
        }
    }

    function _depositToVault(uint256 _amount) internal returns (uint256) {
        underlyingToken.approve(address(imUSD), _amount);
        lastIndexAmount = lastIndexAmount + _amount;
        lastIndexedTime = block.timestamp;
        imUSD.depositSavings(_amount);

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
        uint256 _underlyingAmount = (_amount * oneToken) / price();
        return _redeem(_underlyingAmount);
    }

    function getApr() external view override returns (uint256) {
        uint256 rawBalance = vault.rawBalanceOf(address(this));
        uint256 expectedUnderlyingAmount = imUSD.creditsToUnderlying(rawBalance);

        uint256 gain = expectedUnderlyingAmount - lastIndexAmount;
        if (gain == 0) {
            return 0;
        }
        uint256 time = block.timestamp - lastIndexedTime;
        uint256 gainPerc = (gain * 10**20) / lastIndexAmount;
        uint256 apr = (YEAR / time) * gainPerc;
        return apr;
    }

    /* -------- internal functions ------------- */

    // here _amount means credits, will redeem any governance token if there
    function _redeem(uint256 _amount) internal returns (uint256) {
        require(_amount != 0, "Amount shuld be greater than 0");

        lastIndexAmount = lastIndexAmount - _amount;
        lastIndexedTime = block.timestamp;

        _burn(msg.sender, _amount);
        vault.withdraw(_amount);

        uint256 massetReceived = imUSD.redeem(_amount);
        underlyingToken.transfer(msg.sender, massetReceived);

        return massetReceived;
    }

    function _swapGovTokenOnUniswapAndDepositToVault(uint256 minLiquidityTokenToReceive) internal returns (uint256) {
        uint256 govTokensToSend = IERC20Detailed(govToken).balanceOf(address(this));

        IERC20Detailed(govToken).approve(address(uniswapV2Router02), govTokensToSend);

        uint256 underlyingTokenBalanceBefore = underlyingToken.balanceOf(address(this));
        uniswapV2Router02.swapExactTokensForTokens(
            govTokensToSend,
            minLiquidityTokenToReceive,
            uniswapRouterPath,
            address(this),
            block.timestamp
        );
        uint256 underlyingTokenBalanceAfter = underlyingToken.balanceOf(address(this));

        require(
            underlyingTokenBalanceAfter - underlyingTokenBalanceBefore >= minLiquidityTokenToReceive,
            "Should received more reward from uniswap than minLiquidityTokenToReceive"
        );

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

    function changeUniswapRouterPath(address[] memory newPath) public onlyOwner {
        uniswapRouterPath = newPath;
    }

    // modifiers
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
