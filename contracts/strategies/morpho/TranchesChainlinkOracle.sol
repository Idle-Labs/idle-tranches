
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IdleCDO} from "../../IdleCDO.sol";
import {IdleCDOTranche} from "../../IdleCDOTranche.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/morpho/IAggregatorV3Minimal.sol";

contract TranchesChainlinkOracle is IAggregatorV3Minimal {
  /// @notice Fixed-point scale of `discount`, 1e18 = 100%
  uint256 public constant DISCOUNT_SCALE = 1e18;

  /// @notice Thrown when the discount is greater than 100%
  error DiscountTooHigh();

  address immutable public collateralToken;
  address immutable public loanToken;
  uint256 immutable public loanTokenDecimals;
  IdleCDO immutable public cdo;
  /// @notice Discount applied to the tranche virtualPrice, scaled by DISCOUNT_SCALE (5e16 = 5%)
  uint256 immutable public discount;
  string public description = "Idle Tranches exchange rate";

  /// @notice Deploys the adapter for `_trancheToken` with a fixed, non-upgradable discount
  /// @param _trancheToken Tranche token to price
  /// @param _discount Discount applied to the virtualPrice, scaled by 1e18 (0 = no discount, 1e18 = 100%)
  constructor(address _trancheToken, uint256 _discount) {
    if (_discount > DISCOUNT_SCALE) {
      revert DiscountTooHigh();
    }
    collateralToken = _trancheToken;
    cdo = IdleCDO(IdleCDOTranche(_trancheToken).minter());
    loanToken = cdo.token();
    loanTokenDecimals = IERC20Detailed(loanToken).decimals();
    discount = _discount;
  }

  function decimals() external view returns (uint8) {
    // decimals of the virtualPrice are equal to decimals of the loanToken
    return uint8(loanTokenDecimals);
  }

  /// @notice Returns the tranche virtualPrice reduced by `discount`, in the same units as the virtualPrice.
  /// @dev Computes the exact floor without intermediate overflow for any uint256 virtualPrice.
  /// The final int256 conversion is unchanged; nonnegative answers must fit in int256.
  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    uint256 price = cdo.virtualPrice(collateralToken);
    uint256 multiplier = DISCOUNT_SCALE - discount;
    // For price = q * scale + r, floor(price * multiplier / scale) = q * multiplier + floor(r * multiplier / scale).
    // multiplier <= scale: the sum is <= price, and the remainder product is < scale^2 (1e36).
    uint256 discountedPrice = (price / DISCOUNT_SCALE) * multiplier
      + (price % DISCOUNT_SCALE) * multiplier / DISCOUNT_SCALE;
    return (0, int256(discountedPrice), 0, 0, 0);
  }
}
