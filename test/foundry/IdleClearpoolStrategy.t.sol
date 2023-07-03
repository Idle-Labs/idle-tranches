// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./TestIdleCDOBase.sol";
import "../../contracts/strategies/clearpool/IdleClearpoolStrategy.sol";

contract TestIdleClearpoolStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    address cpToken = 0xCb288b6d30738db7E3998159d192615769794B5b;
    _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address univ2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    strategy = new IdleClearpoolStrategy();
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleClearpoolStrategy(_strategy).initialize(cpToken, _underlying, _owner, univ2Router);
  }

  function _selectFork() public override {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 15133116));
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleClearpoolStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function testOnlyOwner()
    public
    override
  {
    vm.prank(address(0xbabe));
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    IdleClearpoolStrategy(address(strategy)).setWhitelistedCDO(address(0xcafe));
  }

  function testCantReinitialize()
    external
    override
  {
    address _strategy = address(strategy);
    address cpToken = 0xCb288b6d30738db7E3998159d192615769794B5b;
    address univ2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleClearpoolStrategy(_strategy).initialize(
      cpToken,
      address(underlying),
      owner,
      univ2Router
    );
  }
}