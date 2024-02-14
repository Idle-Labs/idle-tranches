// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IMorpho {
  struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
  }
  /// @dev Warning: `totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
  /// @dev Warning: `totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
  /// @dev Warning: `totalSupplyShares` does not contain the additional shares accrued by `feeRecipient` since the last
  /// interest accrual.
  struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
  }
  /// @dev Warning: For `feeRecipient`, `supplyShares` does not contain the accrued shares since the last interest
  /// accrual.
  struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
  }
  /// @notice The state of the position of `user` on the market corresponding to `id`.
  /// @dev Warning: For `feeRecipient`, `p.supplyShares` does not contain the accrued shares since the last interest
  /// accrual.
  function position(bytes32 id, address user) external view returns (Position memory p);
  /// @notice The state of the market corresponding to `id`.
  /// @dev Warning: `m.totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
  /// @dev Warning: `m.totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
  /// @dev Warning: `m.totalSupplyShares` does not contain the accrued shares by `feeRecipient` since the last
  /// interest accrual.
  function market(bytes32 id) external view returns (Market memory m);

  /// @notice The market params corresponding to `id`.
  /// @dev This mapping is not used in Morpho. It is there to enable reducing the cost associated to calldata on layer
  /// 2s by creating a wrapper contract with functions that take `id` as input instead of `marketParams`.
  function idToMarketParams(bytes32 id) external view returns (MarketParams memory);

  function accrueInterest(MarketParams memory marketParams) external;
}