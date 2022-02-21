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

    /// @notice total imUSD tokens staked
    uint256 public totalLpTokensStaked;
    /// @notice total imUSD tokens locked
    uint256 public totalLpTokensLocked;
    /// @notice harvested imUSD tokens release delay
    uint256 public releaseBlocksPeriod;
    /// @notice latest harvest
    uint256 public latestHarvestBlock;
    /// @notice latest saved apr
    uint256 public lastApr;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice Can be called only once
    /// @dev Initialize the upgradable contract
    /// @param _strategyToken address of the strategy token. Here imUSD
    /// @param _underlyingToken address of the token deposited. here mUSD
    /// @param _vault address of the of the vault
    /// @param _uniswapV2Router02 address of the uniswap router
    /// @param _routerPath path to swap the gov tokens
    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _vault,
        address _uniswapV2Router02,
        address[] calldata _routerPath,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        // this contract tokenizes the staked imUSD position
        strategyToken = address(this); 
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(_underlyingToken);
        tokenDecimals = IERC20Detailed(_underlyingToken).decimals();
        oneToken = 10**(tokenDecimals);
        imUSD = ISavingsContractV2(_strategyToken);
        vault = IVault(_vault);
        govToken = vault.getRewardToken();

        uniswapRouterPath = _routerPath;
        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);
        releaseBlocksPeriod = 6400; // ~24 hours

        ERC20Upgradeable.__ERC20_init("Idle MStable Strategy Token", string(abi.encodePacked("idleMS", underlyingToken.symbol())));
        lastIndexedTime = block.timestamp;
        //------//-------//

        transferOwnership(_owner);
        IERC20Detailed(_underlyingToken).approve(_strategyToken, type(uint256).max);
        ISavingsContractV2(_strategyToken).approve(_vault, type(uint256).max);
    }

    /// @notice redeem the rewards. Claims all possible rewards
    /// @return rewards amount of underlyings (mUSD) received after selling rewards and endRound
    function redeemRewards() external onlyOwner returns (uint256[] memory rewards) {
        rewards = new uint256[](2);
        rewards[1] = _claimGovernanceTokens(0);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(0); // will redeem whatever possible reward is available
    }

    /// @notice redeem the rewards. Claims reward as per the _extraData
    /// @param _extraData must contain the minimum liquidity to receive, start round and end round round for which the reward is being claimed
    /// @return rewards amount of underlyings (mUSD) received after selling rewards and endRound
    function redeemRewards(bytes calldata _extraData) external override onlyIdleCDO returns (uint256[] memory rewards) {
        (uint256 minLiquidityTokenToReceive, uint256 endRound) = abi.decode(_extraData, (uint256, uint256));
        rewards = new uint256[](2);
        rewards[1] = _claimGovernanceTokens(endRound);
        rewards[0] = _swapGovTokenOnUniswapAndDepositToVault(minLiquidityTokenToReceive);
    }

    /// @notice unused in MStable Strategy
    function pullStkAAVE() external pure override returns (uint256) {
        return 0;
    }

    /// @notice net price in underlyings of 1 strategyToken
    /// @return _price
    function price() public view override returns (uint256 _price) {
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            _price = oneToken;
        } else {
            _price =
                (totalLpTokensStaked - _lockedLpTokens()) * oneToken / _totalSupply;
        }
    }

    /// @notice Get the reward token
    /// @return _rewards array of reward token (empty as rewards are handled in this strategy)
    function getRewardTokens() external pure override returns (address[] memory _rewards) {
        return _rewards;
    }

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 minted) {
        if (_amount > 0) {
            underlyingToken.transferFrom(msg.sender, address(this), _amount);
            minted = _depositToVault(_amount, true);
        }
    }

    /// @notice Internal function to deposit the underlying tokens to the vault
    /// @param _amount amount of tokens to deposit
    /// @param _shouldMint amount of tokens to deposit
    /// @return _minted number of reward tokens minted
    function _depositToVault(uint256 _amount, bool _shouldMint) internal returns (uint256 _minted) {
        _updateApr(int256(_amount));
        ISavingsContractV2 _imUSD = imUSD;
        // mint imUSD with mUSD
        _imUSD.depositSavings(_amount);
        // stake imUSD in Meta vault
        uint256 _imUSDBal = _imUSD.balanceOf(address(this));
        vault.stake(_imUSDBal);
        if (_shouldMint) {
            _minted = _amount * oneToken / price();
            _mint(msg.sender, _minted);
        }
        totalLpTokensStaked += _amount;
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of strategy tokens to redeem
    /// @return Amount of underlying tokens received
    function redeem(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        return _redeem(_amount, price());
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of underlying tokens to redeem
    /// @return Amount of underlying tokens received
    function redeemUnderlying(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        uint256 _price = price();
        uint256 _strategyTokens = (_amount * oneToken) / _price;
        return _redeem(_strategyTokens, _price);
    }

    /// @notice Approximate APR
    /// @return apr
    function getApr() external view override returns (uint256 apr) {
        return lastApr;
    }

    /* -------- internal functions ------------- */

    /// @notice update last saved apr
    /// @param _amount amount of underlying tokens to mint/redeem
    function _updateApr(int256 _amount) internal {
        uint256 mUSDStaked = imUSD.creditsToUnderlying(vault.rawBalanceOf(address(this)));
        uint256 _lastIndexAmount = lastIndexAmount;
        if (lastIndexAmount > 0) {
            uint256 gainPerc = ((mUSDStaked - _lastIndexAmount) * 10**20) / _lastIndexAmount;
            lastApr = (YEAR / (block.timestamp - lastIndexedTime)) * gainPerc;
        }
        lastIndexedTime = block.timestamp;
        lastIndexAmount = uint256(int256(mUSDStaked) + _amount);
    }

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of strategy tokens
    /// @return massetReceived Amount of underlying tokens received
    function _redeem(uint256 _amount, uint256 _price) internal returns (uint256 massetReceived) {
        uint256 redeemed = (_amount * _price) / oneToken;
        _updateApr(-int256(redeemed));

        ISavingsContractV2 _imUSD = imUSD;
        // mUSD we want back
        uint256 imUSDToRedeem = _imUSD.underlyingToCredits(redeemed);
        totalLpTokensStaked -= redeemed;

        _burn(msg.sender, _amount);
        vault.withdraw(imUSDToRedeem);
        massetReceived = _imUSD.redeemCredits(imUSDToRedeem);
        underlyingToken.transfer(msg.sender, massetReceived);
    }

    /// @notice Function to swap the governance tokens on uniswapV2
    /// @param minLiquidityTokenToReceive minimun number of tokens to that need to be received
    /// @return _bal amount of underlyings (mUSD) received
    function _swapGovTokenOnUniswapAndDepositToVault(uint256 minLiquidityTokenToReceive) internal returns (uint256 _bal) {
        IERC20Detailed _govToken = IERC20Detailed(govToken);
        uint256 govTokensToSend = _govToken.balanceOf(address(this));
        IUniswapV2Router02 _uniswapV2Router02 = uniswapV2Router02;

        _govToken.approve(address(_uniswapV2Router02), govTokensToSend);
        _uniswapV2Router02.swapExactTokensForTokens(
            govTokensToSend,
            minLiquidityTokenToReceive,
            uniswapRouterPath,
            address(this),
            block.timestamp
        );

        _bal = underlyingToken.balanceOf(address(this));
        _depositToVault(_bal, false);
        // save the block in which rewards are swapped and the amount
        latestHarvestBlock = block.number;
        totalLpTokensLocked = _bal;
    }

    /// @notice Claim governance tokens
    /// @param endRound End Round from which the Governance tokens must be claimed
    function claimGovernanceTokens(uint256 endRound) external onlyOwner {
        _claimGovernanceTokens(endRound);
    }

    /// @notice Claim governance tokens
    /// @param endRound End Round from which the Governance tokens must be claimed
    function _claimGovernanceTokens(uint256 endRound) internal returns (uint256) {
        if (endRound == 0) {
            (, , endRound) = vault.unclaimedRewards(address(this));
        }
        vault.claimRewards(rewardLastRound, endRound);
        rewardLastRound = endRound;
        return endRound;
    }

    /// @notice Change the uniswap router path
    /// @param newPath New Path
    /// @dev operation can be only done by the owner of the contract
    function changeUniswapRouterPath(address[] memory newPath) public onlyOwner {
        uniswapRouterPath = newPath;
    }

    /// @notice allow to update whitelisted address
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        idleCDO = _cdo;
    }

    /// @notice allow to update whitelisted address
    function setReleaseBlocksPeriod(uint256 _period) external onlyOwner {
        releaseBlocksPeriod = _period;
    }

    /// @notice 
    function _lockedLpTokens() internal view returns (uint256 _locked) {
        uint256 _releaseBlocksPeriod = releaseBlocksPeriod;
        uint256 _blocksSinceLastHarvest = block.number - latestHarvestBlock;
        uint256 _totalLockedLpTokens = totalLpTokensLocked;

        if (_totalLockedLpTokens > 0 && _blocksSinceLastHarvest < _releaseBlocksPeriod) {
            // progressively release harvested rewards
            _locked = _totalLockedLpTokens * (_releaseBlocksPeriod - _blocksSinceLastHarvest) / _releaseBlocksPeriod;
        }
    }

    /// @notice Modifier to make sure that caller os only the idleCDO contract
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
