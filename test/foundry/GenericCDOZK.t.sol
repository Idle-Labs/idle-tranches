// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IIdleCDOStrategy} from "../../contracts/interfaces/IIdleCDOStrategy.sol";
import {IdleCDOPolygonZK} from "../../contracts/polygon-zk/IdleCDOPolygonZK.sol";
import {IProxyAdmin} from "../../contracts/interfaces/IProxyAdmin.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

contract TestGenericCDOZK is Test {
  struct CDOData {
    IdleCDOPolygonZK cdo;
    IIdleCDOStrategy strategy;
    address AA;
    address BB;
  }

  // @notice test tranche prices pre and post redeem
  function testPricesFasanara() external {
    address cdo = 0x8890957F80d7D771337f4ce42e15Ec40388514f1;
    _forkAndUpgrade(2992365, cdo);

    // cpfasusdc
    CDOData memory dataFasUSDC = _getCDOData(cdo);
    testPricesAndPrint(dataFasUSDC, 3000820, "AA redeem cpfasusdc");
    testPricesAndPrint(dataFasUSDC, 3000834, "BB redeem cpfasusdc");
  }

  // @notice test tranche prices pre and post redeem
  function testPricesPortofino() external {
    address cdo = 0x6b8A1e78Ac707F9b0b5eB4f34B02D9af84D2b689;
    _forkAndUpgrade(2992365, cdo);

    // cpporusdt
    CDOData memory dataPorUSDT = _getCDOData(cdo);
    testPricesAndPrint(dataPorUSDT, 3000855, "AA redeem cporusdt");
    testPricesAndPrint(dataPorUSDT, 3000871, "BB redeem cporusdt");
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
    console.log('contractVal', data.cdo.getContractValue());

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
    console.log('contractVal', data.cdo.getContractValue());

    // price should be the same after a redeem/deposit
    assertApproxEqAbs(preAA, postAA, 1, 'AA Price not increasing');
    assertApproxEqAbs(preBB, postBB, 1, 'BB Price not increasing');
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
  }

  // @dev upgrade the contract to the new implementation using the proxy admin for the current network
  function _upgradeContract(address proxy, address newInstance) internal {
    // Upgrade the proxy to the new contract
    IProxyAdmin admin = IProxyAdmin(0x8aA1379e46A8C1e9B7BB2160254813316b5F35B8);
    vm.prank(admin.owner());
    admin.upgrade(proxy, newInstance);
  }
}