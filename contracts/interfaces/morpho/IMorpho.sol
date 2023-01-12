// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IMorpho {
    function supply(address _poolToken, uint256 _amount) external;

    function supply(address _poolToken, address _onBehalf, uint256 _amount) external;

    /// @notice Supplies underlying tokens to a specific market, on behalf of a given user,
    ///         specifying a gas threshold at which to cut the matching engine.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasForMatching The gas threshold at which to stop the matching engine.
    function supply(address _poolToken, address _onBehalf, uint256 _amount, uint256 _maxGasForMatching) external;

    function borrow(address _poolToken, uint256 _amount) external;

    /// @notice Borrows underlying tokens from a specific market, specifying a gas threshold at which to stop the matching engine.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The gas threshold at which to stop the matching engine.
    function borrow(address _poolToken, uint256 _amount, uint256 _maxGasForMatching) external;

    function withdraw(address _poolToken, uint256 _amount) external;

    /// @notice Withdraws underlying tokens from a specific market.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    /// @param _receiver The address to send withdrawn tokens to.
    function withdraw(address _poolToken, uint256 _amount, address _receiver) external;

    function repay(address _poolToken, uint256 _amount) external;

    /// @notice Repays debt of a given user, up to the amount provided.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolToken, address _onBehalf, uint256 _amount) external;

    function claimRewards(address[] calldata _cTokenAddresses, bool _tradeForMorphoToken)
        external
        returns (uint256 claimedAmount);
}
