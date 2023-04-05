// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./TestIdleCDOBase.sol";

import {InstadappLiteETHV2Strategy} from "../../contracts/strategies/instadapp/InstadappLiteETHV2Strategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";

contract TestInstadappLiteETHV2Strategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant ETHV2Vault = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16981000);
        super.setUp();
    }

    function _deployStrategy(address _owner)
        internal
        override
        runOnForkingNetwork(MAINNET_CHIANID)
        returns (address _strategy, address _underlying)
    {
        _underlying = STETH;
        strategyToken = IERC20Detailed(ETHV2Vault);
        strategy = new InstadappLiteETHV2Strategy();

        _strategy = address(strategy);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        InstadappLiteETHV2Strategy(_strategy).initialize(_owner);
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        InstadappLiteETHV2Strategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testCantReinitialize() external virtual override {}
}
