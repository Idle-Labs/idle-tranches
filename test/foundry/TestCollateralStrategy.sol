// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../contracts/strategies/BaseCollateralStrategy.sol";

import "../../contracts/modules/MorphoBorrowModule.sol";
import "../../contracts/modules/EulerDepositModule.sol";

import "forge-std/Test.sol";

contract TestCollateralStrategy is BaseCollateralStrategy, EulerDepositModule, MorphoBorrowModule {
    function getDebtToBorrow(address collateralAsset, uint256 _collateralAdded) public override returns (uint256) {}

    // /// @dev makes the actual deposit into the `strategy`
    // /// @param _amount amount of tokens to deposit
    // function _depositCollateral(address _token, uint256 _amount) internal override returns (uint256 _collateralAdded) {}

    // function _borrowAsset(address _token, uint256 _debts)
    //     internal
    //     override(MorphoBorrowModule, BaseCollateralStrategy)
    //     returns (uint256 _debtsAdded)
    // {
    //     return MorphoBorrowModule._borrowAsset(_token, _debts);
    // }

    // function _repayAsset(address _token, uint256 _debts)
    //     internal
    //     override(MorphoBorrowModule, BaseCollateralStrategy)
    //     returns (uint256)
    // {
    //     return MorphoBorrowModule._repayAsset(_token, _debts);
    // }

    function _swapForAsset(address _token, uint256 _amountIn) internal override returns (uint256 _amountOut) {}

    function _depositAsset(address _token, uint256 _assets) internal override returns (uint256 _assetsDeposited) {}

    function getApr() external view override returns (uint256) {}

    function getRewardTokens() external view override returns (address[] memory) {}
}
