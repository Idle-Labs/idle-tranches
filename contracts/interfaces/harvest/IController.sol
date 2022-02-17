// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IHarvestController {
    event SharePriceChangeLog(
        address indexed vault,
        address indexed strategy,
        uint256 oldSharePrice,
        uint256 newSharePrice,
        uint256 timestamp
    );

    function greyList(address _target) external view returns (bool);

    function addVaultAndStrategy(address _vault, address _strategy) external;

    /// @notice claim the reward tokens
    function doHardWork(address _vault) external;

    function salvage(address _token, uint256 amount) external;

    function salvageStrategy(
        address _strategy,
        address _token,
        uint256 amount
    ) external;

    function notifyFee(address _underlying, uint256 fee) external;

    function profitSharingNumerator() external view returns (uint256);

    function profitSharingDenominator() external view returns (uint256);

    function feeRewardForwarder() external view returns (address);

    function setFeeRewardForwarder(address _value) external;

    function addHardWorker(address _worker) external;

    function addMultipleToWhitelist(address[] memory _targets) external;
}
