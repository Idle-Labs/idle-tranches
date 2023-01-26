// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity 0.8.10;

// import "@morpho-utils/math/PercentageMath.sol";
// import "@morpho-utils/math/WadRayMath.sol";
// import "@morpho-utils/math/Math.sol";

// import "./Types.sol";

// library InterestRateModel {
//     using PercentageMath for uint256;
//     using WadRayMath for uint256;
//     using Math for uint256;

//     /// STRUCTS ///
//     struct P2PRateComputeParams {
//         uint256 poolSupplyRatePerYear; // The pool supply rate per year (in ray).
//         uint256 poolBorrowRatePerYear; // The pool borrow rate per year (in ray).
//         uint256 poolIndex; // The last stored pool index (in ray).
//         uint256 p2pIndex; // The last stored peer-to-peer index (in ray).
//         uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
//         uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
//         uint256 p2pIndexCursor; // The index cursor of the given market (in bps).
//         uint256 reserveFactor; // The reserve factor of the given market (in bps).
//     }

//     /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
//     /// @param _params The computation parameters.
//     /// @return p2pSupplyRate The peer-to-peer supply rate per year (in ray).
//     function computeP2PSupplyRatePerYear(P2PRateComputeParams memory _params)
//         internal
//         pure
//         returns (uint256 p2pSupplyRate)
//     {
//         if (_params.poolSupplyRatePerYear > _params.poolBorrowRatePerYear) {
//             p2pSupplyRate = _params.poolBorrowRatePerYear; // The p2pSupplyRate is set to the poolBorrowRatePerYear because there is no rate spread.
//         } else {
//             uint256 p2pRate = PercentageMath.weightedAvg(
//                 _params.poolSupplyRatePerYear,
//                 _params.poolBorrowRatePerYear,
//                 _params.p2pIndexCursor
//             );

//             p2pSupplyRate =
//                 p2pRate -
//                 (p2pRate - _params.poolSupplyRatePerYear).percentMul(_params.reserveFactor);
//         }

//         if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
//             uint256 shareOfTheDelta = Math.min(
//                 _params.p2pDelta.rayMul(_params.poolIndex).rayDiv(
//                     _params.p2pAmount.rayMul(_params.p2pIndex)
//                 ), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
//                 WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
//             ); // In ray.

//             p2pSupplyRate =
//                 p2pSupplyRate.rayMul(WadRayMath.RAY - shareOfTheDelta) +
//                 _params.poolSupplyRatePerYear.rayMul(shareOfTheDelta);
//         }
//     }

//   function _getMarketSupply(
//     uint256 _p2pSupplyIndex,
//     uint256 _poolSupplyIndex,
//     uint256 injectedBalance, // added variable
//     Types.Delta memory _delta
//   ) internal pure returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount) {
//       p2pSupplyAmount = _delta.p2pSupplyAmount.rayMul(_p2pSupplyIndex).zeroFloorSub(
//         _delta.p2pSupplyDelta.rayMul(_poolSupplyIndex)
//       );
//       poolSupplyAmount = injectedBalance;
//   }
  
//   function _getWeightedRate(
//     uint256 _p2pRate,
//     uint256 _poolRate,
//     uint256 _balanceInP2P,
//     uint256 _balanceOnPool
//   ) internal pure returns (uint256 weightedRate, uint256 totalBalance) {
//     totalBalance = _balanceInP2P + _balanceOnPool;
//     if (totalBalance == 0) return (weightedRate, totalBalance);

//     if (_balanceInP2P > 0) weightedRate += _p2pRate.rayMul(_balanceInP2P.rayDiv(totalBalance));
//     if (_balanceOnPool > 0)
//         weightedRate += _poolRate.rayMul(_balanceOnPool.rayDiv(totalBalance));
//   }

// }