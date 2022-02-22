
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ConvexBaseStrategy} from "./ConvexBaseStrategy.sol";
import {IDepositZap} from "../../interfaces/curve/IDepositZap.sol";
import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ConvexStrategyMUSD is ConvexBaseStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice curve N_COINS for the pool
    uint256 public constant CURVE_UNDERLYINGS_SIZE = 4;
    /// @notice curve 3pool deposit zap
    address public constant CURVE_MUSD_DEPOSIT =
        address(0x803A2B40c5a9BB2B86DD630B274Fa2A9202874C2);

    /// @return size of the curve deposit array
    function _curveUnderlyingsSize() internal pure override returns (uint256) {
        return CURVE_UNDERLYINGS_SIZE;
    }

    /// @notice Deposits in Curve for metapools based on 3pool
    function _depositInCurve(uint256 _minLpTokens) internal override {
        IERC20Detailed _deposit = IERC20Detailed(curveDeposit);
        uint256 _balance = _deposit.balanceOf(address(this));

        _deposit.safeApprove(CURVE_MUSD_DEPOSIT, 0);
        _deposit.safeApprove(CURVE_MUSD_DEPOSIT, _balance);

        uint256[4] memory _depositArray;
        _depositArray[depositPosition] = _balance;
        IDepositZap(CURVE_MUSD_DEPOSIT).add_liquidity(_depositArray, _minLpTokens);
    }
}