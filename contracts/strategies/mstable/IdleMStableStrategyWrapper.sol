// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/IMAsset.sol";

import "../../IdleCDO.sol";

contract IdleMStableStrategyWrapper {
    IMAsset public mUSD;
    IdleCDO public immutable idleCDO;

    constructor(address _mUSD, IdleCDO _idleCDO) {
        mUSD = IMAsset(_mUSD);
        idleCDO = IdleCDO(_idleCDO);
    }

    /// @dev Must approve the underlying token before calling
    /// @notice Deposit one of the token supported by mstable and get AAtranche tokens
    /// @param token Address of the token to deposit (ex: DAI, USDC, USDT ...)
    /// @param _amount Amount of tokens to deposit
    /// @param minOutputQuantity Minimum number of mUSD token to receive on deposit
    function depositAAWithToken(
        address token,
        uint256 _amount,
        uint256 minOutputQuantity
    ) public returns (uint256) {
        return _depositToken(token, _amount, minOutputQuantity, true);
    }

    /// @dev Must approve the underlying token before callings
    /// @notice Deposit one of the token supported by mstable and get BBtranche tokens
    /// @param token Address of the token to deposit (ex: DAI, USDC, USDT ...)
    /// @param _amount Amount of tokens to deposit
    /// @param minOutputQuantity Minimum number of mUSD token to receive on deposit
    function depositBBWithToken(
        address token,
        uint256 _amount,
        uint256 minOutputQuantity
    ) public returns (uint256) {
        return _depositToken(token, _amount, minOutputQuantity, false);
    }

    /// @dev Must approve AA tranche tokens before callings
    /// @notice Withdraw one of the token supported by mstable to receive (ex: DAI, USDC, USDT ...)
    /// @param tokenToReceive Token to receive
    /// @param amount Amount of AA Tranche tokens to burn
    /// @param minReceiveQuantity minimum number of tokens to receive from mstable
    function withdrawTokenViaBurningAA(
        address tokenToReceive,
        uint256 amount,
        uint256 minReceiveQuantity
    ) public returns (uint256) {
        return _withdrawToken(tokenToReceive, amount, minReceiveQuantity, true);
    }

    /// @dev Must approve BB tranche tokens before callings
    /// @notice Withdraw one of the token supported by mstable to receive (ex: DAI, USDC, USDT ...)
    /// @param tokenToReceive Token to receive
    /// @param amount Amount of BB Tranche tokens to burn
    /// @param minReceiveQuantity minimum number of tokens to receive from mstable
    function withdrawTokenViaBurningBB(
        address tokenToReceive,
        uint256 amount,
        uint256 minReceiveQuantity
    ) public returns (uint256) {
        return _withdrawToken(tokenToReceive, amount, minReceiveQuantity, false);
    }

    /// @notice Internal function to deposit the tokens
    /// @param token Address of token to deposit
    /// @param _amount Amount of tokens to deposit
    /// @param _minOutputQuantity minimum number of output tokens to receive
    /// @param isTrancheAA if true AA tokens are generated, else BB tokens are generated
    function _depositToken(
        address token,
        uint256 _amount,
        uint256 _minOutputQuantity,
        bool isTrancheAA
    ) internal returns (uint256) {
        address tranche = isTrancheAA ? idleCDO.AATranche() : idleCDO.BBTranche();

        IERC20Detailed tokenContract = IERC20Detailed(token);
        tokenContract.transferFrom(msg.sender, address(this), _amount);
        tokenContract.approve(address(mUSD), _amount);
        uint256 mUSDReceived = mUSD.mint(token, _amount, _minOutputQuantity, address(this));
        mUSD.approve(address(idleCDO), mUSDReceived);

        uint256 tTokens;
        if (isTrancheAA) {
            tTokens = idleCDO.depositAA(mUSDReceived);
        } else {
            tTokens = idleCDO.depositBB(mUSDReceived);
        }
        IERC20Detailed(tranche).transfer(msg.sender, tTokens);
        return tTokens;
    }

    /// @notice Internal function to withdraw the tokens (supported by mstable. Ex: DAI, USDC, USDT)
    /// @param token Address of the token to withdraw in
    /// @param _amount Number of Tranche tokens to burn
    /// @param _minOutputQuantity Minimum number of tokens to receive from mstable
    /// @param isTrancheAA if true AA Tranche tokens are burned, else BB Tranche tokens are burned
    function _withdrawToken(
        address token,
        uint256 _amount,
        uint256 _minOutputQuantity,
        bool isTrancheAA
    ) internal returns (uint256) {
        address tranche = isTrancheAA ? idleCDO.AATranche() : idleCDO.BBTranche();
        IERC20Detailed trancheToken = IERC20Detailed(tranche);
        trancheToken.transferFrom(msg.sender, address(this), _amount);
        trancheToken.approve(address(idleCDO), _amount);

        uint256 underlyingMusdReceived;
        if (isTrancheAA) {
            underlyingMusdReceived = idleCDO.withdrawAA(_amount);
        } else {
            underlyingMusdReceived = idleCDO.withdrawBB(_amount);
        }

        return mUSD.redeem(token, underlyingMusdReceived, _minOutputQuantity, msg.sender);
    }
}
