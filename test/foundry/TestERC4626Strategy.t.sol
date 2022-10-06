// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/ERC4626Strategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "./TestIdleCDOBase.sol";

contract TestERC4626VaultStrategy is ERC4626Strategy {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _strategyToken,
        address _token,
        address _owner
    ) public initializer {
        _initialize(_name, _symbol, _strategyToken, _token, _owner);

        IERC20Detailed(_token).approve(_strategyToken, type(uint256).max);
    }

    function getApr() external view override returns (uint256 apr) {}

    function getRewardTokens() external view returns (address[] memory rewards) {}
}

contract TestERC4626Strategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // Morpho-Aave Dai Stablecoin Supply Vault
    address internal constant maDAI = 0x3A91D37BAc30C913369E1ABC8CAd1C13D1ff2e98;

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        _underlying = DAI;
        strategyToken = IERC20Detailed(maDAI);
        strategy = new TestERC4626VaultStrategy();

        _strategy = address(strategy);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        TestERC4626VaultStrategy(_strategy).initialize(
            "Idle TestERC4626VaultStrategy DAI",
            "IdleTestERC4626VaultStrategy[DAI]",
            address(strategyToken),
            _underlying,
            _owner
        );
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        TestERC4626VaultStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        TestERC4626VaultStrategy(address(strategy)).initialize(
            "Idle TestERC4626VaultStrategy DAI",
            "IdleTestERC4626VaultStrategy[DAI]",
            maDAI,
            address(underlying),
            owner
        );
    }

    function testAPR() external override runOnForkingNetwork(MAINNET_CHIANID) {}
}
