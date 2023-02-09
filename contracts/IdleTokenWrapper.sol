// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IERC4626Upgradeable.sol";
import "../contracts/interfaces/IIdleTokenFungible.sol";

contract IdleTokenWrapper is ReentrancyGuardUpgradeable, ERC20Upgradeable, IERC4626Upgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    error AmountZero();
    error InsufficientAllowance();

    uint256 internal constant ONE_18 = 1e18;
    address internal constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

    IIdleTokenFungible public idleToken;
    address public token;

    function initialize(IIdleTokenFungible _idleToken) external initializer {
        __ReentrancyGuard_init();
        __ERC20_init(
            string(abi.encodePacked(_idleToken.name(), "4626Adapter")),
            string(abi.encodePacked(_idleToken.symbol(), "4626"))
        );
        idleToken = _idleToken;
        token = _idleToken.token();

        ERC20Upgradeable(token).safeApprove(address(_idleToken), type(uint256).max); // Vaults are trusted
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     */
    function asset() external view returns (address) {
        return token;
    }

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     */
    function totalAssets() external view returns (uint256) {
        // price: value of 1 idleToken in underlying
        // NOTE: the value is different from assets mangaed by the wrapper
        return (idleToken.tokenPrice() * idleToken.totalSupply()) / ONE_18;
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     * NOTE: `convertTo` functions are both always round down.
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        return ((assets * ONE_18) / idleToken.tokenPrice());
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * idleToken.tokenPrice()) / ONE_18;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @dev Return the amount of assets a user has to provide to receive a certain amount of shares.
     * @notice return as close to and no fewer than the exact amount of assets that would be deposited in a mint call in the same transaction.
     * NOTE: rounds up.
     */
    function previewMint(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares) + 1;
    }

    /**
     * @dev Return the amount of shares a user has to redeem to receive a given amount of assets.
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                      DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     */
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        (assets, shares) = _deposit(assets, receiver, msg.sender);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
     * @notice revert if all of shares cannot be minted.
     */
    function mint(uint256 shares, address receiver) external nonReentrant returns (uint256) {
        if (shares == 0) revert AmountZero();
        uint256 assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        (uint256 assetsUsed, uint256 mintedShares) = _deposit(assets, receiver, msg.sender);

        emit Deposit(msg.sender, receiver, assetsUsed, mintedShares);
        return assetsUsed;
    }

    /// @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
    /// @notice Due to rounding errors, it is possible that less than amount of underlying tokens are sent.
    /// @param assets amount of assets to redeem. If it is equal to type(uint256).max, redeem all shares
    /// @param receiver address to send redeemed assets to
    /// @param owner address to burn shares from
    /// @return shares burned
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256) {
        if (assets == 0) revert AmountZero();
        uint256 shares = (assets == type(uint256).max) ? balanceOf(owner) : previewWithdraw(assets);

        (uint256 _withdrawn, uint256 _burntShares) = _redeem(shares, receiver, owner);

        emit Withdraw(msg.sender, receiver, owner, _withdrawn, _burntShares);
        return _burntShares;
    }

    /// @notice Redeems shares from owner and sends assets of underlying tokens to receiver.
    /// @notice Due to rounding errors, redeem may return less than requested.
    /// @param shares amount of shares to redeem. If shares == type(uint256).max, redeem all shares.
    /// @param receiver address to send redeemed assets to
    /// @param owner address to burn shares from
    /// @return amount of assets withdrawn
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256) {
        if (shares == type(uint256).max) shares = balanceOf(owner);

        (uint256 _withdrawn, uint256 _burntShares) = _redeem(shares, receiver, owner);

        emit Withdraw(msg.sender, receiver, owner, _withdrawn, _burntShares);
        return _withdrawn;
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
     * through a deposit call.
     */
    function maxDeposit(
        address /* receiver */
    ) public view returns (uint256) {
        return idleToken.paused() ? 0 : type(uint256).max;
    }

    function maxMint(
        address /* receiver */
    ) external view returns (uint256) {
        return idleToken.paused() ? 0 : type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return idleToken.paused() ? 0 : convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return idleToken.paused() ? 0 : balanceOf(owner);
    }

    /// @notice Deposit underlying tokens into IdleTokenFungible
    /// @dev This function SHOULD be guarded to prevent potential reentrancy
    /// @param amount Amount of underlying tokens to deposit
    /// @param receiver receiver of tranche shares
    /// @param depositor depositor of underlying tokens
    function _deposit(
        uint256 amount,
        address receiver,
        address depositor
    ) internal returns (uint256 deposited, uint256 mintedShares) {
        ERC20Upgradeable _token = ERC20Upgradeable(token);

        SafeERC20Upgradeable.safeTransferFrom(_token, depositor, address(this), amount);

        uint256 beforeBal = _token.balanceOf(address(this));
        mintedShares = idleToken.mintIdleToken(amount, true, TL_MULTISIG);
        uint256 afterBal = _token.balanceOf(address(this));

        deposited = beforeBal - afterBal;

        _mint(receiver, mintedShares);
    }

    /// @notice Withdraw underlying tokens from IdleTokenFungible
    /// @dev This function SHOULD be guarded to prevent potential reentrancy
    /// @param shares shares to withdraw
    /// @param receiver receiver of underlying tokens withdrawn from IdleTokenFungible
    /// @param sender sender of tranche shares
    function _redeem(
        uint256 shares,
        address receiver,
        address sender
    ) internal returns (uint256 withdrawn, uint256 burntShares) {
        IIdleTokenFungible _idleToken = idleToken;

        // withdraw from idleToken
        uint256 beforeBal = _idleToken.balanceOf(address(this));
        withdrawn = _idleToken.redeemIdleToken(shares);
        burntShares = beforeBal - _idleToken.balanceOf(address(this));

        _burnFrom(sender, burntShares);
        SafeERC20Upgradeable.safeTransfer(ERC20Upgradeable(token), receiver, withdrawn);
    }

    function _burnFrom(address account, uint256 amount) internal {
        if (account != msg.sender) {
            uint256 currentAllowance = allowance(account, msg.sender);
            if (currentAllowance < amount) {
                revert InsufficientAllowance();
            }
            unchecked {
                _approve(account, msg.sender, currentAllowance - amount);
            }
        }
        _burn(account, amount);
    }
}
