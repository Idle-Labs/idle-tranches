pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IIdleCDO} from "../../contracts/interfaces/IIdleCDO.sol";
import {HypernativeBatchPauser} from "../../contracts/HypernativeBatchPauser.sol";

error NotAllowed();

contract TestHypernativeBatchPauser is Test {
  uint256 BLOCK = 124239642;
  string constant network = 'optimism'; // mainnet, polygonzk, optimism, arbitrum
  address PROT_CONTRACT_1 = 0x94e399Af25b676e7783fDcd62854221e67566b7f;
  address PROT_CONTRACT_2 = 0x8771128e9E386DC8E4663118BB11EA3DE910e528;
  address PROT_CONTRACT_3 = 0xe49174F0935F088509cca50e54024F6f8a6E08Dd;
  address PROT_CONTRACT_4 = 0x67D07aA415c8eC78cbF0074bE12254E55Ad43f3f;
  address constant TL_MULTISIG_OP = 0xFDbB4d606C199F091143BD604C85c191a526fbd0;
  address public pauser = makeAddr('pauser');
  address[] public protectedContracts;
  HypernativeBatchPauser batchPauser;

  function setUp() public {
    vm.createSelectFork(network, BLOCK);
    
    protectedContracts.push(PROT_CONTRACT_1);
    protectedContracts.push(PROT_CONTRACT_2);
    batchPauser = new HypernativeBatchPauser(pauser, protectedContracts);

    vm.startPrank(TL_MULTISIG_OP);
    IIdleCDO(PROT_CONTRACT_1).setGuardian(address(batchPauser));
    IIdleCDO(PROT_CONTRACT_2).setGuardian(address(batchPauser));
    vm.stopPrank();
  }

  function testConstructor() public view {
    assertEq(batchPauser.pauser(), pauser);
    assertEq(batchPauser.protectedContracts(0), PROT_CONTRACT_1);
    assertEq(batchPauser.protectedContracts(1), PROT_CONTRACT_2);
    assertEq(batchPauser.owner(), address(this));
  }

  function testSetPauser() public {
    address newPauser = makeAddr('newPauser');
    batchPauser.setPauser(newPauser);
    assertEq(batchPauser.pauser(), newPauser);
    
    vm.prank(makeAddr('nonOwner'));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    batchPauser.setPauser(pauser);
  }

  function testPauseAll() public {
    vm.prank(makeAddr('nonPauser'));
    vm.expectRevert(NotAllowed.selector);
    batchPauser.pauseAll();

    vm.prank(pauser);
    batchPauser.pauseAll();

    assertEq(IIdleCDO(PROT_CONTRACT_1).paused(), true, "contract 1 should be paused");
    assertEq(IIdleCDO(PROT_CONTRACT_1).allowAAWithdraw(), false, "contract 1 should have allowAAWithdraw set to false");
    assertEq(IIdleCDO(PROT_CONTRACT_1).allowBBWithdraw(), false, "contract 1 should have allowBBWithdraw set to false");

    assertEq(IIdleCDO(PROT_CONTRACT_2).paused(), true, "contract 2 should be paused");
    assertEq(IIdleCDO(PROT_CONTRACT_2).allowAAWithdraw(), false, "contract 2 should have allowAAWithdraw set to false");
    assertEq(IIdleCDO(PROT_CONTRACT_2).allowBBWithdraw(), false, "contract 2 should have allowBBWithdraw set to false");
  }

  function testReplaceProtectedContracts() public {
    address[] memory newProtectedContracts = new address[](2);
    newProtectedContracts[0] = PROT_CONTRACT_3;
    newProtectedContracts[1] = PROT_CONTRACT_4;
    batchPauser.replaceProtectedContracts(newProtectedContracts);

    assertEq(batchPauser.protectedContracts(0), newProtectedContracts[0]);
    assertEq(batchPauser.protectedContracts(1), newProtectedContracts[1]);

    vm.prank(makeAddr('nonOwner'));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    batchPauser.replaceProtectedContracts(protectedContracts);
  }

  function testAddProtectedContracts() public {
    address[] memory newProtectedContracts = new address[](2);
    newProtectedContracts[0] = PROT_CONTRACT_3;
    newProtectedContracts[1] = PROT_CONTRACT_4;
    batchPauser.addProtectedContracts(newProtectedContracts);

    assertEq(batchPauser.protectedContracts(0), PROT_CONTRACT_1);
    assertEq(batchPauser.protectedContracts(1), PROT_CONTRACT_2);
    assertEq(batchPauser.protectedContracts(2), newProtectedContracts[0]);
    assertEq(batchPauser.protectedContracts(3), newProtectedContracts[1]);

    vm.prank(makeAddr('nonOwner'));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    batchPauser.addProtectedContracts(protectedContracts);
  }
}