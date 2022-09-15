// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../contracts/strategies/lido/IdlePoLidoStrategy.sol";
import {IdleCDOPoLidoVariant} from "../../contracts/IdleCDOPoLidoVariant.sol";
import "./TestIdleCDOBase.sol";

import "../../contracts/interfaces/IStMatic.sol";

contract TestIdlePoLidoStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    /// @notice stMatic contract
    IStMATIC internal constant stMatic = IStMATIC(0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599);

    /// @notice Matic contract
    IERC20Detailed public constant MATIC = IERC20Detailed(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0);

    IPoLidoNFT internal poLidoNFT;

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        poLidoNFT = stMatic.poLidoNFT();
        _underlying = address(MATIC);
        strategy = new IdlePoLidoStrategy();
        _strategy = address(strategy);

        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        IdlePoLidoStrategy(_strategy).initialize(_owner);

        vm.label(address(stMatic), "stMATIC");
        vm.label(address(MATIC), "MATIC");
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        IdlePoLidoStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function _deployCDO() internal override returns (IdleCDO _cdo) {
        _cdo = new IdleCDOPoLidoVariant();
    }

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdlePoLidoStrategy(address(strategy)).initialize(owner);
    }

    function testRedeems() external override runOnForkingNetwork(MAINNET_CHIANID) {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);

        {
            // user receives an nft not underlying
            idleCDO.withdrawAA(IERC20Detailed(address(AAtranche)).balanceOf(address(this)));
            uint256[] memory tokenIds = poLidoNFT.getOwnedTokens(address(this));
            assertEq(poLidoNFT.ownerOf(tokenIds[tokenIds.length - 1]), address(this), "withdrawAA: poLidoNft owner");
        }
        {
            // user receives an nft not underlying
            idleCDO.withdrawBB(IERC20Detailed(address(BBtranche)).balanceOf(address(this)));
            uint256[] memory tokenIds = poLidoNFT.getOwnedTokens(address(this));
            assertEq(poLidoNFT.ownerOf(tokenIds[tokenIds.length - 1]), address(this), "withdrawBB: poLidoNft owner");
        }

        assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
        assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
    }
}
