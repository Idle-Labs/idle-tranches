// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {IProgrammableBorrower} from "./interfaces/IProgrammableBorrower.sol";
import {IdleCDOEpochVariant} from "./IdleCDOEpochVariant.sol";
import {IdleCDOTranche} from "./IdleCDOTranche.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

error InvalidTranche();

/// @notice Stateless helper for the current implied Credit Vault tranche price during an epoch.
contract IdleCreditVaultImpliedPrice {
  uint256 private constant FULL_ALLOC = 100_000;
  uint256 private constant ONE_TRANCHE_TOKEN = 1e18;

  /// @notice Current implied virtual price for a Credit Vault tranche token.
  /// @dev During an epoch this linearly accrues expected epoch interest net of fees up to epochEndDate.
  /// Outside running epochs it returns the vault virtualPrice.
  /// @param _tranche AA or BB tranche token address.
  /// @return price Current implied tranche price, scaled like IdleCDO.virtualPrice.
  function impliedVirtualPrice(address _tranche) external view returns (uint256 price) {
    IdleCDOTranche tranche = IdleCDOTranche(_tranche);
    IdleCDOEpochVariant cdo = IdleCDOEpochVariant(tranche.minter());
    bool isAATranche = _isAATranche(cdo, _tranche);

    uint256 trancheSupply = tranche.totalSupply();
    if (trancheSupply == 0) return cdo.oneToken();

    if (!cdo.isEpochRunning() || cdo.defaulted()) return cdo.virtualPrice(_tranche);

    uint256 strategyBalance = IERC20Detailed(cdo.strategyToken()).balanceOf(address(cdo));
    uint256 unpaidFees = cdo.unclaimedFees();
    uint256 managedNav = strategyBalance > unpaidFees ? strategyBalance - unpaidFees : 0;
    uint256 elapsedFee = managedNav * cdo.managementFee() * (block.timestamp - cdo.latestHarvestBlock()) / (FULL_ALLOC * 365 days);
    uint256 projectedAssets = managedNav + _accruedGain(cdo);
    if (elapsedFee >= projectedAssets) return 0;
    price = _projectedNAV(cdo, isAATranche, projectedAssets - elapsedFee, cdo.pendingManagementFees() + elapsedFee) * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  function _isAATranche(IdleCDOEpochVariant cdo, address _tranche) private view returns (bool) {
    address aaTranche = cdo.AATranche();
    if (_tranche == aaTranche) return true;
    if (_tranche != cdo.BBTranche()) revert InvalidTranche();
    return false;
  }

  /// @notice Accrue gross active interest before the accounting helper allocates fees.
  /// @param cdo Epoch vault whose current expected interest is being projected.
  /// @return accruedGain Gross active interest earned through the current time.
  function _accruedGain(IdleCDOEpochVariant cdo) private view returns (uint256 accruedGain) {
    uint256 duration = cdo.epochDuration();
    uint256 endDate = cdo.epochEndDate();
    uint256 startDate = endDate > duration ? endDate - duration : 0;
    if (duration == 0 || block.timestamp <= startDate) return 0;

    uint256 elapsed = block.timestamp >= endDate ? duration : block.timestamp - startDate;
    if (cdo.isProgrammableBorrower()) return _programmableBorrowerInterest(cdo);
    uint256 expectedInterest = cdo.expectedEpochInterest();
    uint256 pendingFees = cdo.pendingWithdrawFees();
    if (elapsed == 0 || expectedInterest <= pendingFees) return 0;

    accruedGain = expectedInterest - pendingFees;
    accruedGain = accruedGain * elapsed / duration;
  }

  /// @notice Current realized interest attributable to active LPs in programmable mode.
  /// @dev Raw interest excludes fee principal and is already accrued; only remove the APR0 receipt share.
  function _programmableBorrowerInterest(IdleCDOEpochVariant cdo) private view returns (uint256 interest) {
    IdleCreditVault strategy = IdleCreditVault(cdo.strategy());
    interest = IProgrammableBorrower(strategy.borrower()).totalInterestDueNow();
    uint256 principal = strategy.apr0TotalPrincipal();
    if (principal != 0) interest -= interest * principal / (cdo.getContractValue() + principal);
  }

  /// @notice Project settlement NAV using the CDO's yield, fee and credit-loss allocation rules.
  /// @param cdo Vault whose saved NAV is the projection's starting point.
  /// @param senior Whether the requested tranche is AA.
  /// @param nav Total net assets including accrued interest and management expenses.
  /// @param managementFees Accrued management expenses not yet reflected in saved NAV.
  /// @return Projected tranche NAV in underlying units.
  function _projectedNAV(IdleCDOEpochVariant cdo, bool senior, uint256 nav, uint256 managementFees) private view returns (uint256) {
    uint256 aaNav = cdo.lastNAVAA();
    uint256 bbNav = cdo.lastNAVBB();
    uint256 savedNav = aaNav + bbNav;
    if (savedNav == 0) return 0;
    int256 gain = int256(nav) - int256(savedNav);
    if (gain > 0) gain -= gain * int256(cdo.fee()) / int256(FULL_ALLOC);
    gain += int256(managementFees);
    uint256 bbFee = managementFees * bbNav / savedNav;
    int256 bbGain;
    if (bbNav != 0) {
      if (aaNav == 0) {
        bbGain = gain;
      } else if (gain > 0) {
        bbGain = gain * int256(FULL_ALLOC - cdo.trancheAPRSplitRatio()) / int256(FULL_ALLOC);
      } else {
        int256 maxLoss = -int256(bbNav - bbFee);
        bbGain = gain > maxLoss ? gain : maxLoss;
      }
    }
    return senior ? uint256(int256(aaNav) + gain - bbGain - int256(managementFees - bbFee)) : uint256(int256(bbNav) + bbGain - int256(bbFee));
  }

}
