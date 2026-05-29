// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

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

    price = cdo.virtualPrice(_tranche);
    if (!cdo.isEpochRunning() || cdo.defaulted()) return price;

    uint256 accruedGain = _accruedGain(cdo);
    if (accruedGain == 0) return price;

    uint256 trancheGain = _trancheGain(cdo, accruedGain, isAATranche);
    uint256 impliedNav = trancheSupply * price / ONE_TRANCHE_TOKEN + trancheGain;
    return impliedNav * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  function _isAATranche(IdleCDOEpochVariant cdo, address _tranche) private view returns (bool) {
    address aaTranche = cdo.AATranche();
    if (_tranche == aaTranche) return true;
    if (_tranche != cdo.BBTranche()) revert InvalidTranche();
    return false;
  }

  function _accruedGain(IdleCDOEpochVariant cdo) private view returns (uint256 accruedGain) {
    uint256 duration = cdo.epochDuration();
    uint256 endDate = cdo.epochEndDate();
    uint256 startDate = endDate > duration ? endDate - duration : 0;
    if (duration == 0 || block.timestamp <= startDate) return 0;

    uint256 elapsed = block.timestamp >= endDate ? duration : block.timestamp - startDate;
    bool isProgrammable = cdo.isProgrammableBorrower();
    uint256 expectedInterest = isProgrammable ? _programmableBorrowerInterest(cdo) : cdo.expectedEpochInterest();
    uint256 pendingFees = cdo.pendingWithdrawFees();
    if (elapsed == 0 || expectedInterest <= pendingFees) return 0;

    accruedGain = expectedInterest - pendingFees;
    if (!isProgrammable) accruedGain = accruedGain * elapsed / duration;
    uint256 mgmtFee = cdo.managementFee();
    if (mgmtFee != 0) {
      // Match stop accounting: management fees reduce gains before performance fees.
      uint256 accruedManagementFee = cdo.getContractValue() * mgmtFee * elapsed / (FULL_ALLOC * 365 days);
      if (accruedManagementFee >= accruedGain) return 0;
      accruedGain -= accruedManagementFee;
    }
    accruedGain -= accruedGain * cdo.fee() / FULL_ALLOC;
  }

  /// @notice Current net epoch interest due from a programmable borrower.
  /// @dev The borrower returns interest accrued to now, so callers must not prorate it again.
  function _programmableBorrowerInterest(IdleCDOEpochVariant cdo) private view returns (uint256) {
    address borrower = IdleCreditVault(cdo.strategy()).borrower();
    return IProgrammableBorrower(borrower).totalInterestDueNow();
  }

  function _trancheGain(
    IdleCDOEpochVariant cdo,
    uint256 accruedGain,
    bool isAATranche
  ) private view returns (uint256 trancheGain) {
    address aaTranche = cdo.AATranche();
    address bbTranche = cdo.BBTranche();
    uint256 splitRatio = cdo.trancheAPRSplitRatio();
    if (IdleCDOTranche(isAATranche ? bbTranche : aaTranche).totalSupply() == 0) {
      trancheGain = accruedGain;
    } else if (isAATranche) {
      // Match IdleCDO's precision behavior: BB is rounded first, dust favors AA.
      uint256 bbGain = accruedGain * (FULL_ALLOC - splitRatio) / FULL_ALLOC;
      trancheGain = accruedGain - bbGain;
    } else {
      trancheGain = accruedGain * (FULL_ALLOC - splitRatio) / FULL_ALLOC;
    }
  }
}
