// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleToken.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleTokenFungible.sol";
import "forge-std/Test.sol";
import "../../contracts/interfaces/IProxyAdmin.sol";
import "../../contracts/interfaces/euler/IEToken.sol";
import "../../contracts/interfaces/euler/IDToken.sol";
import "../../contracts/interfaces/euler/IMarkets.sol";
import "../../contracts/interfaces/euler/IEulerGeneralView.sol";
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/strategies/euler/IdleEulerStakingStrategyPSM.sol";

contract CallMeCDO is Test {
  using stdStorage for StdStorage;
  // ######## PARAMS ###################
  uint256 public blockForTest = 16578413;
  // uint256 public blockForTest = 16541740;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  // dai
  address public constant cdo = 0x264E1552Ee99f57a7D9E1bD1130a478266870C39;
  // ######## PARAMS ###################

  bytes internal extraData;
  bytes internal extraDataSell;

  function setUp() public virtual {
    _forkAt(blockForTest);
  }

  function _forkAt(uint256 _block) internal {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _block));
  }

  function _getCDOPrices(uint256 _block) internal 
    returns (uint256 aa, uint256 bb, uint256 strat) {
    console.log('##########', _block);
    if (_block != 0) {
      _forkAt(_block);
    }
    IdleCDO _cdo = IdleCDO(cdo);
    aa = _cdo.virtualPrice(_cdo.AATranche());
    bb = _cdo.virtualPrice(_cdo.BBTranche());
    strat = IIdleCDOStrategy(_cdo.strategy()).price();
    console.log('AA   ', aa);
    console.log('BB   ', bb);
    console.log('strat', strat);
  }

  function testGenericCDO() external {
    _getCDOPrices(blockForTest - 1);
    _upgradeContract(IdleCDO(cdo).strategy(), address(new IdleEulerStakingStrategyPSM()));
    console.log('pre cdo harvest');
    (uint256 aa, uint256 bb, uint256 strat) = _getCDOPrices(0);
    console.log('######### harvest');
    _cdoHarvest(IdleCDO(cdo), true);
    (uint256 aa1, uint256 bb1, uint256 strat1) = _getCDOPrices(0);
    assertGe(aa1, aa, 'AA price should increase or stay the same');
    assertGe(bb1, bb, 'BB price should increase or stay the same');
    assertGe(strat1, strat, 'Strat price should increase or stay the same');
  }

  function testGenericCDOApr() external  {
    _upgradeContract(IdleCDO(cdo).strategy(), address(new IdleEulerStakingStrategyPSM()));

    IdleCDO _cdo = IdleCDO(cdo);
    // uint256 aa = _cdo.getApr(_cdo.AATranche());
    // uint256 bb = _cdo.getApr(_cdo.BBTranche());
    uint256 strat = IIdleCDOStrategy(_cdo.strategy()).getApr();
    // console.log('AA   ', aa);
    // console.log('BB   ', bb);
    console.log('strat', strat);
    // assertGe(aa, 0, 'AA apr should be >= 0');
    // assertGe(bb, 0, 'BB apr should be >= 0');
    assertGe(strat, 0, 'Strat apr should be >= 0');
  }

  // UTILS
  function _cdoHarvest(IdleCDO _cdo, bool _skipRewards) internal {
    uint256 numOfRewards = IIdleCDOStrategy(IdleCDO(cdo).strategy()).getRewardTokens().length;
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](numOfRewards);
    uint256[] memory _minAmount = new uint256[](numOfRewards);
    uint256[] memory _sellAmounts = new uint256[](numOfRewards);
    bytes[] memory _extraData = new bytes[](2);
    if(!_skipRewards){
      _extraData[0] = extraData;
      _extraData[1] = extraDataSell;
    }
    // skip all rewards
    _skipFlags[3] = _skipRewards;

    vm.prank(_cdo.rebalancer());
    _cdo.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

    // linearly release all sold rewards
    vm.roll(block.number + _cdo.releaseBlocksPeriod() + 1); 
  }

  function _upgradeContract(address proxy, address newInstance) internal {
    // Upgrade the proxy to the new contract
    IProxyAdmin admin = IProxyAdmin(0x9438904ABC7d8944A6E2A89671fEf51C629af351);
    vm.prank(admin.owner());
    admin.upgrade(proxy, newInstance);
  }
}