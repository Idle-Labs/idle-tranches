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

    uint256 public minOutputPercentage = 95000; // means 95%

    constructor(address _mUSD, IdleCDO _idleCDO) {
        mUSD = IMAsset(_mUSD);
        idleCDO = IdleCDO(_idleCDO);
    }

    // this contract must be approved, token must one of the underlying token of mUSD
    function depositAAWithToken(address token, uint256 _amount) public {
        IERC20Detailed tokenContract = IERC20Detailed(token);
        tokenContract.transferFrom(msg.sender, address(this), _amount);
        tokenContract.approve(address(mUSD), _amount);
        uint256 _minOutputQuantity = _amount.mul(minOutputPercentage).div(
            1000000
        );
        uint256 mUSDReceived = mUSD.mint(
            token,
            _amount,
            _minOutputQuantity,
            address(this)
        );

        mUSD.approve(address(idleCDO), mUSDReceived);

        uint256 aaReceived = idleCDO.depositAA(mUSDReceived);
        IERC20Detailed(idleCDO.AATranche()).transfer(msg.sender, aaReceived);
    }

    // this contract must be approved, token must one of the underlying token of mUSD
    function depositBBWithToken(address token, uint256 _amount) public {
        IERC20Detailed tokenContract = IERC20Detailed(token);
        tokenContract.transferFrom(msg.sender, address(this), _amount);
        tokenContract.approve(address(mUSD), _amount);
        uint256 _minOutputQuantity = _amount.mul(minOutputPercentage).div(
            1000000
        );
        uint256 mUSDReceived = mUSD.mint(
            token,
            _amount,
            _minOutputQuantity,
            address(this)
        );

        mUSD.approve(address(idleCDO), mUSDReceived);

        uint256 bbReceived = idleCDO.depositBB(mUSDReceived);
        IERC20Detailed(idleCDO.BBTranche()).transfer(msg.sender, bbReceived);
    }
}
