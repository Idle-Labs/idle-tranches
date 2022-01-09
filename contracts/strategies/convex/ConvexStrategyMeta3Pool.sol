
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ConvexBaseStrategy} from "./ConvexBaseStrategy.sol";
import {IDepositZap} from "../../interfaces/curve/IDepositZap.sol";
import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ConvexStrategyMeta3Pool is ConvexBaseStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice curve N_COINS for the pool
    uint256 public constant CURVE_UNDERLYINGS_SIZE = 4;
    /// @notice curve 3pool deposit zap
    address public constant CRV_3POOL_DEPOSIT_ZAP =
        address(0xA79828DF1850E8a3A3064576f380D90aECDD3359);

    /// @return size of the curve deposit array
    function _curveUnderlyingsSize() internal pure override returns (uint256) {
        return CURVE_UNDERLYINGS_SIZE;
    }

    /// @notice Deposits in Curve for metapools based on 3pool
    function _depositInCurve(uint256 _minLpTokens) internal override {
        IERC20Detailed _deposit = IERC20Detailed(curveDeposit);
        uint256 _balance = _deposit.balanceOf(address(this));

        address _pool = _curvePool(curveLpToken);

        _deposit.safeApprove(CRV_3POOL_DEPOSIT_ZAP, 0);
        _deposit.safeApprove(CRV_3POOL_DEPOSIT_ZAP, _balance);

        // we can accept 0 as minimum, this will be called only by trusted roles
        // we also use the zap to deploy funds into a meta pool
        uint256[4] memory _depositArray;
        _depositArray[depositPosition] = _balance;

        IDepositZap(CRV_3POOL_DEPOSIT_ZAP).add_liquidity(
            _pool,
            _depositArray,
            _minLpTokens
        );
    }
}