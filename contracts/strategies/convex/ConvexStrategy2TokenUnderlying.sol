// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ConvexBaseStrategy} from "./ConvexBaseStrategy.sol";
import {ICurveDeposit_2token_underlying} from "../../interfaces/curve/ICurveDeposit_2token_underlying.sol";
import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ConvexStrategy2TokenUnderlying is ConvexBaseStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice curve N_COINS for the pool
    uint256 public constant CURVE_UNDERLYINGS_SIZE = 2;

    /// @return size of the curve deposit array
    function _curveUnderlyingsSize() internal pure override returns(uint256) {
        return CURVE_UNDERLYINGS_SIZE;
    }

    /// @notice Deposits in Curve for lending pools with 2 tokens 
    /// @dev This should be used to implement the strategy with newest curve pools like ib (Iron Bank)
    ///      See: https://curve.readthedocs.io/exchange-pools.html#id10
    function _depositInCurve(uint256 _minLpTokens) internal override {
        IERC20Detailed _deposit = IERC20Detailed(curveDeposit);
        uint256 _balance = _deposit.balanceOf(address(this));
        
        address _pool = _curvePool(curveLpToken);

        _deposit.safeApprove(_pool, 0);
        _deposit.safeApprove(_pool, _balance);

        // we can accept 0 as minimum, this will be called only by trusted roles
        // we also use only underlying because we liquidate rewards for one of the
        // underlying assetss
        uint256[2] memory _depositArray;
        _depositArray[depositPosition] = _balance;
        ICurveDeposit_2token_underlying(_pool).add_liquidity(_depositArray, _minLpTokens, true);
    }
}