// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/morpho/MorphoCompoundSupplyVaultStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/mocks/MockRewardsDistributor.sol";
import "./TestIdleCDOBase.sol";

contract TestMorphoCompoundSupplyVaultStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address internal constant MORPHO = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;

    // Morpho-Compound Dai Stablecoin Supply Vault
    // https://github.com/morpho-dao/morpho-tokenized-vaults
    address internal constant mcDAI = 0x8F88EaE3e1c01d60bccdc3DB3CBD5362Dd55d707;
    address internal constant morphoProxy = 0x777777c9898D384F785Ee44Acfe945efDFf5f3E0;
    address internal constant morphoDistributor = 0x60345417a227ad7E312eAa1B5EC5CD1Fe5E2Cdc6;

    // COMP token
    address internal rewardToken = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    address internal constant COMP_LENS = 0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67;

    function setUp() public override {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16917511));
        super.setUp();
    }

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        _underlying = DAI;
        strategyToken = IERC20Detailed(mcDAI);
        strategy = new MorphoCompoundSupplyVaultStrategy();

        _strategy = address(strategy);

        // override distributor code with mock
        vm.etch(morphoDistributor, address(new MockRewardsDistributor()).code);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        MorphoCompoundSupplyVaultStrategy(_strategy).initialize(
            address(strategyToken),
            _underlying,
            _owner,
            CDAI,
            rewardToken,
            morphoDistributor
        );

        vm.label(morphoProxy, "MorphoProxy");
        vm.label(COMP_LENS, "CompLens");
        vm.label(morphoDistributor, "MorphoDistributor");
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        MorphoCompoundSupplyVaultStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));

        // fund distributor with morpho tokens
        deal(MORPHO, morphoDistributor, 1000 * 1e18, true);
        // address account, uint256 claimable, bytes32[] memory proof
        extraData = abi.encode(_cdo, 1000 * 1e18, new bytes32[](0));
    }

    function testDeposits() external override {
        // poke morpho contract with a deposit to update strategyPrice
        _pokeMorpho();

        uint256 amount = 10000 * ONE_SCALE;
        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 strategyPrice = strategy.price();
        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        // increase time to accrue some interest
        skip(7 days);
        // Poke morpho contract with a deposit to increase strategyPrice
        _pokeMorpho();

        assertGt(strategy.price(), strategyPrice, "strategy price");
        // claim rewards
        _cdoHarvest(false);
        assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal after harvest");

        // Skip 7 day forward to accrue interest
        skip(7 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);

        // Poke morpho contract with a deposit to increase strategyPrice
        _pokeMorpho();
        assertGt(strategy.price(), strategyPrice, "strategy price");
        // virtualPrice should increase too
        assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
        assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
    }

    function testCantReinitialize() external override {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        MorphoCompoundSupplyVaultStrategy(address(strategy)).initialize(
            mcDAI,
            address(underlying),
            owner,
            CDAI,
            address(0),
            morphoDistributor
        );
    }

    function testRedeems() external override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);

        skip(7 days);
        vm.roll(block.number + 7 * 7200);

        // Poke morpho contract with a deposit to increase strategyPrice
        _pokeMorpho();

        // redeem all
        uint256 resAA = idleCDO.withdrawAA(0);
        assertGt(resAA, amount, "AA gained something");
        uint256 resBB = idleCDO.withdrawBB(0);
        assertGt(resBB, amount, "BB gained something");

        assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
        assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
        assertGe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
    }

    function testRedeemRewards() external virtual override {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);

        // sell some rewards
        uint256 pricePre = idleCDO.virtualPrice(address(AAtranche));
        _cdoHarvest(false);

        uint256 pricePost = idleCDO.virtualPrice(address(AAtranche));
        // NOTE: right now MORPHO is not transferable
        assertGt(IERC20Detailed(MORPHO).balanceOf(address(idleCDO)), 0, "morpho bal");
        assertGt(pricePost, pricePre, "virtual price increased");
    }

    function _cdoHarvest(bool _skipRewards) internal override {
        uint256 numOfRewards = rewards.length;
        bool[] memory _skipFlags = new bool[](4);
        bool[] memory _skipReward = new bool[](numOfRewards);
        uint256[] memory _minAmount = new uint256[](numOfRewards);
        uint256[] memory _sellAmounts = new uint256[](numOfRewards);
        bytes[] memory _extraData = new bytes[](2);
        if (!_skipRewards) {
            _extraData[0] = extraData;
            _extraData[1] = extraDataSell;
            // skip selling rewards (MORPHO) because MORPHO is not transferable
            _skipReward[0] = true;
        }
        // skip fees distribution
        _skipFlags[3] = _skipRewards;

        vm.prank(idleCDO.rebalancer());
        idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

        // linearly release all sold rewards
        vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1);
    }

    function _pokeMorpho() internal {
        uint256 userAmount = 10000 * ONE_SCALE;
        address user = address(0xbabe);
        deal(DAI, user, userAmount);
        vm.startPrank(user);
        IERC20Detailed(DAI).approve(mcDAI, type(uint256).max);
        IERC4626(mcDAI).deposit(userAmount, user);
        vm.stopPrank();
    }
}
