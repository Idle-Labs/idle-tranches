// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IIdleCDOStrategy} from "../../contracts/interfaces/IIdleCDOStrategy.sol";
import {IdleCDOPolygonZK} from "../../contracts/polygon-zk/IdleCDOPolygonZK.sol";
import {IProxyAdmin} from "../../contracts/interfaces/IProxyAdmin.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IdleClearpoolStrategyPolygonZK} from "../../contracts/polygon-zk/strategies/clearpool/IdleClearpoolStrategyPolygonZK.sol";

contract TestGenericCDOZK is Test {
  address private constant WETH = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;
  address private constant USDC = 0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
  address private constant CPOOL = 0xc3630b805F10E91c2de084Ac26C66bCD91F3D3fE;
  address private constant MATIC = 0xa2036f0538221a77A3937F1379699f44945018d0;
  address private constant USDT = 0x1E4a5963aBFD975d8c9021ce480b42188849D41d;

  struct CDOData {
    IdleCDOPolygonZK cdo;
    IIdleCDOStrategy strategy;
    address AA;
    address BB;
  }

  // @notice test tranche prices pre and post redeem
  function testPricesFasanara() external {
    address cdo = 0x8890957F80d7D771337f4ce42e15Ec40388514f1;
    _forkAndUpgrade(3520750, cdo);

    // cpfasusdc
    CDOData memory dataFasUSDC = _getCDOData(cdo);
    testPricesAndPrint(dataFasUSDC, 3000820, "AA redeem cpfasusdc");
    testPricesAndPrint(dataFasUSDC, 3000834, "BB redeem cpfasusdc");
    // testPricesAndPrint(dataFasUSDC, 3623001, "harvest cpfasusdc");
  }

  // @notice test tranche prices pre and post redeem
  function testPricesPortofino() external {
    address cdo = 0x6b8A1e78Ac707F9b0b5eB4f34B02D9af84D2b689;
    _forkAndUpgrade(2992365, cdo);

    // cpporusdt
    CDOData memory dataPorUSDT = _getCDOData(cdo);
    testPricesAndPrint(dataPorUSDT, 3000855, "AA redeem cporusdt");
    testPricesAndPrint(dataPorUSDT, 3000871, "BB redeem cporusdt");
    // testPricesAndPrint(dataPorUSDT, 3700871, "harvest cporusdt");
  }

  // @notice test tranche prices pre and post redeem
  function testHarvestPortofino() external {
    address cdo = 0x6b8A1e78Ac707F9b0b5eB4f34B02D9af84D2b689;
    uint256 blockToTest = 6347434;
    _forkAndUpgrade(blockToTest, cdo);

    // cpporusdt
    CDOData memory data = _getCDOData(cdo);
    uint256 maticBal = IERC20Detailed(MATIC).balanceOf(address(data.cdo));
    uint256 preVal = data.cdo.getContractValue();
    console.log('maticBal      ', maticBal);
    console.log('contractVal   ', preVal);

    _cdoHarvest(data.cdo, false);

    uint256 postMaticBal = IERC20Detailed(MATIC).balanceOf(address(data.cdo));
    uint256 posVal = data.cdo.getContractValue();

    console.log('postmaticBal  ', postMaticBal);
    console.log('contractValPos', posVal);
    assertApproxEqAbs(postMaticBal, 0, 1, 'All MATIC should be sold');
    assertGt(posVal, preVal, 'All MATIC sold are in the contract');
  }

  // @dev get tranches and strategy addresses and instances
  function _getCDOData(address _cdo) internal view returns (CDOData memory data) {
    IdleCDOPolygonZK cdo = IdleCDOPolygonZK(_cdo);
    IIdleCDOStrategy strategy = IIdleCDOStrategy(cdo.strategy());
    address AA = cdo.AATranche();
    address BB = cdo.BBTranche();
    data = CDOData(cdo, strategy, AA, BB);
  }

  // @dev fork at blockTest - 1, fetch prices and then fork at blockTest and fetch prices again
  // prices at the end should be == then before (or >= or at most less then before of about 1-2 wei due to rounding 
  // eg on harvests)
  function testPricesAndPrint(
    CDOData memory data,
    uint256 blockTest,
    string memory label
  ) internal {
    _forkAndUpgrade(blockTest - 1, address(data.cdo));

    console.log('########## Pre', label, ' block: ', blockTest - 1);
    uint256 preAA = data.cdo.virtualPrice(data.AA);
    uint256 preBB = data.cdo.virtualPrice(data.BB);
    uint256 preStrategy = data.strategy.price();

    console.log('tranchePriceAA', preAA);
    console.log('tranchePriceBB', preBB);
    console.log('strategyPrice ', preStrategy);
    console.log('contractVal   ', data.cdo.getContractValue());

    _forkAndUpgrade(blockTest, address(data.cdo));

    console.log('########## Pos', label, ' block: ', blockTest);
    uint256 postAA = data.cdo.virtualPrice(data.AA);
    uint256 postBB = data.cdo.virtualPrice(data.BB);
    uint256 postStrategy = data.strategy.price();

    int256 diffAA = int256(postAA) - int256(preAA);
    int256 diffBB = int256(postBB) - int256(preBB);
    int256 diffStrategy = int256(postStrategy) - int256(preStrategy);
    
    console.log('tranchePriceAA', postAA, diffAA > 0 ? 'Diff   +' : 'Diff   -', diffAA > 0 ? uint256(diffAA) : uint256(-diffAA));
    console.log('tranchePriceBB', postBB, diffBB > 0 ? 'Diff   +' : 'Diff   -', diffBB > 0 ? uint256(diffBB) : uint256(-diffBB));
    console.log('strategyPrice ', postStrategy, diffStrategy > 0 ? 'Diff   +' : 'Diff   -', diffStrategy > 0 ? uint256(diffStrategy) : uint256(-diffStrategy));
    console.log('contractVal   ', data.cdo.getContractValue());

    // price should be the same after a redeem/deposit
    assertApproxEqAbs(preAA, postAA, 2, 'AA Price not increasing');
    assertApproxEqAbs(preBB, postBB, 2, 'BB Price not increasing');
    console.log('-----------');
  }

  // @dev we do fork and upgrade in case we need to log stuff so we can use the local modified code
  function _forkAndUpgrade(
    uint256 blockTest,
    address cdo
  ) internal {
    vm.createSelectFork("polygonzk", blockTest);
    // this is needed at each create fork to keep upgrades persistent (eg console.logs)
    _upgradeContract(cdo, address(new IdleCDOPolygonZK()));
    _upgradeContract(IdleCDOPolygonZK(cdo).strategy(), address(new IdleClearpoolStrategyPolygonZK()));
  }

  // @dev upgrade the contract to the new implementation using the proxy admin for the current network
  function _upgradeContract(address proxy, address newInstance) internal {
    // Upgrade the proxy to the new contract
    IProxyAdmin admin = IProxyAdmin(0x8aA1379e46A8C1e9B7BB2160254813316b5F35B8);
    vm.prank(admin.owner());
    admin.upgrade(proxy, newInstance);
  }

  function _cdoHarvest(IdleCDOPolygonZK idleCDO, bool _skipRewards) internal virtual {
    bytes[] memory _extraPath = new bytes[](1);
    bytes memory extraData;
    bytes memory extraDataSell;
    // Quickswap is using algebra.finance and poolFees
    // are dynamic and calculated directly in their contract
    // so we simply need to pass the path without poolFee params
    _extraPath[0] = abi.encodePacked(MATIC, WETH, USDT);
    extraDataSell = abi.encode(_extraPath);

    uint256 numOfRewards = 1;
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](numOfRewards);
    uint256[] memory _minAmount = new uint256[](numOfRewards);
    uint256[] memory _sellAmounts = new uint256[](numOfRewards);
    bytes[] memory _extraData = new bytes[](2);
    if(!_skipRewards){
      _extraData[0] = extraData;
      _extraData[1] = extraDataSell;
    }
    // skip fees distribution
    _skipFlags[3] = _skipRewards;

    vm.prank(idleCDO.rebalancer());
    idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

    // linearly release all sold rewards
    vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1); 
  }
}