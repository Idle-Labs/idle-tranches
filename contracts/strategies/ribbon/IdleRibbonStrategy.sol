// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";

import "../../interfaces/ribbon/IRibbonVault.sol";

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
    IRibbonVault public vault;

    /// @notice address of the IdleCDO
    address public idleCDO;

    /// @notice 100000 => 100%
    uint32 constant MAX_APR_PERC = 100000;

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

        // ribbon vault
        vault = IRibbonVault(_vault);
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
        return _redeem(_amount);
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of underlying tokens to redeem
    /// @return Amount of underlying tokens received
    function redeemUnderlying(uint256 _amount) external override onlyIdleCDO returns (uint256) {
        uint256 _price = price();
        uint256 _strategyTokens = (_amount * oneToken) / _price;
        return _redeem(_strategyTokens);
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
        uint16 round = vault.vaultState().round;
        if (round < 2) {
            return 0;
        }

        uint256 previousWeekStartAmount = vault.roundPricePerShare(round - 2);
        uint256 previousWeekEndAmount = vault.roundPricePerShare(round - 1);
        uint256 weekApr = (previousWeekEndAmount * MAX_APR_PERC / previousWeekStartAmount) - MAX_APR_PERC;
        return weekApr * 52;
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

            if(address(underlyingToken) == vault.WETH()) {
                IWETH(token).withdraw(_amount);
                vault.depositETH{value: _amount}();
            } else {
                underlyingToken.approve(address(vault), _amount);

                try vault.STETH() returns (address v) {
                    vault.depositYieldToken(_amount);
                } catch (bytes memory) {
                    vault.deposit(_amount);
                }

            }

            uint256 _minted = _amount * oneToken;
            _mint(msg.sender, _minted);
        }
        
    }

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of strategy tokens
    /// @return massetReceived Amount of underlying tokens received
    function _redeem(uint256 _amount) internal returns (uint256 massetReceived) {

        _burn(msg.sender, _amount);

        vault.completeWithdraw();

        uint256 currentBalance; 

        if(address(underlyingToken) == vault.WETH()) {
            currentBalance = address(this).balance;
            IWETH(address(underlyingToken)).deposit{value : currentBalance}();
        } else {
            currentBalance = underlyingToken.balanceOf(address(this));
            underlyingToken.approve(address(this), currentBalance);
            underlyingToken.approve(msg.sender, currentBalance);
        }

        underlyingToken.transferFrom(address(this), msg.sender, currentBalance);
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
