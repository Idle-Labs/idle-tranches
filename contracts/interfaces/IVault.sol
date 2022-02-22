// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface IVault {
    function stake(uint256 _amount) external;

    function stake(address _beneficiary, uint256 _amount) external;

    function exit() external;

    function exit(uint256 _first, uint256 _last) external;

    function withdraw(uint256 _amount) external;

    function rawBalanceOf(address _account) external view returns (uint256);

    function claimRewards() external;

    function claimRewards(uint256 _first, uint256 _last) external;

    function boostDirector() external view returns (address);

    function getRewardToken() external view returns (address);
    function notifyRewardAmount(uint256 _reward) external;

    function unclaimedRewards(address _account)
        external
        view
        returns (
            uint256 amount,
            uint256 first,
            uint256 last
        );
}
