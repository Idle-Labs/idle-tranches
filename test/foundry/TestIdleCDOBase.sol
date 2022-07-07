// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleCDO.sol";
import "forge-std/Test.sol";

abstract contract TestIdleCDOBase is Test {
    using stdStorage for StdStorage;

    uint256 internal constant FULL_ALLOC = 100000;
    uint256 internal constant MAINNET_CHIANID = 1;
    uint256 internal initialBal;
    uint256 internal decimals;
    uint256 internal ONE_SCALE;
    address[] internal rewards;
    address[] internal incentives; // incentives is a subset of rewards
    address public owner;
    IdleCDO internal idleCDO;
    IERC20Detailed internal underlying;
    IERC20Detailed internal strategyToken;
    IdleCDOTranche internal AAtranche;
    IdleCDOTranche internal BBtranche;
    IIdleCDOStrategy internal strategy;

    // override these methods in derived contracts
    function _deployStrategy(address _owner)
        internal
        virtual
        returns (address _strategy, address _underlying);

    function _postDeploy(address _cdo, address _owner) internal virtual;

    // end override

    modifier runOnForkingNetwork(uint256 networkId) {
        // solhint-disable-next-line
        if (block.chainid == networkId) {
            _;
        }
    }

    function setUp() public virtual runOnForkingNetwork(MAINNET_CHIANID) {
        idleCDO = _deployLocalContracts();

        owner = idleCDO.owner();
        underlying = IERC20Detailed(idleCDO.token());
        decimals = underlying.decimals();
        ONE_SCALE = 10**decimals;
        strategy = IIdleCDOStrategy(idleCDO.strategy());
        strategyToken = IERC20Detailed(strategy.strategyToken());
        AAtranche = IdleCDOTranche(idleCDO.AATranche());
        BBtranche = IdleCDOTranche(idleCDO.BBTranche());
        rewards = strategy.getRewardTokens();
        incentives = idleCDO.getIncentiveTokens();

        // fund
        initialBal = 1000000 * ONE_SCALE;
        deal(address(underlying), address(this), initialBal, true);
        underlying.approve(address(idleCDO), type(uint256).max);

        // label
        vm.label(address(idleCDO), "idleCDO");
        vm.label(address(AAtranche), "AAtranche");
        vm.label(address(BBtranche), "BBtranche");
        vm.label(address(strategy), "strategy");
        vm.label(address(underlying), "underlying");
        vm.label(address(strategyToken), "strategyToken");
    }

    function testInitialize() external runOnForkingNetwork(MAINNET_CHIANID) {
        assertEq(idleCDO.token(), address(underlying));
        assertGt(strategy.price(), ONE_SCALE);
        assertEq(idleCDO.tranchePrice(address(AAtranche)), ONE_SCALE);
        assertEq(idleCDO.tranchePrice(address(BBtranche)), ONE_SCALE);
    }

    function testCantReinitialize() external virtual;

    function testDeposits() external runOnForkingNetwork(MAINNET_CHIANID) {
        uint256 amount = 10000 * ONE_SCALE;
        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 totAmount = amount * 2;

        assertEq(
            IERC20(AAtranche).balanceOf(address(this)),
            10000 * 1e18,
            "AAtranche bal"
        );
        assertEq(
            IERC20(BBtranche).balanceOf(address(this)),
            10000 * 1e18,
            "BBtranche bal"
        );
        assertEq(
            underlying.balanceOf(address(this)),
            initialBal - totAmount,
            "underlying bal"
        );
        assertEq(
            underlying.balanceOf(address(idleCDO)),
            totAmount,
            "underlying bal"
        );
        // strategy is still empty with no harvest
        assertEq(strategyToken.balanceOf(address(idleCDO)), 0, "strategy bal");
        uint256 strategyPrice = strategy.price();

        _cdoHarvest(true);
        assertEq(
            underlying.balanceOf(address(idleCDO)),
            0,
            "underlying bal after harvest"
        );
        // Skip 7 day forward to accrue interest
        skip(7 days);
        vm.roll(block.number + 1);

        assertGt(strategy.price(), strategyPrice, "strategy price");
        // virtualPrice should increase too
        assertGt(
            idleCDO.virtualPrice(address(AAtranche)),
            ONE_SCALE,
            "AA virtual price"
        );
        assertGt(
            idleCDO.virtualPrice(address(BBtranche)),
            ONE_SCALE,
            "BB virtual price"
        );
    }

    function testRedeems() external runOnForkingNetwork(MAINNET_CHIANID) {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);

        idleCDO.withdrawAA(
            IERC20Detailed(address(AAtranche)).balanceOf(address(this))
        );
        idleCDO.withdrawBB(
            IERC20Detailed(address(BBtranche)).balanceOf(address(this))
        );

        assertEq(
            IERC20(AAtranche).balanceOf(address(this)),
            0,
            "AAtranche bal"
        );
        assertEq(
            IERC20(BBtranche).balanceOf(address(this)),
            0,
            "BBtranche bal"
        );
        assertGt(
            underlying.balanceOf(address(this)),
            initialBal,
            "underlying bal increased"
        );
    }

    function testRedeemRewards() external runOnForkingNetwork(MAINNET_CHIANID) {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);

        // sell some rewards
        uint256 pricePre = idleCDO.virtualPrice(address(AAtranche));
        _cdoHarvest(false);
        vm.roll(block.number + 1);
        uint256 pricePost = idleCDO.virtualPrice(address(AAtranche));
        if (_numOfSellableRewards() > 0) {
            assertGt(pricePost, pricePre, "virtual price increased");
        } else {
            assertEq(pricePost, pricePre, "virtual price equal");
        }
    }

    function testOnlyIdleCDO()
        public
        virtual
        runOnForkingNetwork(MAINNET_CHIANID)
    {
        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.deposit(1e10);

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.redeem(1e10);

        vm.prank(address(0xbabe));
        vm.expectRevert(bytes("Only IdleCDO can call"));
        strategy.redeemRewards(bytes(""));
    }

    function testOnlyOwner() public virtual;

    function testAPR() external runOnForkingNetwork(MAINNET_CHIANID) {
        uint256 amount = 10000 * ONE_SCALE;
        idleCDO.depositAA(amount);

        // funds in lending
        _cdoHarvest(true);
        skip(7 days);
        vm.roll(block.number + 1);
        uint256 apr = idleCDO.getApr(address(AAtranche));
        assertGt(apr / 1e16, 0, "apr is > 0.01% and with 18 decimals");
    }

    function _cdoHarvest(bool _skipRewards) internal {
        uint256 numOfRewards = _numOfSellableRewards();
        bool[] memory _skipFlags = new bool[](4);
        bool[] memory _skipReward = new bool[](numOfRewards);
        uint256[] memory _minAmount = new uint256[](numOfRewards);
        uint256[] memory _sellAmounts = new uint256[](numOfRewards);
        bytes memory _extraData;
        // bytes memory _extraData = abi.encode(uint256(0), uint256(0), uint256(0));
        // skip fees distribution
        _skipFlags[3] = _skipRewards;

        vm.prank(idleCDO.rebalancer());
        idleCDO.harvest(
            _skipFlags,
            _skipReward,
            _minAmount,
            _sellAmounts,
            _extraData
        );
        // linearly release all sold rewards
        vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1);
    }

    function _deployLocalContracts() internal returns (IdleCDO _cdo) {
        address _owner = address(2);
        address _rebalancer = address(3);
        (address _strategy, address _underlying) = _deployStrategy(_owner);

        // deploy idleCDO and tranches
        _cdo = new IdleCDO();
        stdstore.target(address(_cdo)).sig(_cdo.token.selector).checked_write(
            address(0)
        );

        address[] memory incentiveTokens = new address[](0);
        _cdo.initialize(
            0,
            _underlying,
            address(this), // governanceFund,
            _owner, // owner,
            _rebalancer, // rebalancer,
            _strategy, // strategyToken
            20000, // apr split: 100000 is 100% to AA
            50000, // ideal value: 50% AA and 50% BB tranches
            incentiveTokens
        );

        vm.startPrank(_owner);
        _cdo.setIsAYSActive(true);
        _cdo.setUnlentPerc(0);
        _cdo.setFee(0);
        vm.stopPrank();

        _postDeploy(address(_cdo), _owner);
    }

    function _numOfSellableRewards() internal view returns (uint256 num) {
        for (uint256 i = 0; i < rewards.length; i++) {
            if (!_includesAddress(incentives, rewards[i])) {
                num++;
            }
        }
    }

    function _includesAddress(address[] memory _array, address _val)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _val) {
                return true;
            }
        }
        // explicit return to fix linter
        return false;
    }
}
