// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IEToken is IERC20 {
      function name() external view returns(string memory);
  function symbol() external view returns(string memory);
  function decimals() external view returns(uint256);
    /// @notice Transfer underlying tokens from sender to the Euler pool, and increase account's eTokens
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param amount In underlying units (use max uint256 for full underlying token balance)
    function deposit(uint subAccountId, uint amount) external;
    
    /// @notice Transfer underlying tokens from Euler pool to sender, and decrease account's eTokens
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param amount In underlying units (use max uint256 for full pool balance)
    function withdraw(uint subAccountId, uint amount) external;

    /// @notice Balance of a particular account, in underlying units (increases as interest is earned)
    function balanceOfUnderlying(address account) external view returns (uint);

    /// @notice Convert an eToken balance to an underlying amount, taking into account current exchange rate
    /// @param balance eToken balance, in internal book-keeping units (18 decimals)
    /// @return Amount in underlying units, (same decimals as underlying token)
    function convertBalanceToUnderlying(uint balance) external view returns (uint);
    
    /// @notice Convert an underlying amount to an eToken balance, taking into account current exchange rate
    /// @param underlyingAmount Amount in underlying units (same decimals as underlying token)
    /// @return eToken balance, in internal book-keeping units (18 decimals)
    function convertUnderlyingToBalance(uint underlyingAmount) external view returns (uint);

    /// @notice Sum of all balances, in underlying units (increases as interest is earned)
    function totalSupplyUnderlying() external view returns (uint);
}