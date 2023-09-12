// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./interfaces/IERC4626Upgradeable.sol";

import "./interfaces/IWstETH.sol";
import "./TrancheWrapper.sol";
import "./IdleCDO.sol";

/// @dev this variant is not fully compliant with ERC4626 standard but it used for the integration with Balancer
/// boosted pools. 
/// boosted pools only use a subset of the ERC4624 interface
contract TrancheWrapperWSTETHBalancer is TrancheWrapper {
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function initialize(IdleCDO _idleCDO, address _tranche) public override {
        // initializer modifier not used in this contract as initialization check is already included in parent contract 
        // double initializer is not working anymore https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v4.4.1
        super.initialize(_idleCDO, _tranche);
        // approve wstETH to wrap our stETH
        ERC20Upgradeable(token).approve(WSTETH, type(uint256).max);
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToAssets(uint256 shares) public override view returns (uint256) {
        // shares * virtualPrice is an stETHAmount multiplied by 1e18 
        // we div this the wstETH price
        return (shares * idleCDO.virtualPrice(tranche)) / IWstETH(WSTETH).stEthPerToken();
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToShares(uint256 assets) public override view returns (uint256) {
        // assets is wsteth
        return ((assets * IWstETH(WSTETH).stEthPerToken()) / idleCDO.virtualPrice(tranche));
    }

    /*//////////////////////////////////////////////////////////////
                      DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/


    /// @notice Deposit underlying tokens into IdleCDO
    /// @dev This function SHOULD be guarded to prevent potential reentrancy
    /// @param amount Amount of underlying tokens to deposit. This is in wstETH
    /// @param receiver receiver of tranche shares
    /// @param depositor depositor of underlying tokens
    function _deposit(
        uint256 amount,
        address receiver,
        address depositor
    ) internal override returns (uint256 deposited, uint256 mintedShares) {
        // get wsteth in this contract
        ERC20Upgradeable _token = ERC20Upgradeable(WSTETH);
        SafeERC20Upgradeable.safeTransferFrom(_token, depositor, address(this), amount);
        // get wstETH balance
        uint256 wBalBefore = _token.balanceOf(address(this));
        // unwrap wstETH into stETH
        IWstETH(WSTETH).unwrap(amount);
        // set amount of assets used
        deposited = wBalBefore - ERC20Upgradeable(WSTETH).balanceOf(address(this));

        // set _token to stETH
        _token = ERC20Upgradeable(token);
        // get stETH amount received after wrap
        amount = _token.balanceOf(address(this));

        IdleCDO _idleCDO = idleCDO;
        if (isAATranche) {
            mintedShares = _idleCDO.depositAA(amount);
        } else {
            mintedShares = _idleCDO.depositBB(amount);
        }

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
    ) internal override returns (uint256 withdrawn, uint256 burntShares) {
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
        // Everything before this comment is the same as TrancheWrapper.sol

        // we now have stETH in this contract that we need wrap in wstETH
        IWstETH(WSTETH).wrap(withdrawn);
        // we now have wstETH that we send to user
        ERC20Upgradeable wstETH = ERC20Upgradeable(WSTETH);
        withdrawn = wstETH.balanceOf(address(this));
        SafeERC20Upgradeable.safeTransfer(wstETH, receiver, withdrawn);
    }
}
