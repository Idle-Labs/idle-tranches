// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC4626.sol";

import "./IdleCDO.sol";

contract TrancheWrapper is ReentrancyGuard, ERC20, IERC4626 {
    uint256 internal constant ONE_TRANCHE_TOKEN = 1e18;

    IdleCDO public immutable idleCDO;
    address public immutable token;
    address public immutable tranche;
    bool internal immutable isAATranche;

    constructor(IdleCDO _idleCDO, address _tranche)
        ERC20(
            string(abi.encodePacked(ERC20(_tranche).name(), "4626Adapter")),
            string(abi.encodePacked(ERC20(_tranche).symbol(), "4626"))
        )
    {
        idleCDO = _idleCDO;
        tranche = _tranche; // 18 decimals
        token = idleCDO.token();
        isAATranche = idleCDO.AATranche() == _tranche;
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     */
    function asset() external view returns (address assetTokenAddress) {
        return token;
    }

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     */
    function totalAssets() external view returns (uint256 totalManagedAssets) {
        return idleCDO.getContractValue();
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        return ((assets * ONE_TRANCHE_TOKEN) / idleCDO.tranchePrice(address(this)));
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * idleCDO.tranchePrice(address(this))) / ONE_TRANCHE_TOKEN;
    }

    /** @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

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
        uint256 assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        (uint256 assetsUsed, uint256 mintedShares) = _deposit(assets, receiver, msg.sender);
        require(shares <= mintedShares, "tw: all of shares cannot be minted");

        emit Deposit(msg.sender, receiver, assetsUsed, mintedShares);
        return assetsUsed;
    }

    /**
     * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
     * @notice revert if all of assets cannot be withdrawn.
     */
    // TODO: add allowance check to use owner argument
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256) {
        uint256 shares = previewWithdraw(assets); // ?? No need to check for rounding error, previewWithdraw rounds up.

        (uint256 _withdrawn, uint256 _burntShares) = _redeem(shares, receiver, msg.sender);
        require(_withdrawn >= assets, "tw: all of assets cannot be withdrawn");

        emit Withdraw(msg.sender, receiver, owner, _withdrawn, _burntShares);
        return _burntShares;
    }

    // TODO: add allowance check to use owner argument
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256) {
        (uint256 _withdrawn, uint256 _burntShares) = _redeem(shares, receiver, msg.sender);

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
    function maxDeposit(address receiver) public view returns (uint256) {
        IdleCDO _idleCDO = idleCDO;

        uint256 _depositLimit = _idleCDO.limit(); // TVL limit in underlying value
        uint256 _totalAssets = _idleCDO.getContractValue(); // TVL in underlying value
        if (_depositLimit == 0) return type(uint256).max; // 0 means unlimited
        if (_totalAssets >= _depositLimit) return 0;
        return _depositLimit - _totalAssets;
    }

    function maxMint(address receiver) external view returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        bool withdrawable = isAATranche ? idleCDO.allowAAWithdraw() : idleCDO.allowBBWithdraw();
        if (!withdrawable) return 0;
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        bool withdrawable = isAATranche ? idleCDO.allowAAWithdraw() : idleCDO.allowBBWithdraw();
        if (!withdrawable) return 0;
        return balanceOf(owner);
    }

    /// @notice Deposit underlying tokens into IdleCDO
    /// @dev This function SHOULD be guarded to prevent potential reentrancy
    /// @param amount Amount of underlying tokens to deposit
    /// @param receiver receiver of tranche shares
    /// @param depositor depositor of underlying tokens
    function _deposit(
        uint256 amount,
        address receiver,
        address depositor
    ) internal returns (uint256 deposited, uint256 mintedShares) {
        IdleCDO _idleCDO = idleCDO;
        IERC20 _token = IERC20(token);

        SafeERC20.safeTransferFrom(_token, depositor, address(this), amount);

        if (_token.allowance(address(this), address(_idleCDO)) < amount) {
            _token.approve(address(_idleCDO), 0); // Avoid issues with some tokens requiring 0
            _token.approve(address(_idleCDO), type(uint256).max); // Vaults are trusted
        }

        uint256 beforeBal = _token.balanceOf(address(this));

        if (isAATranche) {
            mintedShares = _idleCDO.depositAA(deposited);
        } else {
            mintedShares = _idleCDO.depositBB(deposited);
        }
        uint256 afterBal = _token.balanceOf(address(this));
        deposited = beforeBal - afterBal;

        _mint(receiver, mintedShares);
    }

    /// @notice Withdraw underlying tokens from IdleCDO
    /// @dev This function SHOULD be guarded to prevent potential reentrancy
    /// @param shares shares to withdraw
    /// @param receiver receiver of underlying tokens withdrawn from IdleCDO
    /// @param sender sender of tranche shares
    function _redeem(
        uint256 shares,
        address receiver,
        address sender
    ) internal returns (uint256 withdrawn, uint256 burntShares) {
        IdleCDO _idleCDO = idleCDO;
        IERC20 _tranche = IERC20(tranche);

        // withdraw from idleCDO
        uint256 beforeBal = _tranche.balanceOf(address(this));

        if (isAATranche) {
            withdrawn = _idleCDO.withdrawAA(shares);
        } else {
            withdrawn = _idleCDO.withdrawBB(shares);
        }

        burntShares = beforeBal - _tranche.balanceOf(address(this));
        _burn(sender, burntShares);

        SafeERC20.safeTransfer(IERC20(token), receiver, withdrawn);
    }
}
