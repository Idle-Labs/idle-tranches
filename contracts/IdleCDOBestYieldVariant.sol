// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./IdleCDO.sol";
import "./interfaces/IERC20Detailed.sol";

/// @title IdleCDO variant as proxy for Idle best-yield
/// @author Idle DAO, @massun-onibakuchi
contract IdleCDOBestYieldVariant is IdleCDO {
    function _additionalInit() internal override {
        delete isAYSActive; // disable yield split
    }

    /// @notice this method is pausable
    /// @dev disabling depositAA if we have non-zero totalSupply for senior tranche (AATranche).
    function _deposit(
        uint256 _amount,
        address _tranche,
        address _referral
    ) internal override returns (uint256 _minted) {
        if (AATranche == _tranche) {
            require(IERC20Detailed(_tranche).totalSupply() == 0, "disable depositAA");
        }
        _minted = super._deposit(_amount, _tranche, _referral);
    }
}
