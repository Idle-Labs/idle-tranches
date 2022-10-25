// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC4626.sol";

import "./IdleCDO.sol";

contract TrancheWrapper is ERC20, IERC4626 {
    uint256 internal ONE_TRANCHE_TOKEN = 1e18;

    IdleCDO public immutable idleCDO;
    address public immutable token;
    address public immutable tranche;
    bool internal immutable isAATranche;

    constructor(address _idleCDO, address _tranche) ERC20("TrancheWrapper", "TW") {
        idleCDO = IdleCDO(_idleCDO);
        tranche = _tranche;
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
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
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
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        (assets, shares) = _deposit(assets, receiver, msg.sender);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        (assets, shares) = _deposit(assets, receiver, msg.sender);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // TODO: add allowance check to use owner argument
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public returns (uint256) {
        (uint256 _withdrawn, uint256 _burntShares) = _withdraw(assets, receiver, msg.sender);

        emit Withdraw(msg.sender, receiver, owner, _withdrawn, _burntShares);
        return _burntShares;
    }

    // TODO: add allowance check to use owner argument
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public returns (uint256) {
        uint256 assets = previewRedeem(shares);
        require(assets != 0, "ZERO_ASSETS");

        (uint256 _withdrawn, uint256 _burntShares) = _withdraw(assets, receiver, msg.sender);

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

        uint256 _depositLimit = _idleCDO.limit();
        uint256 _totalAssets = _idleCDO.getContractValue();
        if (_depositLimit == 0) return type(uint256).max;
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

    function _withdraw(
        uint256 amount, // if `MAX_UINT256`, just withdraw everything
        address receiver,
        address sender
    ) internal returns (uint256 withdrawn, uint256 burntShares) {
        IdleCDO _idleCDO = idleCDO;
        IERC20 _tranche = IERC20(tranche);

        uint256 shares = (amount * ONE_TRANCHE_TOKEN) / _idleCDO.tranchePrice(tranche);

        // withdraw from vault and get total used shares
        uint256 beforeBal = _tranche.balanceOf(address(this));

        if (isAATranche) {
            withdrawn = _idleCDO.withdrawAA(shares);
        } else {
            withdrawn = _idleCDO.withdrawBB(shares);
        }

        burntShares = beforeBal - _tranche.balanceOf(address(this));

        _burn(receiver, burntShares);

        SafeERC20.safeTransfer(_token, receiver, withdrawn);
    }
}
