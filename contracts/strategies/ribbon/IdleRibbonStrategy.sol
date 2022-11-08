// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/ribbon/IPoolFactoryRibbon.sol";
import "../../interfaces/ribbon/IPoolMasterRibbon.sol";
import "../clearpool/IdleClearpoolStrategy.sol";

// NOTE Ribbon is a fork of clearpool with 2 differences:
// (1) reward token is retrieves using PoolFactory.rbn() (instead of PoolFactory.cpool())
// (2) IPoolMaster.provide(uint256, address) has an additional parameter for `referral`
//
contract IdleRibbonStrategy is
    IdleClearpoolStrategy
{
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice can be only called once
    /// @dev copied verbatim from IdleClearpoolStrategy except for (1) and name
    /// @param _cpToken address of the strategy token (lending pool)
    /// @param _underlyingToken address of the underlying token (pool currency)
    function initialize(
        address _cpToken,
        address _underlyingToken,
        address _owner,
        address _uniswapV2Router
    ) public override initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        cpToken = _cpToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        govToken = IPoolMasterRibbon(_cpToken).factory().rbn();

        ERC20Upgradeable.__ERC20_init(
            "Idle Ribbon Strategy Token",
            string(abi.encodePacked("idle_", IERC20Detailed(_cpToken).symbol()))
        );
        //------//-------//

        uniswapRouter = IUniswapV2Router02(_uniswapV2Router);

        transferOwnership(_owner);
    }

    /// @notice internal function to deposit the funds to the vault
    /// @dev copied verbatim from IdleClearpoolStrategy except for (2)
    /// @param _amount Amount of underlying tokens to deposit
    /// @return minted number of reward tokens minted
    function _depositToVault(uint256 _amount)
        override
        internal
        returns (uint256 minted)
    {
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

    /// @dev RBN path on univ2 to USDC is through WETH
    function _tokenToUnderlyingRate() internal override view returns (uint256) {
        address[] memory path = new address[](3);
        (path[0], path[1], path[2]) = (govToken, WETH, token);
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(10**18, path);
        return amountsOut[2];
    }
}
