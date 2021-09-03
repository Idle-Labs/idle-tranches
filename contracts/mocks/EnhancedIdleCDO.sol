// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "../IdleCDO.sol";

contract EnhancedIdleCDO is IdleCDO {
  function setUniRouterForTest(address a) external {
    uniswapRouterV2 = IUniswapV2Router02(a);
  }
  function setWethForTest(address a) external {
    weth = a;
  }
  function updateAccountingForTest() external {
    _updateAccounting();
  }
  function claimStkAave() external {
    _claimStkAave();
  }
  function harvestedRewardsPublic() external view returns (uint256) {
    return harvestedRewards;
  }
  function latestHarvestBlockPublic() external view returns (uint256) {
    return latestHarvestBlock;
  }
}
