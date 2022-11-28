// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

import "./IERC20Detailed.sol";

interface IIdleTokenFungible is IERC20Detailed {
    function token() external view returns (address);

    function tokenDecimals() external view returns (uint256);

    function tokenPrice() external view returns (uint256 price);

    function mintIdleToken(
        uint256 _amount,
        bool _skipRebalance,
        address _referral
    ) external returns (uint256 mintedTokens);

    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);

    function rebalance() external returns (bool);

    function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);

    function getAvgAPR() external view returns (uint256);

    function getAllocations() external view returns (uint256[] memory);

    function getAllAvailableTokens() external view returns (address[] memory);

    function protocolWrappers(address) external view returns (address);

    function owner() external view returns (address);

    function rebalancer() external view returns (address);

    function fee() external view returns (uint256);

    function paused() external view returns (bool);

    function setAllocations(uint256[] calldata _allocations) external;

    function setMaxUnlentPerc(uint256 _perc) external;
}
