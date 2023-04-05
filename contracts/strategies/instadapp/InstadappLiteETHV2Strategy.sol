// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../ERC4626Strategy.sol";

contract InstadappLiteETHV2Strategy is ERC4626Strategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    address internal constant ETHV2Vault = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function initialize(address _owner) public {
        _initialize(ETHV2Vault, STETH, _owner);
    }

    /// @notice redeem the rewards
    /// @return rewards amount of reward that is deposited to the ` strategy`
    function redeemRewards(bytes calldata data)
        public
        virtual
        override
        onlyIdleCDO
        nonReentrant
        returns (uint256[] memory rewards)
    {}

    function getRewardTokens() external view returns (address[] memory rewards) {}

    function getApr() external view override returns (uint256 apr) {}
}
