// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/clearpool/IPoolFactory.sol";
import "../../interfaces/clearpool/IPoolMaster.sol";
import "../../interfaces/IPSM.sol";
import "./IdleClearpoolStrategy.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract IdleClearpoolPSMStrategy is
    IdleClearpoolStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IPSM public constant DAIPSM = IPSM(0xf6e72Db5454dd049d0788e411b06CfAF16853042);

    /// @notice can be only called once
    /// @param _cpToken address of the strategy token (lending pool)
    /// @param _underlyingToken address of the underlying token (pool currency)
    function initialize(
        address _cpToken,
        address _underlyingToken,
        address _owner,
        address _uniswapV2Router
    ) public virtual override {
        // initializer modifier not used in this contract as initialization check is already included in parent contract 
        // double initializer is not working anymore https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v4.4.1
        super.initialize(_cpToken, _underlyingToken, _owner, _uniswapV2Router);

        // approve psm and helper to spend DAI and USDC
        IERC20Detailed(DAI).safeApprove(address(DAIPSM), type(uint256).max);
        address psmGemJoin = DAIPSM.gemJoin();
        underlyingToken.safeApprove(address(psmGemJoin), type(uint256).max);
    }

    /// @notice this is needed in case PSM address needs to be changed
    function approvePSM() external onlyOwner {
        IERC20Detailed(DAI).safeApprove(address(DAIPSM), type(uint256).max);
        address psmGemJoin = DAIPSM.gemJoin();
        underlyingToken.safeApprove(address(psmGemJoin), type(uint256).max);
    }

    /// @notice return the price from the strategy token contract
    /// @return price
    function price() public view override returns (uint256) {
        // 18 decimals
        return IPoolMaster(cpToken).getCurrentExchangeRate();
    }

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount)
        external
        override
        onlyIdleCDO
        returns (uint256 minted)
    {
        if (_amount > 0) {
            IERC20Detailed(DAI).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            minted = _depositToVault(_amount);
        }
    }

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of cpTokens (underlying decimals)
    /// @return balanceReceived Amount of underlying tokens received
    function _redeem(uint256 _amount)
        override
        internal
        returns (uint256 balanceReceived)
    {
        // strategyToken (ie this contract) has 18 decimals
        _burn(msg.sender, (_amount * 1e18) / oneToken);
        IERC20Detailed _underlyingToken = underlyingToken;
        uint256 balanceBefore = _underlyingToken.balanceOf(address(this));
        // redeem USDC from clearpool
        IPoolMaster(cpToken).redeem(_amount);
        balanceReceived = _underlyingToken.balanceOf(address(this)) - balanceBefore;
        // buy DAI with USDC redeemed via PSM, Maker expect 18 decimals here
        buyDAI(balanceReceived);
        IERC20Detailed dai = IERC20Detailed(DAI);
        balanceReceived = dai.balanceOf(address(this));
        dai.safeTransfer(msg.sender, balanceReceived);
    }

    /// @notice internal function to deposit the funds to the vault
    /// @param _amount Amount of underlying tokens to deposit in DAI
    /// @return minted number of reward tokens minted
    function _depositToVault(uint256 _amount)
        virtual
        override
        internal
        returns (uint256 minted)
    {
        // convert amount of DAI in USDC, 1-to-1
        // Maker expect amount to be in `gem` (ie USDC in this case)
        _amount = _amount / 10**(18-tokenDecimals);
        sellDAI(_amount);
        // the amount passed here is in USDC (6 decimals)
        minted = super._depositToVault(_amount);
    }

    function sellDAI(uint256 _amount) internal {
        // 1inch fallback?
        require(DAIPSM.tin() == 0 && DAIPSM.tout() == 0, 'FEE!0');
        DAIPSM.buyGem(address(this), _amount);
    }

    function buyDAI(uint256 _amount) internal {
        // 1inch fallback?
        require(DAIPSM.tin() == 0 && DAIPSM.tout() == 0, 'FEE!0');
        DAIPSM.sellGem(address(this), _amount);
    }
}
