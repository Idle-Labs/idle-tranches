// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IDepositZap} from "../../interfaces/curve/IDepositZap.sol";
import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import {ICurveDeposit_4token} from "../../interfaces/curve/ICurveDeposit_4token.sol";
import {ConvexFactoryMetaPoolStrategy} from "./ConvexFactoryMetaPoolStrategy.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ConvexStrategyMetaBTC is ConvexFactoryMetaPoolStrategy {
    using SafeERC20 for IERC20Detailed;

    /// @notice curve N_COINS for the pool
    uint256 public constant CURVE_UNDERLYINGS_SIZE = 4;
    /// @notice curve sBTC deposit zap
    address public constant META_BTC_DEPOSIT_ZAP =
        address(0x7AbDBAf29929e7F8621B757D2a7c04d78d633834);

    /// @return size of the curve deposit array
    function _curveUnderlyingsSize() internal pure override returns (uint256) {
        return CURVE_UNDERLYINGS_SIZE;
    }

    /// @notice Deposits in Curve for metapools based on sbtc
    function _depositInCurve(uint256 _minLpTokens) internal override {
        IERC20Detailed _deposit = IERC20Detailed(curveDeposit);
        uint256 _balance = _deposit.balanceOf(address(this));
        address _pool = curveLpToken;

        _deposit.safeApprove(META_BTC_DEPOSIT_ZAP, 0);
        _deposit.safeApprove(META_BTC_DEPOSIT_ZAP, _balance);

        // we can accept 0 as minimum, this will be called only by trusted roles
        // we also use the zap to deploy funds into a meta pool
        uint256[4] memory _depositArray;
        _depositArray[depositPosition] = _balance;

        IDepositZap(META_BTC_DEPOSIT_ZAP).add_liquidity(
            _pool,
            _depositArray,
            _minLpTokens
        );
    }
}
