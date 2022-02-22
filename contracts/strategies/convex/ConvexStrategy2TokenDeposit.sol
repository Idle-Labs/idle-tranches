// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ConvexBaseStrategy} from "./ConvexBaseStrategy.sol";
import {ICurveDeposit_2token} from "../../interfaces/curve/ICurveDeposit_2token.sol";
import {IERC20Detailed} from "../../interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ConvexStrategy2TokenDeposit is ConvexBaseStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice curve N_COINS for the pool
    uint256 public constant CURVE_UNDERLYINGS_SIZE = 2;

    /// @return size of the curve deposit array
    function _curveUnderlyingsSize() internal pure override returns(uint256) {
        return CURVE_UNDERLYINGS_SIZE;
    }

    /// @notice Deposits in Curve for 2 tokens
    /// @dev To implement the strategy with old curve pools like compound and y
    ///      this contract should be used with respective _underlying_ deposit contracts
    ///      See: https://curve.readthedocs.io/exchange-pools.html#id10
    function _depositInCurve(uint256 _minLpTokens) internal override {
        address _depositor = depositor;
        require(_depositor != address(0), "Depositor address is zero");

        IERC20Detailed _deposit = IERC20Detailed(curveDeposit);
        uint256 _balance = _deposit.balanceOf(address(this));        

        _deposit.safeApprove(_depositor, 0);
        _deposit.safeApprove(_depositor, _balance);

        // we can accept 0 as minimum, this will be called only by trusted roles
        uint256[2] memory _depositArray;
        _depositArray[depositPosition] = _balance;
        ICurveDeposit_2token(_depositor).add_liquidity(_depositArray, _minLpTokens);
    }
}