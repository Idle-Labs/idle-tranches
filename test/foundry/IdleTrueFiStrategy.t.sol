// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import {IdleTruefiStrategy} from "../../contracts/strategies/truefi/IdleTruefiStrategy.sol";
import {IdleCDOTruefiVariant} from "../../contracts/IdleCDOTruefiVariant.sol";
import {ITruefiPool, ITrueLegacyMultiFarm} from "../../contracts/interfaces/truefi/ITruefi.sol";

contract TestIdleTruefiStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    _underlying= 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    strategy = IIdleCDOStrategy(address(new IdleTruefiStrategy()));
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleTruefiStrategy(_strategy).initialize(
      ITruefiPool(0xA991356d261fbaF194463aF6DF8f0464F8f1c742), // tfUSDC 
      ITrueLegacyMultiFarm(0xec6c3FD795D6e6f202825Ddb56E01b3c128b0b10),
      _owner
    );
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleTruefiStrategy(address(strategy)).setIdleCDO(address(_cdo));
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOTruefiVariant();
  }

  function testRedeems() external override runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 initial = underlying.balanceOf(address(this));
    // funds in lending
    _cdoHarvest(true);
    skip(7 days); 
    vm.roll(block.number + 1);
    // sell some rewards
    _cdoHarvest(false);

    idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
    uint256 balnow = underlying.balanceOf(address(this));
    idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));
  
    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");

    // TODO here we are getting something less, verify that this is correct and due 
    // to the exit fee
    assertGt(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  // TODO
  // function testDefaultCheck() external runOnForkingNetwork(MAINNET_CHIANID) {
  // }
}