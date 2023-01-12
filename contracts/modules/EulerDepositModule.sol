// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "./BaseDepositModule.sol";
import "../interfaces/euler/IEToken.sol";

contract EulerDepositModule is BaseDepositModule {
    /// @notice Euler markets contract address
    address internal constant EULER_MARKETS = 0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3;
    uint256 internal constant SUB_ACCOUNT_ID = 0;

    function _depositCollateral(address _token, uint256 _amount)
        internal
        virtual
        override
        returns (uint256 _collateralAdded)
    {
        IEToken(_token).deposit(SUB_ACCOUNT_ID, _amount);
    }
}
