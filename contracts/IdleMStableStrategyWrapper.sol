// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IMAsset.sol";
import "./interfaces/IIdleMStableStrategy.sol";

import "./IdleCDO.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IdleMStableStrategyWrapper {
    using SafeMath for uint256;

    IMAsset public mUSD;
    IdleCDO public immutable idleCDO;

    constructor(address _mUSD, IdleCDO _idleCDO) {
        mUSD = IMAsset(_mUSD);
        idleCDO = IdleCDO(_idleCDO);
    }

    // this contract must be approved, token must one of the underlying token of mUSD
    function depositAAWithToken(
        address token,
        uint256 _amount,
        uint256 minOutputQuantity
    ) public returns (uint256) {
        return _depositToken(token, _amount, minOutputQuantity, true);
    }

    // this contract must be approved, token must one of the underlying token of mUSD
    function depositBBWithToken(
        address token,
        uint256 _amount,
        uint256 minOutputQuantity
    ) public returns (uint256) {
        return _depositToken(token, _amount, minOutputQuantity, false);
    }

    function withdrawTokenViaBurningAA(
        address tokenToReceive,
        uint256 amount,
        uint256 minReceiveQuantity
    ) public {
        _withdrawToken(tokenToReceive, amount, minReceiveQuantity, true);
    }

    function withdrawTokenViaBurningBB(
        address tokenToReceive,
        uint256 amount,
        uint256 minReceiveQuantity
    ) public {
        _withdrawToken(tokenToReceive, amount, minReceiveQuantity, false);
    }

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

    // user must approve tranche tokens
    // token = token that you want to receive
    function _withdrawToken(
        address token,
        uint256 _amount,
        uint256 _minOutputQuantity,
        bool isTrancheAA
    ) internal {
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
        mUSD.redeem(token, underlyingMusdReceived, _minOutputQuantity, msg.sender);
    }
}
