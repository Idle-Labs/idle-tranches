// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IMAsset.sol";
import "./interfaces/IIdleMStableStrategy.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IdleMStableStrategyWrapper {
    using SafeMath for uint256;

    IMAsset public mUSD;
    IIdleMStableStrategy public idleMStableStrategy;
    uint256 public minOutputPercentage = 95000; // means 95%

    constructor(address _mUSD, address _idleMStableStrategy) {
        mUSD = IMAsset(_mUSD);
        idleMStableStrategy = IIdleMStableStrategy(_idleMStableStrategy);
    }

    // this contract must be approved
    function saveDirectlyToIdleMStableStrategy(address token, uint256 _amount)
        public
    {
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

        mUSD.approve(address(idleMStableStrategy), mUSDReceived);

        uint256 sharesReceived = idleMStableStrategy.deposit(mUSDReceived);
        idleMStableStrategy.transferShares(
            msg.sender,
            sharesReceived,
            sharesReceived
        );
    }
}
