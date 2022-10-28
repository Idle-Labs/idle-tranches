// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/IPSM.sol";
import "../clearpool/IdleClearpoolPSMStrategy.sol";
import "./IdleRibbonStrategy.sol";

// NOTE overrided implementation here is exactly the same as IdleRibbonStrategy except for the 
// initialize which has the additional initialize steps of IdleClerapoolPSMStrategy and same for
// _depositToVault
contract IdleRibbonPSMStrategy is
    IdleClearpoolPSMStrategy
{
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice can be only called once
    /// @param _cpToken address of the strategy token (lending pool)
    /// @param _underlyingToken address of the underlying token (pool currency)
    function initialize(
        address _cpToken,
        address _underlyingToken,
        address _owner,
        address _uniswapV2Router
    ) public virtual override initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        cpToken = _cpToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        govToken = IPoolFactoryRibbon(address(IPoolMaster(_cpToken).factory())).rbn();

        ERC20Upgradeable.__ERC20_init(
            "Idle Ribbon Strategy Token",
            string(abi.encodePacked("idle_", IERC20Detailed(_cpToken).symbol()))
        );
        //------//-------//

        uniswapRouter = IUniswapV2Router02(_uniswapV2Router);

        transferOwnership(_owner);

        // approve psm and helper to spend DAI and USDC
        IERC20Detailed(DAI).safeApprove(address(DAIPSM), type(uint256).max);
        address psmGemJoin = DAIPSM.gemJoin();
        underlyingToken.safeApprove(address(psmGemJoin), type(uint256).max);
    }

    /// @notice internal function to deposit the funds to the vault
    /// @param _amount Amount of underlying tokens to deposit in DAI
    /// @return minted number of reward tokens minted
    function _depositToVault(uint256 _amount)
        override
        internal
        returns (uint256 minted)
    {
        // convert amount of DAI in USDC, 1-to-1
        // Maker expect amount to be in `gem` (ie USDC in this case)
        _amount = _amount / 10**(18-tokenDecimals);
        sellDAI(_amount);

        // This part is copied from IdleRibbonStrategy
        address _cpToken = cpToken;
        underlyingToken.safeApprove(_cpToken, _amount);

        uint256 balanceBefore = IERC20Detailed(_cpToken).balanceOf(
            address(this)
        );
        IPoolMasterRibbon(_cpToken).provide(_amount, address(this));
        minted =
            IERC20Detailed(_cpToken).balanceOf(address(this)) -
            balanceBefore;
        minted = (minted * 10**18) / oneToken;
        _mint(msg.sender, minted);
    }

    /// @dev copied from IdleRibbonStrategy
    function _tokenToUnderlyingRate() internal override view returns (uint256) {
        address[] memory path = new address[](3);
        (path[0], path[1], path[2]) = (govToken, WETH, token);
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(10**18, path);
        return amountsOut[2];
    }
}
