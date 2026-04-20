// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../CollateralsVault.sol";

/// @notice Minimal 1inch v5 aggregation router interface.
interface IOneInchAggregationRouterV5 {
  struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address srcReceiver;
    address dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
  }

  /// @notice Executes swap.
  /// @param executor Aggregation executor address from 1inch API response.
  /// @param desc Swap description.
  /// @param data Calldata payload provided by 1inch API.
  /// @return returnAmount Amount of dstToken received.
  /// @return spentAmount Amount of srcToken spent.
  function swap(
    address executor,
    SwapDescription calldata desc,
    bytes calldata data
  ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}

/// @title OneInchLiquidationAdapter
/// @notice Adapter for CollateralsVault to liquidate collateral via 1inch Aggregation Router v5.
contract OneInchLiquidationAdapter is ILiquidationAdapter {
  using SafeERC20 for IERC20;

  address public immutable router;

  constructor(address _router) {
    router = _router;
  }

  /// @inheritdoc ILiquidationAdapter
  function liquidateCollateral(
    address collateral,
    uint256 collateralAmount,
    address borrowedToken,
    uint256 minOut,
    bytes calldata data
  ) external override returns (uint256 borrowedOut) {
    (address executor, bytes memory swapData) = abi.decode(data, (address, bytes));

    // pull collateral from caller (vault) using allowance it set
    IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralAmount);

    // approve router
    IERC20(collateral).safeApprove(router, 0);
    IERC20(collateral).safeApprove(router, collateralAmount);

    IOneInchAggregationRouterV5.SwapDescription memory desc = IOneInchAggregationRouterV5.SwapDescription({
      srcToken: IERC20(collateral),
      dstToken: IERC20(borrowedToken),
      srcReceiver: address(this),
      dstReceiver: msg.sender,
      amount: collateralAmount,
      minReturnAmount: minOut,
      flags: 0,
      permit: ""
    });

    (borrowedOut, ) = IOneInchAggregationRouterV5(router).swap(executor, desc, swapData);

    // clear approval
    IERC20(collateral).safeApprove(router, 0);

    require(borrowedOut >= minOut, "MIN_OUT");
  }
}
