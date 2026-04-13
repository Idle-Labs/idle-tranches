// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

/// @notice Hook surface exposed by programmable borrowers used by `IdleCDOEpochVariant`.
interface IProgrammableBorrower {
  /// @notice Sync borrower-side accounting when a new epoch starts.
  /// @param _pendingWithdraws Underlyings reserved for withdraw requests at epoch end.
  function onStartEpoch(uint256 _pendingWithdraws) external;

  /// @notice Free enough liquidity so IdleCDO can pull stop-epoch funds.
  /// @param _amountRequired Total underlyings IdleCDO will transfer from the borrower.
  function onStopEpoch(uint256 _amountRequired) external;

  /// @notice Return the total net interest currently due for the running epoch.
  /// @dev This is the pool-facing stop-epoch value: borrower contractual interest plus positive
  /// vault PnL minus vault losses.
  /// @return Interest amount owed right now.
  function totalInterestDueNow() external view returns (uint256);

  /// @notice Move accrued borrower interest into settled debt.
  /// @dev Called only on success path after IdleCDO fronted the interest. This settles the full
  /// contractual borrower-interest sleeve, independently from vault gains or losses.
  function settleBorrowerInterest() external;

  /// @notice Abort active epoch accounting after IdleCDO has defaulted the facility.
  /// @dev Used only on the default path when `onStopEpoch` could not complete successfully.
  function onDefault() external;
}
