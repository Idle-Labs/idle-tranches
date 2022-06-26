// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IERC20Detailed.sol";

contract MockStakingReward is ERC20("StakedERC20Mock", "StkERC20Mock") {
    IERC20Detailed internal token;
    uint256 internal reward;

    constructor(IERC20Detailed _token) {
        token = _token;
    }

    function setTestReward(uint256 _reward) external {
        reward = _reward;
    }

    function stake(uint256 _amount) external {
        token.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external {
        _burn(msg.sender, _amount);
        token.transfer(msg.sender, _amount);
    }

    function claimRewards() external {
        token.transfer(msg.sender, reward);
    }
}
