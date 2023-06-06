// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/strategies/euler/IdleEulerStrategy.sol";
import "./TestIdleCDOBase.sol";

contract TestIdleEulerStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;

  function _selectFork() public override {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16527983));
  }

  function _deployStrategy(address _owner) internal override returns (
    address _strategy,
    address _underlying
  ) {
    address eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    address lendingToken = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716; // eUSDC
    _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    strategy = new IdleEulerStrategy();
    _strategy = address(strategy);
    stdstore
      .target(_strategy)
      .sig(strategy.token.selector)
      .checked_write(address(0));
    IdleEulerStrategy(_strategy).initialize(lendingToken, _underlying, eulerMain, _owner);

    vm.label(eulerMain, "euler");
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    IdleEulerStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function testOnlyIdleCDO() 
    public 
    override
  {}

  function testCantReinitialize()
    external
    override
  {
    address eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    address lendingToken = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716; // eUSDC
    address _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    IdleEulerStrategy(address(strategy)).initialize(lendingToken, _underlying, eulerMain, owner);
  }
}