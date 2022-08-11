// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import {IdleTruefiStrategy} from "../../contracts/strategies/truefi/IdleTruefiStrategy.sol";
import {IdleCDOTruefiVariant} from "../../contracts/IdleCDOTruefiVariant.sol";
import {ITruefiPool, ITrueLegacyMultiFarm, ILoanToken} from "../../contracts/interfaces/truefi/ITruefi.sol";

error Default();

contract TestIdleTruefiStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;
  ITruefiPool public _pool = ITruefiPool(0xA991356d261fbaF194463aF6DF8f0464F8f1c742);
  uint128 public constant LAST_MINUTE_PAYBACK_DURATION = 1 days;
  uint256 private constant BASIS_POINTS = 1e4;

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    strategy = IIdleCDOStrategy(address(new IdleTruefiStrategy()));
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleTruefiStrategy(_strategy).initialize(
      _pool, // tfUSDC 
      ITrueLegacyMultiFarm(0xec6c3FD795D6e6f202825Ddb56E01b3c128b0b10),
      _owner
    );
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleTruefiStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOTruefiVariant();
  }

  function testCantReinitialize()
    external
    override
    runOnForkingNetwork(MAINNET_CHIANID)
  {
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleTruefiStrategy(address(strategy)).initialize(
      _pool, // tfUSDC 
      ITrueLegacyMultiFarm(0xec6c3FD795D6e6f202825Ddb56E01b3c128b0b10),
      owner
    );
  }

  function testRedeems() external override runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 10000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // funds in lending
    _cdoHarvest(true);
    skip(20 days); 
    vm.roll(block.number + 1);
    // sell some rewards
    _cdoHarvest(false);

    idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
    idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));
  
    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");

    assertGt(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  function testRedeemsWithPenalty() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 100000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 initial = underlying.balanceOf(address(this));
    // funds in lending
    _cdoHarvest(true);
    // we exit the position and get the penalty
    uint256 penA = applyPenalty(amount);
    idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
    uint256 balnowA = underlying.balanceOf(address(this));
    assertApproxEqAbs(balnowA - initial, penA, ONE_SCALE, "AA redeem bal");

    uint256 penB = applyPenalty(amount);
    idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));
    uint256 balnowB = underlying.balanceOf(address(this));
    assertApproxEqAbs(balnowB - balnowA, penB, ONE_SCALE, "BB redeem bal");

    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");

    // here we are getting something less due to the exit fee
    assertApproxEqAbs(underlying.balanceOf(address(this)), initialBal - (amount - penA) - (amount - penB), ONE_SCALE, "underlying bal increased");
  }

  function testDefaultCheck() external runOnForkingNetwork(MAINNET_CHIANID) {
    uint256 amount = 100000 * ONE_SCALE;
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // funds in lending
    _cdoHarvest(true);

    // set 1 loan as defaulted
    ILoanToken[] memory loans = _pool.lender().loans(_pool);
    ILoanToken loan = loans[0];
    vm.warp(loan.start() + loan.term() + LAST_MINUTE_PAYBACK_DURATION);
    loan.enterDefault();
    vm.roll(block.number + 1);
    assertEq(uint256(loan.status()), uint256(ILoanToken.Status.Defaulted), 'loan defaulted');
    
    // try to exit the position but it will fail with status reason "4" (defaulted)
    uint256 balAA = IERC20Detailed(address(AAtranche)).balanceOf(address(this));
    vm.expectRevert(Default.selector);
    idleCDO.withdrawAA(balAA);

    uint256 balBB = IERC20Detailed(address(BBtranche)).balanceOf(address(this));
    vm.expectRevert(Default.selector);
    idleCDO.withdrawBB(balBB);
  }

  // calculate exit penalty
  function applyPenalty(uint256 amount) internal view returns (uint256) {
    return amount * _pool.liquidExitPenalty(amount) / BASIS_POINTS;
  }
}