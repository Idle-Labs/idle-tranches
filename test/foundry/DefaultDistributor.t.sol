// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/DefaultDistributor.sol";
import "../../contracts/IdleCDOTranche.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "forge-std/Test.sol";

// @notice contract used to test the update of lido PYT to the new 
// IdleCDO implementation with the adaptive yield split strategy and referrals
contract TestDefaultDistributor is Test {
  using stdStorage for StdStorage;

  uint256 internal constant ONE_TRANCHE = 1e18;
  uint256 internal constant MAINNET_CHIANID = 1;
  DefaultDistributor internal distributor;
  // USDC, 6 decimals
  IERC20Detailed internal underlying = IERC20Detailed(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IERC20Detailed internal tranche;

  function setUp() public {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16527983));

    tranche = IERC20Detailed(address(new IdleCDOTranche('tranche', 'AA')));
    // label
    vm.label(address(tranche), "AAtranche");
    vm.label(address(underlying), "underlying");
  }

  function testConstructor() external {
    IdleCDOTranche(address(tranche)).mint(address(1), 1e18);
    address _owner = address(2);
    distributor = new DefaultDistributor(address(underlying), address(tranche), _owner);

    assertEq(distributor.token(), address(underlying));
    assertEq(distributor.trancheToken(), address(tranche));
    assertEq(distributor.owner(), _owner);
  }

  function testOnlyOwner() public {
    distributor = new DefaultDistributor(address(underlying), address(tranche), address(this));
    IdleCDOTranche(address(tranche)).mint(address(this), 100 * 1e18);

    // not owner
    vm.startPrank(address(0xbabe));
    vm.expectRevert(bytes("!AUTH"));
    distributor.setIsActive(true);
    vm.expectRevert(bytes("!AUTH"));
    distributor.transferToken(address(1), address(2), 1e18);
    vm.stopPrank();

    // owner
    distributor.setIsActive(true);
    assertEq(distributor.isActive(), true, 'Not active');

    deal(address(underlying), address(distributor), 1e18);
    distributor.transferToken(address(underlying), address(this), 1e18);
    assertEq(underlying.balanceOf(address(this)), 1e18, 'Bal not correct');
  }

  function testIsActive() external {
    address user = address(1);
    IdleCDOTranche(address(tranche)).mint(user, 100 * 1e18);
    // create contract, tot tranche supply == 100
    distributor = new DefaultDistributor(address(underlying), address(tranche), address(this));
    // give funds to redistribute
    deal(address(underlying), address(distributor), 200 * 1e6);
  
    vm.prank(user);
    vm.expectRevert(bytes("!ACTIVE"));
    distributor.claim(user);

    // allow claim
    distributor.setIsActive(true);
    assertEq(distributor.rate(), 2 * 1e6, 'Rate not correct');
  }

  function testClaim(uint16 amt, uint16 amt2, uint32 claimable) external {
    vm.assume(amt > 0 && amt < 1000);
    vm.assume(amt2 > 0 && amt2 < 1000);
    vm.assume(claimable > 0 && claimable < 10000000);

    address user = address(1);
    address user2 = address(2);
    uint256 _claimable = uint256(claimable) * 1e6;
    IdleCDOTranche(address(tranche)).mint(user, uint256(amt) * 1e18);
    IdleCDOTranche(address(tranche)).mint(user2, uint256(amt2) * 1e18);
    uint256 balU1 = underlying.balanceOf(user);
    uint256 balU2 = underlying.balanceOf(user2);

    // create contract
    distributor = new DefaultDistributor(address(underlying), address(tranche), address(this));
    // give funds to redistribute
    deal(address(underlying), address(distributor), _claimable);
    // allow claim
    distributor.setIsActive(true);

    vm.startPrank(user);
    tranche.approve(address(distributor), tranche.balanceOf(user));
    distributor.claim(user);
    assertApproxEqAbs(
      underlying.balanceOf(user) - balU1, 
      amt * _claimable / (amt + amt2),
      1000, // max delta
      'Balance claimed is wrong'
    );
    vm.stopPrank();

    vm.startPrank(user2);
    tranche.approve(address(distributor), tranche.balanceOf(user2));
    distributor.claim(user2);
    assertApproxEqAbs(
      underlying.balanceOf(user2) - balU2,
      amt2 * _claimable / (amt + amt2), 
      1000,
      'Balance claimed for user2 is wrong'
    );
    vm.stopPrank();
  }
}