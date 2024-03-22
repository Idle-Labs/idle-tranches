
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IdleCDO} from "../../IdleCDO.sol";
import {IdleCDOTranche} from "../../IdleCDOTranche.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/morpho/IAggregatorV3Minimal.sol";

contract TranchesChainlinkOracle is IAggregatorV3Minimal {
  address immutable public collateralToken;
  address immutable public loanToken;
  uint256 immutable public loanTokenDecimals;
  IdleCDO immutable public cdo;
  string public description = "Idle Tranches exchange rate";

  constructor(address _trancheToken) {
    collateralToken = _trancheToken;
    cdo = IdleCDO(IdleCDOTranche(_trancheToken).minter());
    loanToken = cdo.token();
    loanTokenDecimals = IERC20Detailed(loanToken).decimals();
  }

  function decimals() external view returns (uint8) {
    // decimals of the virtualPrice are equal to decimals of the loanToken
    return uint8(loanTokenDecimals);
  }

  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (0, int256(cdo.virtualPrice(collateralToken)), 0, 0, 0);
  }
}