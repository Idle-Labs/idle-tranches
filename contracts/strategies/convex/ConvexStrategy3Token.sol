// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {ConvexBaseStrategy} from "./ConvexBaseStrategy.sol";
import {ICurveDeposit_3token} from "../../interfaces/curve/ICurveDeposit_3token.sol";
import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ConvexStrategy2Token is ConvexBaseStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;
    
    /// @notice curve N_COINS for the pool
    uint256 public constant CURVE_UNDERLYINGS_SIZE = 3;

    function _curveUnderlyingsSize() internal pure override returns(uint256) {
        return CURVE_UNDERLYINGS_SIZE;
    }

    function _curveDeposit() internal override {
        IERC20Detailed _deposit = IERC20Detailed(curveDeposit);
        uint256 _balance = _deposit.balanceOf(address(this));

        address _pool = _curvePool();

        _deposit.safeApprove(_pool, 0);
        _deposit.safeApprove(_pool, _balance);

        uint256[3] memory _depositArray;
        _depositArray[depositPosition] = _balance;

        // we can accept 0 as minimum, this will be called only by trusted roles
        uint256 _minimum = 0;
        ICurveDeposit_3token(_pool).add_liquidity(_depositArray, _minimum);
    }
}