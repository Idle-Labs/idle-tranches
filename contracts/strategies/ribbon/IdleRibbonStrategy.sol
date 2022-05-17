// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";

import "../../interfaces/ribbon/IRibbonThetaSTETHVault.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "hardhat/console.sol";

/// @author LiveDuo.
/// @title IdleRibbonStrategy
/// @notice IIdleCDOStrategy to deploy funds in Idle Finance
/// @dev This contract should not have any funds at the end of each tx.
contract IdleRibbonStrategy is Initializable, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice underlying token address
    address public override token;

    /// @notice address of the strategy used
    address public override strategyToken;

    /// @notice decimals of the underlying asset
    uint256 public override tokenDecimals;

    /// @notice one underlying token
    uint256 public override oneToken;

    /// @notice underlying ERC20 token contract
    IERC20Detailed public underlyingToken;

    /* ------------Extra declarations ---------------- */
    /// @notice vault
    IRibbonThetaSTETHVault public vault;

    /// @notice address of the IdleCDO
    address public idleCDO;

    /// @notice amount last indexed for calculating APR
    uint256 public lastIndexAmount;

    /// @notice time when last deposit/redeem was made, used for calculating the APR
    uint256 public lastIndexedTime;

    /// @notice total tokens deposited
    uint256 public totalDeposited;

    /// @notice latest saved apr
    uint256 public lastApr;

    /// @notice one year, used to calculate the APR
    uint256 private constant YEAR = 365 days;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice Can be called only once
    /// @dev Initialize the upgradable contract
    /// @param _strategyToken address of the strategy token.
    /// @param _underlyingToken address of the token deposited.
    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _vault,
        address _owner
    ) public initializer {
        require(token == address(0), "Token is already initialized");

        // initialize owner
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        // underlying token
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        // initialize strategy token
        string memory params = string(abi.encodePacked("idleRB", underlyingToken.symbol()));
        ERC20Upgradeable.__ERC20_init("Idle Ribbon Strategy Token", params);
        
        // strategy token
        strategyToken = address(this);
        underlyingToken.approve(_strategyToken, type(uint256).max);

        // ribbon vault
        vault = IRibbonThetaSTETHVault(_vault);
        lastIndexedTime = block.timestamp;

    }
    
    /* -------- write functions ------------- */

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 minted) {
        minted = _deposit(_amount);
    }

    /// @notice Redeem Tokens
    /// @param _amount number of tokens to redeem
    /// @return minted number of reward tokens minted
    function redeem(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        vault.initiateWithdraw(_amount);
        return _amount;
    }

    /// @notice Complete redeem Tokens
    /// @return Amount of underlying tokens received
    function completeRedeem() external onlyIdleCDO returns (uint256) {
        uint256 _amount = vault.accountVaultBalance(address(this));
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

    /// @notice allow to update whitelisted address
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        idleCDO = _cdo;
    }

    /* -------- read functions ------------- */

    /// @notice Approximate APR
    /// @return apr
    function getApr() external view override returns (uint256 apr) {
        return lastApr;
    }

    /// @notice net price in underlyings of 1 strategyToken
    /// @return _price
    function price() public view override returns (uint256 _price) {
        return vault.pricePerShare();
    }

    /* -------- internal functions ------------- */

    /// @notice Internal function to deposit the underlying tokens to the vault
    /// @param _amount amount of tokens to deposit
    /// @return _minted number of reward tokens minted
    function _deposit(uint256 _amount) internal returns (uint256 _minted) {
        
        if (_amount > 0) {

            underlyingToken.transferFrom(msg.sender, address(this), _amount);
            IWETH(token).withdraw(_amount);

            _updateApr(int256(_amount));
            
            vault.depositETH{value: _amount}();

            uint256 _minted = _amount * oneToken / price();
            _mint(msg.sender, _minted);
            totalDeposited += _amount;
        }
        
    }

        /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of strategy tokens
    /// @return massetReceived Amount of underlying tokens received
    function _redeem(uint256 _amount, uint256 _price) internal returns (uint256 massetReceived) {

        uint256 redeemed = (_amount * _price) / oneToken;
        _updateApr(-int256(redeemed));

        totalDeposited -= redeemed;

        _burn(msg.sender, _amount);
        
        IWETH(token).deposit{value : _amount}();
        
        underlyingToken.transferFrom(address(this), msg.sender, _amount);
    }

    /// @notice update last saved apr
    /// @param _amount amount of underlying tokens to mint/redeem
    function _updateApr(int256 _amount) internal {
        uint256 amountDeposited = uint256(_amount >= 0 ? _amount : -_amount) * 110 / 100;
        uint256 _lastIndexAmount = lastIndexAmount;
        if (lastIndexAmount > 0) {
            uint256 diff = amountDeposited > _lastIndexAmount ? amountDeposited - _lastIndexAmount : _lastIndexAmount - amountDeposited;
            uint256 gainPerc = (diff * 10**20) / _lastIndexAmount;
            lastApr = (YEAR / (block.timestamp - lastIndexedTime)) * gainPerc;
        }
        lastIndexedTime = block.timestamp;
        lastIndexAmount = uint256(int256(amountDeposited) + _amount);
    }

    /// @notice fallback functions to allow receiving eth
    fallback() external payable {}

    /// @notice Modifier to make sure that caller os only the idleCDO contract
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }

    /* -------- unused functions ------------- */

    /// @notice unused in Ribbon Strategy
    function redeemRewards(bytes calldata _extraData) external override onlyIdleCDO returns (uint256[] memory rewards) {}

    /// @notice unused in Ribbon Strategy
    function pullStkAAVE() external pure override returns (uint256) {}

    /// @notice unused in Ribbon Strategy
    function getRewardTokens() external pure override returns (address[] memory _rewards) {}

}
