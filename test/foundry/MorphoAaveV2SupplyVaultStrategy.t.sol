// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/morpho/MorphoAaveV2SupplyVaultStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "./TestIdleCDOBase.sol";

contract TestMorphoAaveV2SupplyVaultStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant ADAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    // Morpho-Aave Dai Stablecoin Supply Vault
    // https://github.com/morpho-dao/morpho-tokenized-vaults
    address internal constant maDAI = 0x36F8d0D0573ae92326827C4a82Fe4CE4C244cAb6;

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        _underlying = DAI;
        strategyToken = IERC20Detailed(maDAI);
        strategy = new MorphoAaveV2SupplyVaultStrategy();

        _strategy = address(strategy);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        MorphoAaveV2SupplyVaultStrategy(_strategy).initialize(
            "Idle MorphoAaveV2SupplyVaultStrategy DAI",
            "IdleMorphoSupplyVaultStrategy[DAI]",
            address(strategyToken),
            _underlying,
            _owner,
            ADAI
        );
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        MorphoAaveV2SupplyVaultStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        MorphoAaveV2SupplyVaultStrategy(address(strategy)).initialize(
            "Idle MorphoAaveV2SupplyVaultStrategy DAI",
            "IdleMorphoSupplyVaultStrategy[DAI]",
            maDAI,
            address(underlying),
            owner,
            ADAI
        );
    }

    function testAPR() external override runOnForkingNetwork(MAINNET_CHIANID) {}
}
