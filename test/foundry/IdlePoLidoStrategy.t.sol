// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../../contracts/strategies/lido/IdlePoLidoStrategy.sol";
import {IdleCDOPoLidoVariant} from "../../contracts/IdleCDOPoLidoVariant.sol";
import "./TestIdleCDOBase.sol";

import "../../contracts/interfaces/IStMatic.sol";

contract TestIdlePoLidoStrategy is TestIdleCDOBase, IERC721Receiver {
    using stdStorage for StdStorage;

    /// @notice stMatic contract
    IStMATIC internal constant stMatic = IStMATIC(0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599);

    /// @notice Matic contract
    IERC20Detailed public constant MATIC = IERC20Detailed(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0);
    address public constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IPoLidoNFT internal poLidoNFT;
    function _selectFork() public override {
        // IdleUSDC deposited all in compund
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16527983));
    }

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        poLidoNFT = stMatic.poLidoNFT();
        bytes[] memory _extraPath = new bytes[](1);
        _extraPath[0] = abi.encodePacked(LDO, uint24(3000), WETH, uint24(3000), address(MATIC));
        extraDataSell = abi.encode(_extraPath);
        _underlying = address(MATIC);
        strategy = new IdlePoLidoStrategy();
        _strategy = address(strategy);

        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        IdlePoLidoStrategy(_strategy).initialize(_owner);
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        IdlePoLidoStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function _deployCDO() internal override returns (IdleCDO _cdo) {
        _cdo = new IdleCDOPoLidoVariant();
        vm.prank(owner);
        _cdo.setUnlentPerc(0); // NOTE: set unlentPerc zero to avoid left matic in the contract
    }

    function testCantReinitialize() external override {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdlePoLidoStrategy(address(strategy)).initialize(owner);
    }

    function testOnlyOwner() public override {
        super.testOnlyOwner();
        vm.startPrank(address(0xbabe));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IdlePoLidoStrategy(address(strategy)).transferToken(address(1), 100, address(2));

        vm.stopPrank();
    }

    function testDeposits() external override {
        uint256 amount = 10000 * ONE_SCALE;
        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 totAmount = amount * 2;

        assertEq(IERC20(AAtranche).balanceOf(address(this)), 10000 * 1e18, "AAtranche bal");
        assertEq(IERC20(BBtranche).balanceOf(address(this)), 10000 * 1e18, "BBtranche bal");
        assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal");
        // in case of poLido cdo variant funds is deposited immediately into strategy
        assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal");
        assertGt(strategyToken.balanceOf(address(idleCDO)), 0, "strategy bal");
        uint256 strategyPrice = strategy.price();

        // check that trancheAPRSplitRatio and aprs are updated
        assertApproxEqAbs(idleCDO.trancheAPRSplitRatio(), 25000, 1, "split ratio");
        // limit is 50% of the strategy apr if AAratio is <= 50%
        assertEq(idleCDO.getApr(address(AAtranche)), initialApr / 2, "AA apr");
        // apr will be 150% of the strategy apr if AAratio is == 50%
        assertEq(idleCDO.getApr(address(BBtranche)), (initialApr * 3) / 2, "BB apr");

        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        // claim rewards
        _cdoHarvest(false);
        (uint256 priceLast, uint256 totalShares, uint256 totalPooledMATIC) = stMatic.convertStMaticToMatic(ONE_SCALE);
        assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal after harvest");

        // NOTE: mock stMatic.convertStMaticToMatic call
        // increase stMATIC price
        vm.mockCall(
            address(stMatic),
            abi.encodeWithSelector(IStMATIC.convertStMaticToMatic.selector, ONE_SCALE),
            abi.encode((priceLast * 101) / 100, totalShares, totalPooledMATIC)
        );
        assertGt(strategy.price(), strategyPrice, "strategy price");

        // virtualPrice should increase too
        assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
        assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");

        vm.clearMockedCalls();
    }

    function testRedeemRewards() external override {
        // rewards are managed manually so we only test that the correct reward token address is set
        address[] memory _rewards = strategy.getRewardTokens();
        assertEq(_rewards[0], LDO, "Wrong reward address");
        assertEq(_rewards.length, 1, "Wrong reward number");
    }

    function testRedeems() external override {
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

    function testOnlyIdleCDO() public override {
        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.deposit(1e10);

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.redeem(1e10);
    }

    function testRestoreOperations() external override {
        uint256 amount = 1000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // call with non owner
        vm.expectRevert(bytes("6"));
        vm.prank(address(0xbabe));
        idleCDO.restoreOperations();

        // call with owner
        vm.startPrank(owner);
        idleCDO.emergencyShutdown();
        idleCDO.restoreOperations();
        vm.stopPrank();

        vm.roll(block.number + 1);

        idleCDO.withdrawAA(amount);
        idleCDO.withdrawBB(amount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

  function testMinStkIDLEBalance() external override {}
}
