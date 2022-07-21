// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/euler/IEToken.sol";
import "../../interfaces/euler/IDToken.sol";
import "../../interfaces/euler/IMarkets.sol";
import "../../interfaces/euler/IEulerGeneralView.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @author Euler Finance
/// @title IdleEulerStrategy
/// @notice IIdleCDOStrategy to deploy funds in Idle Finance
/// @dev This contract should not have any funds at the end of each tx.
/// The contract is upgradable, to add storage slots, add them after the last `###### End of storage VXX`
contract IdleEulerStrategy is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IIdleCDOStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;

    /// ###### Storage V1
    /// @notice address of the strategy used, in this case ETokens, e.g., eDAI
    address public override strategyToken;
    /// @notice underlying token address (e.g., DAI)
    address public override token;
    /// @notice one underlying token
    uint256 public override oneToken;
    /// @notice decimals of the underlying asset
    uint256 public override tokenDecimals;
    /// @notice underlying ERC20 token contract
    IERC20Detailed public underlyingToken;
    /// @notice EToken contract
    IEToken public eToken;

    /// @notice Euler markets contract address
    address internal constant EULER_MARKETS =
        address(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    /// @notice Euler general view contract address
    address internal constant EULER_GENERAL_VIEW =
        address(0xACC25c4d40651676FEEd43a3467F3169e3E68e42);
    address internal constant idleGovTimelock =
        address(0xD6dABBc2b275114a2366555d6C481EF08FDC2556);
    address public whitelistedCDO;

    /// ###### End of storage V1

    // Used to prevent initialization of the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    // ###################
    // Initializer
    // ###################

    /// @notice can only be called once
    /// @dev Initialize the upgradable contract
    /// @param _strategyToken address of the strategy token
    /// @param _underlyingToken address of the underlying token
    /// @param _owner owner address
    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _euler,
        address _owner
    ) public initializer {
        require(token == address(0), "Initialized");
        // Initialize contracts
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        // Set basic parameters
        strategyToken = _strategyToken;
        // EToken does not have function to get address of underlying token.
        // This is being rolled out
        token = _underlyingToken;
        tokenDecimals = IERC20Detailed(token).decimals();
        oneToken = 10**(tokenDecimals);
        eToken = IEToken(_strategyToken);
        underlyingToken = IERC20Detailed(token);
        // approve Euler protocol uint256 max for deposits
        underlyingToken.safeApprove(_euler, type(uint256).max);
        // transfer ownership of this smart contract to _owner
        transferOwnership(_owner);
    }

    // ###################
    // Public methods
    // ###################

    /// @dev msg.sender should approve this contract first to spend `_amount` of underlying `token`, e.g., DAI
    /// msg.sender will receive strategyTokens minted, i.e., ETokens
    /// @param _amount amount of underlying `token` to deposit
    /// @return minted strategyTokens minted, i.e., ETokens
    function deposit(uint256 _amount)
        external
        override
        returns (uint256 minted)
    {
        if (_amount > 0) {
            /// get `tokens` from msg.sender
            underlyingToken.safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            /// deposit those in Euler
            uint256 eTokenBalanceBefore = eToken.balanceOf(address(this));
            eToken.deposit(0, _amount);
            uint256 eTokenBalanceAfter = eToken.balanceOf(address(this));
            minted = eTokenBalanceAfter - eTokenBalanceBefore;
            /// transfer eTokens to msg.sender
            eToken.transfer(msg.sender, minted);
        }
    }

    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken` balanceOf
    /// strategyToken, i.e., eToken that will be taken from msg.sender in exchange for underlying token
    /// IEToken withdraw function uses underlying amount/units, and max uint256 for full pool balance
    /// @param _amount amount of strategyTokens to redeem
    /// @return redeemed of underlyings redeemed
    function redeem(uint256 _amount)
        external
        override
        returns (uint256 redeemed)
    {
        if (_amount > 0) {
            // get eTokens from the user
            eToken.transferFrom(msg.sender, address(this), _amount);
            redeemed = _redeem(eToken.convertBalanceToUnderlying(_amount));
        }
    }

    /// @notice Anyone can call this because this contract holds no stETH and so no 'old' rewards
    /// NOTE: stkAAVE rewards are not sent back to the user but accumulated in this contract until 'pullStkAAVE' is called
    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`.
    /// redeem rewards and transfer them to msg.sender
    function redeemRewards(bytes calldata)
        external
        override
        returns (uint256[] memory _balances)
    {}

    /// @dev IEToken withdraw function uses underlying amount/units, and max uint256 for full pool balance
    /// msg.sender should approve this contract first to spend eToken.convertUnderlyingToBalance(`underlying amount`)
    /// @param _amount amount of underlying tokens to redeem, in underlying units
    /// @return redeemed of underlyings redeemed
    function redeemUnderlying(uint256 _amount)
        external
        override
        returns (uint256 redeemed)
    {
        if (_amount > 0) {
            // get eTokens from the user
            eToken.transferFrom(
                msg.sender,
                address(this),
                eToken.convertUnderlyingToBalance(_amount)
            );

            // after converting underlying amount to eToken to collect from user
            // the underlying amount could exceed eToken balance upon calling withdraw
            // and revert with 'e/insufficient-balance'
            if (eToken.balanceOfUnderlying(address(this)) < _amount) {
                redeemed = _redeem(eToken.balanceOfUnderlying(address(this)));
            } else {
                redeemed = _redeem(_amount);
            }
        }
    }

    // ###################
    // Internal
    // ###################

    function _redeem(uint256 _amount) internal returns (uint256 redeemed) {
        uint256 underlyingTokenBalanceBefore = underlyingToken.balanceOf(
            address(this)
        );

        eToken.withdraw(0, _amount);

        uint256 underlyingTokenBalanceAfter = underlyingToken.balanceOf(
            address(this)
        );
        redeemed = underlyingTokenBalanceAfter - underlyingTokenBalanceBefore;

        // transfer redeemed underlying tokens to msg.sender
        underlyingToken.safeTransfer(msg.sender, redeemed);
        // transfer gov tokens to msg.sender
        // _withdrawGovToken(msg.sender);
    }

    // ###################
    // Views
    // ###################

    /// @return net price in underlyings of 1 strategyToken
    function price() public view override returns (uint256) {
        uint256 decimals = eToken.decimals();
        // return price of 1 eToken in underlying
        return eToken.convertBalanceToUnderlying(10**decimals);
    }

    /// @dev Returns supply apr for providing liquidity minus reserveFee
    /// @return apr net apr (fees should already be excluded)
    function getApr() external view override returns (uint256 apr) {
        // Use the markets module:
        IMarkets markets = IMarkets(EULER_MARKETS);
        IDToken dToken = IDToken(markets.underlyingToDToken(token));
        uint256 borrowSPY = uint256(int256(markets.interestRate(token)));
        uint256 totalBorrows = dToken.totalSupply();
        uint256 totalBalancesUnderlying = eToken.totalSupplyUnderlying();
        uint32 reserveFee = markets.reserveFee(token);
        // (borrowAPY, supplyAPY)
        (, apr) = IEulerGeneralView(EULER_GENERAL_VIEW).computeAPYs(
            borrowSPY,
            totalBorrows,
            totalBalancesUnderlying,
            reserveFee
        );
        // apr is eg 0.024300334 * 1e27 for 2.43% apr
        // while the method needs to return the value in the format 2.43 * 1e18
        // so we do apr / 1e9 * 100 -> apr / 1e7
        apr = apr / 1e7;
    }

    /// @return tokens array of reward token addresses
    function getRewardTokens()
        external
        view
        override
        returns (address[] memory tokens)
    {}

    // ###################
    // Protected
    // ###################

    /// @notice Allow the CDO to pull stkAAVE rewards (forliquidity mining rewards)
    /// @return _bal amount of stkAAVE transferred
    function pullStkAAVE() external override returns (uint256 _bal) {}

    /// @notice This contract should not have funds at the end of each tx (except for stkAAVE), this method is just for leftovers
    /// @dev Emergency method
    /// @param _token address of the token to transfer
    /// @param value amount of `_token` to transfer
    /// @param _to receiver address
    function transferToken(
        address _token,
        uint256 value,
        address _to
    ) external onlyOwner nonReentrant {
        IERC20Detailed(_token).safeTransfer(_to, value);
    }

    /// @notice allow to update address whitelisted to pull stkAAVE rewards
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        whitelistedCDO = _cdo;
    }
}
