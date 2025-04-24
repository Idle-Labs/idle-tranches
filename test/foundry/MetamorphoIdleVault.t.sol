// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import { DeployMetamorphoVault } from "../../forge-scripts/DeployMetamorphoVault.s.sol";

import {IIdleCDOStrategy} from "../../contracts/interfaces/IIdleCDOStrategy.sol";
import {IIdleCDO} from "../../contracts/interfaces/IIdleCDO.sol";
import {IdleCDOTranche} from "../../contracts/IdleCDOTranche.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626} from "../../contracts/interfaces/IERC4626.sol";

interface IKeyringWhitelist {
  function setWhitelistStatus(address entity, bool status) external;
}

contract MetamorphoIdleVault is Test, DeployMetamorphoVault {
  // @notice test tranche prices pre and post redeem
  uint256 BLOCK = 22304039;
  string constant network = 'mainnet';
  address internal constant CDO = 0xf6223C567F21E33e859ED7A045773526E9E3c2D5;
  address internal constant KEYRING = 0x6351370a1c982780Da2D8c85DfedD421F7193Fa5;

  function setUp() public {
    vm.createSelectFork(network, BLOCK);
    vm.startPrank(TL_MULTISIG);
    IKeyringWhitelist(KEYRING).setWhitelistStatus(DEPLOYER, true);
    vm.stopPrank();

    // Give LOAN_TOKEN to deployer
    deal(LOAN_TOKEN, DEPLOYER, 100 * 1e6);
    // Deposit LOAN_TOKEN in CDO with DEPLOYER
    vm.startPrank(DEPLOYER);
    IERC20Detailed(LOAN_TOKEN).approve(CDO, type(uint256).max);
    IIdleCDO(CDO).depositAA(1e6);
    vm.stopPrank();
  }

  function testMetamorphoFactoryCreation() external {
    vm.startPrank(DEPLOYER);
    _setUpMorphoVault();
    vm.stopPrank();

    // vm.prank(TL_MULTISIG);
    // IMMVault(mmVault).acceptOwnership();
    // console.log('vault.address ', address(mmVault));
    // console.log('vault.owner   ', IMMVault(mmVault).owner());
  }
}