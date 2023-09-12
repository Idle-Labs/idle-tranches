// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./interfaces/IERC4626Upgradeable.sol";

import "./IdleCDO.sol";

contract TrancheWrapper is ReentrancyGuardUpgradeable, ERC20Upgradeable, IERC4626Upgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    error AmountZero();

    event CloneCreated(address indexed instance);

    uint256 internal constant ONE_TRANCHE_TOKEN = 1e18;

    /// @dev flag to check if the contract has been cloned via minimal proxy or not
    /// @notice original contract set the flag to true.
    bool public isOriginal;

    IdleCDO public idleCDO;
    address public token;
    address public tranche;
    bool internal isAATranche;

    /// @dev constructor doesn't run if the contract is cloned via minimal proxy
    ///      proxy executes the runtime code that does not include the constructor
    constructor() {
        isOriginal = true;
        token = address(1);
    }

    function initialize(IdleCDO _idleCDO, address _tranche) public virtual initializer {
        __ReentrancyGuard_init();
        __ERC20_init(
            string(abi.encodePacked(ERC20Upgradeable(_tranche).name(), "4626Adapter")),
            string(abi.encodePacked(ERC20Upgradeable(_tranche).symbol(), "4626"))
        );
        require(token == address(0), "Token is already initialized");
        idleCDO = _idleCDO;
        tranche = _tranche; // 18 decimals
        token = idleCDO.token();
        isAATranche = idleCDO.AATranche() == _tranche;

        ERC20Upgradeable(token).safeApprove(address(_idleCDO), type(uint256).max); // Vaults are trusted
    }

    /// @dev clone the contract via minimal proxy. proxy contract must be deployed by the original contract.
    /// @notice the clone is created with the same code of the original contract
    function clone(IdleCDO _idleCDO, address _tranche) external returns (address instance) {
        require(isOriginal, "!clone");
        bytes32 salt = keccak256(abi.encodePacked(address(_idleCDO), _tranche));
        instance = ClonesUpgradeable.cloneDeterministic(address(this), salt);
        TrancheWrapper(instance).initialize(_idleCDO, _tranche);

        emit CloneCreated(instance);
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
        return idleCDO.getContractValue();
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToShares(uint256 assets) public virtual view returns (uint256) {
        return ((assets * ONE_TRANCHE_TOKEN) / idleCDO.virtualPrice(tranche));
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToAssets(uint256 shares) public virtual view returns (uint256) {
        return (shares * idleCDO.virtualPrice(tranche)) / ONE_TRANCHE_TOKEN;
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
        IdleCDO _idleCDO = idleCDO;

        uint256 _depositLimit = _idleCDO.limit(); // TVL limit in underlying value
        uint256 _totalAssets = _idleCDO.getContractValue(); // TVL in underlying value
        if (_depositLimit == 0) return type(uint256).max; // 0 means unlimited
        if (_totalAssets >= _depositLimit) return 0;
        return _depositLimit - _totalAssets;
    }

    function maxMint(address receiver) external view returns (uint256) {
        uint256 _maxDeposit = maxDeposit(receiver);
        if (_maxDeposit == type(uint256).max) return type(uint256).max;
        return convertToShares(_maxDeposit);
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
    ) internal virtual returns (uint256 deposited, uint256 mintedShares) {
        IdleCDO _idleCDO = idleCDO;
        ERC20Upgradeable _token = ERC20Upgradeable(token);

        SafeERC20Upgradeable.safeTransferFrom(_token, depositor, address(this), amount);

        uint256 beforeBal = _token.balanceOf(address(this));

        if (isAATranche) {
            mintedShares = _idleCDO.depositAA(amount);
        } else {
            mintedShares = _idleCDO.depositBB(amount);
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
    ) internal virtual returns (uint256 withdrawn, uint256 burntShares) {
        IdleCDO _idleCDO = idleCDO;
        ERC20Upgradeable _tranche = ERC20Upgradeable(tranche);

        // withdraw from idleCDO
        uint256 beforeBal = _tranche.balanceOf(address(this));

        if (isAATranche) {
            withdrawn = _idleCDO.withdrawAA(shares);
        } else {
            withdrawn = _idleCDO.withdrawBB(shares);
        }

        burntShares = beforeBal - _tranche.balanceOf(address(this));
        _burnFrom(sender, burntShares);
        SafeERC20Upgradeable.safeTransfer(ERC20Upgradeable(token), receiver, withdrawn);
    }

    function _burnFrom(address account, uint256 amount) internal {
        if (account != msg.sender) {
            uint256 currentAllowance = allowance(account, msg.sender);
            require(currentAllowance >= amount, "tw: burn amount exceeds allowance");
            unchecked {
                _approve(account, msg.sender, currentAllowance - amount);
            }
        }
        _burn(account, amount);
    }
}
