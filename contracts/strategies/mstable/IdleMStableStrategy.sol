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

/// @author IdleHusbandry.
/// @title IdleMStableStrategy
/// @notice IIdleCDOStrategy to deploy funds in Idle Finance
/// @dev This contract should not have any funds at the end of each tx.
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
    /// @notice address of the governance token. (Here META)
    address public govToken;

    /// @notice vault
    IVault public vault;

    /// @notice address of the IdleCDO
    address public idleCDO;

    /// @notice uniswap router path that should be used to swap the tokens
    address[] public uniswapRouterPath;

    /// @notice interface derived from uniswap router
    IUniswapV2Router02 public uniswapV2Router02;

    /// @notice amount last indexed for calculating APR
    uint256 public lastIndexAmount;

    /// @notice time when last deposit/redeem was made, used for calculating the APR
    uint256 public lastIndexedTime;

    /// @notice one year, used to calculate the APR
    uint256 public constant YEAR = 365 days;

    /// @notice round for which the last reward is claimed
    uint256 public rewardLastRound;

    constructor() {
        token = address(1);
    }

    /// @notice Can be called only once
    /// @dev Initialize the upgradable contract
    /// @param _strategyToken address of the strategy token. Here imUSD
    /// @param _underlyingToken address of the token deposited. here mUSD
    /// @param _vault address of the of the vault
    /// @param _idleCDO address of the idleCDO contract
    /// @param _uniswapV2Router02 address of the uniswap router
    /// @param _routerPath path to swap the gov tokens
    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _vault,
        address _idleCDO,
        address _uniswapV2Router02,
        address[] calldata _routerPath,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

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

        uniswapRouterPath = _routerPath;
        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);

        ERC20Upgradeable.__ERC20_init("Idle MStable Strategy Token", string(abi.encodePacked("idleMS", underlyingToken.symbol())));
        lastIndexedTime = block.timestamp;
        //------//-------//

        (, , rewardLastRound) = vault.unclaimedRewards(address(this));
        transferOwnership(_owner);
    }

    /// @notice redeem the rewards. Claims all possible rewards
    /// @return rewards amount of reward that is deposited to vault
    function redeemRewards() external onlyIdleCDO returns (uint256[] memory rewards) {
        _claimGovernanceTokens(0);
        rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(0); // will redeem whatever possible reward is available
    }

    /// @notice redeem the rewards. Claims reward as per the _extraData
    /// @param _extraData must contain the minimum liquidity to receive, start round and end round round for which the reward is being claimed
    /// @return rewards amount of reward that is deposited to vault
    function redeemRewards(bytes calldata _extraData) external override onlyIdleCDO returns (uint256[] memory rewards) {
        (uint256 minLiquidityTokenToReceive, uint256 endRound) = abi.decode(_extraData, (uint256, uint256));
        _claimGovernanceTokens(endRound);
        rewardLastRound = endRound;
        rewards = new uint256[](1);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(minLiquidityTokenToReceive);
    }

    /// @notice unused in MStable Strategy
    function pullStkAAVE() external pure override returns (uint256) {
        return 0;
    }

    /// @notice return the price from the imUSD contract
    /// @return price
    function price() public view override returns (uint256) {
        return imUSD.exchangeRate();
    }

    /// @notice Get the reward token
    /// @return array of reward token
    function getRewardTokens() external view override returns (address[] memory) {
        address[] memory govTokens;
        govTokens[0] = govToken;
        return govTokens;
    }

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 minted) {
        if (_amount > 0) {
            underlyingToken.transferFrom(msg.sender, address(this), _amount);
            minted = _depositToVault(_amount);
        }
    }

    /// @notice Internal function to deposit the underlying tokens to the vault
    /// @param _amount amount of tokens to deposit
    /// @return number of reward tokens minted
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

    /// @notice Redeem Tokens
    /// @param _amount amount of strategy tokens to redeem
    /// @return Amount of underlying tokens received
    function redeem(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        return _redeem(_amount);
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of underlying tokens to redeem
    /// @return Amount of underlying tokens received
    function redeemUnderlying(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        uint256 _underlyingAmount = (_amount * oneToken) / price();
        return _redeem(_underlyingAmount);
    }

    /// @notice Approximate APR
    /// @return APR
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

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of strategy tokens
    /// @return Amount of underlying tokens received
    function _redeem(uint256 _amount) internal returns (uint256) {
        lastIndexAmount = lastIndexAmount - _amount;
        lastIndexedTime = block.timestamp;

        _burn(msg.sender, _amount);
        vault.withdraw(_amount);

        uint256 massetReceived = imUSD.redeem(_amount);
        underlyingToken.transfer(msg.sender, massetReceived);

        return massetReceived;
    }

    /// @notice Function to swap the governance tokens on uniswapV2
    /// @param minLiquidityTokenToReceive minimun number of tokens to that need to be received
    /// @return Number of new strategy tokens generated
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

    /// @notice Claim governance tokens
    /// @param endRound End Round from which the Governance tokens must be claimed
    function claimGovernanceTokens(uint256 endRound) external onlyOwner {
        _claimGovernanceTokens(endRound);
    }

    /// @notice Claim governance tokens
    /// @param endRound End Round from which the Governance tokens must be claimed
    function _claimGovernanceTokens(uint256 endRound) internal {
        if (endRound == 0) {
            (, , endRound) = vault.unclaimedRewards(address(this));
        }
        require(rewardLastRound <= endRound, "End Round should be more than or equal to lastRewardRound");
        vault.claimRewards(rewardLastRound, endRound);
        rewardLastRound = endRound;
    }

    /// @notice Change idleCDO address
    /// @dev operation can be only done by the owner of the contract
    function changeIdleCDO(address _idleCDO) external onlyOwner {
        idleCDO = _idleCDO;
    }

    /// @notice Change the uniswap router path
    /// @param newPath New Path
    /// @dev operation can be only done by the owner of the contract
    function changeUniswapRouterPath(address[] memory newPath) public onlyOwner {
        uniswapRouterPath = newPath;
    }

    /// @notice Modifier to make sure that caller os only the idleCDO contract
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
