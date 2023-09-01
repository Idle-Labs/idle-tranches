// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IPoLidoNFT.sol";
import "./interfaces/IStMatic.sol";

import "./IdleCDO.sol";

/// @title IdleCDO variant for Polido strategy
/// @author Idle DAO, @massun-onibakuchi
contract IdleCDOPoLidoVariant is IdleCDO, IERC721ReceiverUpgradeable {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice stMatic contract
    IStMATIC public constant stMatic = IStMATIC(0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599);

    // NOTE: override this function
    /// @notice method used to deposit `token` and mint tranche tokens
    /// @dev deposit underlyings to strategy immediately
    /// @return _minted number of tranche tokens minted
    function _deposit(
        uint256 _amount,
        address _tranche,
        address _referral
    ) internal override whenNotPaused returns (uint256 _minted) {
        _minted = super._deposit(_amount, _tranche, _referral);
        IIdleCDOStrategy(strategy).deposit(_amount);
    }

    /// @notice It allows users to burn their tranche token and redeem their principal + interest back
    /// @dev automatically reverts on lending provider default (_strategyPrice decreased).
    /// @param _amount in tranche tokens
    /// @param _tranche tranche address
    /// @return toRedeem number of underlyings redeemed
    function _withdraw(uint256 _amount, address _tranche) internal override nonReentrant returns (uint256 toRedeem) {
        // check if a deposit is made in the same block from the same user
        _checkSameTx();
        // check if _strategyPrice decreased
        _checkDefault();
        // accrue interest to tranches and updates tranche prices
        _updateAccounting();
        // redeem all user balance if 0 is passed as _amount
        if (_amount == 0) {
            _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
        }
        require(_amount != 0, "0");

        // Calculate the amount to redeem
        toRedeem = (_amount * _tranchePrice(_tranche)) / ONE_TRANCHE_TOKEN;

        // NOTE: modified from IdleCDO
        // request unstaking matic from poLido strategy and receive an nft.
        toRedeem = _liquidate(toRedeem, revertIfTooLow);
        // burn tranche token
        IdleCDOTranche(_tranche).burn(msg.sender, _amount);

        // NOTE: modified from IdleCDO
        // send an PoLido nft not matic to msg.sender
        uint256[] memory tokenIds = stMatic.poLidoNFT().getOwnedTokens(address(this));
        require(tokenIds.length != 0, "no NFTs");

        // update NAV with the _amount of underlyings removed
        if (_tranche == AATranche) {
            lastNAVAA -= toRedeem;
        } else {
            lastNAVBB -= toRedeem;
        }

        // update trancheAPRSplitRatio
        _updateSplitRatio(_getAARatio(true));

        uint256 tokenId = tokenIds[tokenIds.length - 1];
        stMatic.poLidoNFT().safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}
