// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import "../../contracts/strategies/ribbon/IdleRibbonStrategy.sol";

contract TestIdleRibbonStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;

  function _selectFork() public override {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 15831007));
  }

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    // rFOL-USDC
    address cpToken = 0x3CD0ecf1552D135b8Da61c7f44cEFE93485c616d;
    _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address univ2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    strategy = new IdleRibbonStrategy();
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleRibbonStrategy(_strategy).initialize(cpToken, _underlying, _owner, univ2Router);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleRibbonStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function testOnlyOwner()
    public
    override
  {
    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    IdleRibbonStrategy(address(strategy)).setWhitelistedCDO(address(0xcafe));
  }

  function testCantReinitialize()
    external
    override
  {
    address _strategy = address(strategy);
    address cpToken = 0x3CD0ecf1552D135b8Da61c7f44cEFE93485c616d;
    address univ2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleRibbonStrategy(_strategy).initialize(
      cpToken,
      address(underlying),
      owner,
      univ2Router
    );
  }
}