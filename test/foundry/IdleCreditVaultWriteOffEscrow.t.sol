pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {IdleCreditVault} from "../../contracts/strategies/idle/IdleCreditVault.sol";
import {IdleCDOEpochVariant} from "../../contracts/IdleCDOEpochVariant.sol";
import {IdleCreditVaultWriteOffEscrow} from "../../contracts/IdleCreditVaultWriteOffEscrow.sol";
import {IKeyring} from "../../contracts/interfaces/keyring/IKeyring.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";

error NotAllowed();
error EpochNotRunning();
error Is0();

contract TestIdleCreditVaultWriteOffEscrow is Test {
  using stdStorage for StdStorage;

  uint256 public constant ONE_TRANCHE = 1e18;
  uint256 public constant ONE_TOKEN = 1e6; // vault uses USDC with 6 decimals
  IdleCDOEpochVariant public constant cdoEpoch = IdleCDOEpochVariant(0xf6223C567F21E33e859ED7A045773526E9E3c2D5);
  IdleCreditVaultWriteOffEscrow public escrow;
  IERC20Detailed public underlying;
  IERC20Detailed public tranche;
  IdleCreditVault public strategy;
  address public manager;
  address public borrower;
  // LP address
  address public constant LP = 0xA7780086ab732C110E9E71950B9Fb3cb2ea50D89;
  address public constant FASA = 0x7545CdbccD780DabAd6AdA8279D82E5ccfd4bF88;
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

  function setUp() public {
    vm.createSelectFork('mainnet', 23032567);

    // we deploy a new IdleCDOEpochVariant and IdleCreditVault contract used only to get the bytecode 
    // and etch at the same address of the original one so to enable console.log in the IdleCDOEpochVariant 
    // and new features not yet deployed on mainnet
    IdleCDOEpochVariant dummy = new IdleCDOEpochVariant();
    IdleCreditVault dummyStrategy = new IdleCreditVault();
    vm.etch(address(cdoEpoch), address(dummy).code);
    vm.etch(cdoEpoch.strategy(), address(dummyStrategy).code);

    escrow = new IdleCreditVaultWriteOffEscrow();
    // allow initialization of the escrow contract
    vm.store(address(escrow), bytes32(uint256(0)), bytes32(uint256(0)));
    escrow.initialize(address(cdoEpoch), TL_MULTISIG, true);

    underlying = IERC20Detailed(cdoEpoch.token());
    strategy = IdleCreditVault(cdoEpoch.strategy());
    manager = strategy.manager();
    borrower = strategy.borrower();
    tranche = IERC20Detailed(cdoEpoch.AATranche());

    // approve escrow contract to spend tranches tokens of address(this)
    tranche.approve(address(escrow), type(uint256).max);

    // allow everyone to deposit
    vm.prank(cdoEpoch.owner());
    cdoEpoch.setKeyringParams(address(0), 1, false);

    vm.prank(LP);
    tranche.approve(address(escrow), type(uint256).max);
  }

  function testInitialize() public view {
    assertEq(escrow.idleCDOEpoch(), address(cdoEpoch));
    assertEq(escrow.strategy(), cdoEpoch.strategy());
    assertEq(escrow.underlying(), cdoEpoch.token());
    assertEq(escrow.tranche(), cdoEpoch.AATranche());
    assertEq(escrow.owner(), TL_MULTISIG);
    assertEq(escrow.borrower(), borrower);
    assertEq(escrow.exitFee(), 100);
    assertEq(escrow.feeReceiver(), TL_MULTISIG);
  }

  function testCantReinitialize() public {
    vm.expectRevert('Initializable: contract is already initialized');
    escrow.initialize(address(cdoEpoch), address(this), true);
  }

  function testOnlyKeyringUsersCanInteract() external {
    address keyring = address(1);

    vm.prank(cdoEpoch.owner());
    cdoEpoch.setKeyringParams(keyring, 1, false);

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(false)
    );

    // try with this contract
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    escrow.createWriteOffRequest(1e18, 1e6);
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    escrow.deleteWriteOffRequest();
    vm.clearMockedCalls();

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );

    // epoch is already running at specified block
    vm.startPrank(LP);
    escrow.createWriteOffRequest(1e18, 1e6);
    escrow.deleteWriteOffRequest();
    vm.stopPrank();

    vm.clearMockedCalls();
  }

  function testCreateWriteOffRequest() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    escrow.createWriteOffRequest(0, 1e6);

    uint256 trancheBalancePre = tranche.balanceOf(LP);
    vm.prank(LP);
    escrow.createWriteOffRequest(10000e18, 10000e6); // 10k tranche tokens and 10k USDC requested
    uint256 trancheBalancePost = tranche.balanceOf(LP);
    assertEq(trancheBalancePre - trancheBalancePost, 10000e18, 'tranche balance of LP is wrong after write-off request');
    (uint256 tranches, uint256 underlyings) = escrow.userRequests(LP);
    assertEq(tranches, 10000e18, 'write-off request tranches is wrong');
    assertEq(underlyings, 10000e6, 'write-off request underlyings is wrong');

    // create another request
    vm.prank(LP);
    escrow.createWriteOffRequest(10000e18, 10000e6);
    (tranches, underlyings) = escrow.userRequests(LP);
    assertEq(tranches, 20000e18, 'write-off request tranches is wrong after second request');
    assertEq(underlyings, 20000e6, 'write-off request underlyings is wrong after second request');

    _stopCurrentEpoch();
    vm.expectRevert(abi.encodeWithSelector(EpochNotRunning.selector));
    escrow.createWriteOffRequest(0, 1e6);
  }

  function testDeleteWriteOffRequest() external {
    vm.expectRevert(abi.encodeWithSelector(Is0.selector));
    escrow.deleteWriteOffRequest();

    vm.startPrank(LP);
    escrow.createWriteOffRequest(10000e18, 10000e6);
    uint256 trancheBalancePre = tranche.balanceOf(LP);
    escrow.deleteWriteOffRequest();
    uint256 trancheBalancePost = tranche.balanceOf(LP);
    vm.stopPrank();

    (uint256 tranches, uint256 underlyings) = escrow.userRequests(LP);
    assertEq(tranches, 0, 'write-off request tranches is not 0 after delete');
    assertEq(underlyings, 0, 'write-off request underlyings is not 0 after delete');

    assertEq(trancheBalancePost, trancheBalancePre + 10000e18, 'tranche balance of LP is wrong after delete request');
  }

  function testFullfillWriteOffRequest() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    escrow.fullfillWriteOffRequest(LP);

    deal(address(underlying), borrower, 10000e6);

    vm.startPrank(borrower);
    vm.expectRevert(abi.encodeWithSelector(Is0.selector));
    escrow.fullfillWriteOffRequest(LP);
    vm.stopPrank();

    vm.prank(LP);
    escrow.createWriteOffRequest(10000e18, 10000e6);

    uint256 balPreBorrower = underlying.balanceOf(borrower);
    uint256 balPreBorrowerTranche = tranche.balanceOf(borrower);
    uint256 balPreLP = underlying.balanceOf(LP);
    uint256 balPreFeeReceiver = underlying.balanceOf(TL_MULTISIG);

    vm.startPrank(borrower);
    underlying.approve(address(escrow), 10000e6);
    escrow.fullfillWriteOffRequest(LP);
    vm.stopPrank();

    (uint256 tranches, uint256 underlyings) = escrow.userRequests(LP);
    assertEq(tranches, 0, 'write-off request tranches is not 0 after fulfill');
    assertEq(underlyings, 0, 'write-off request underlyings is not 0 after fulfill');

    uint256 fee = 10e6;
    assertEq(balPreBorrower - underlying.balanceOf(borrower), 10000e6, 'borrower balance is wrong after fulfill');
    assertEq(underlying.balanceOf(LP) - balPreLP, 10000e6 - fee, 'LP balance is wrong after fulfill');
    assertEq(tranche.balanceOf(borrower) - balPreBorrowerTranche, 10000e18, 'borrower tranche balance is wrong after fulfill');
    assertEq(underlying.balanceOf(TL_MULTISIG) - balPreFeeReceiver, fee, 'fee receiver balance is wrong after fulfill');
  }

  function testSetExitFee() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    escrow.setExitFee(100);

    vm.startPrank(TL_MULTISIG);
    escrow.setExitFee(1000);
    vm.stopPrank();

    assertEq(escrow.exitFee(), 1000, 'exit fee is not 1000');
  }

  function testEmergencyWithdraw() external {
    vm.expectRevert(abi.encodeWithSelector(NotAllowed.selector));
    escrow.emergencyWithdraw(address(underlying), TL_MULTISIG, 1);

    deal(address(underlying), address(escrow), 100e6);

    uint256 balPre = underlying.balanceOf(TL_MULTISIG);
    vm.startPrank(TL_MULTISIG);
    escrow.emergencyWithdraw(address(underlying), TL_MULTISIG, 100e6);
    vm.stopPrank();

    uint256 balPost = underlying.balanceOf(TL_MULTISIG);
    assertEq(balPost - balPre, 100e6, 'TL_MULTISIG balance is not correct after emergency withdraw');
  }

  function _stopCurrentEpoch() internal {
    _stopCurrentEpochWithApr(0);
  }

  function _stopCurrentEpochWithApr(uint256 _apr) internal {
    uint256 interest = 1000 * 1e6; // 1000 USDC
    uint256 pendingWithdraw = strategy.pendingWithdraws();

    uint256 toRepay = _apr == 0 ? interest + pendingWithdraw : _expectedFundsEndEpoch();

    deal(address(underlying), borrower, toRepay);
    vm.prank(borrower);
    underlying.approve(address(cdoEpoch), toRepay);

    vm.warp(cdoEpoch.epochEndDate() + 1);
    vm.prank(cdoEpoch.owner());
    if (_apr == 0) {
      cdoEpoch.stopEpoch(0, interest);
    } else {
      cdoEpoch.stopEpoch(_apr, 0);
    }

    assertEq(cdoEpoch.defaulted(), false, 'pool should not be defaulted');
  }

  function _expectedFundsEndEpoch() internal view returns (uint256 expected) {
    expected = cdoEpoch.expectedEpochInterest() + IdleCreditVault(address(strategy)).pendingWithdraws();
  }
}