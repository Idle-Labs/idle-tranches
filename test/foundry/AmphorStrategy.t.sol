// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {AmphorStrategy} from "../../contracts/strategies/amphor/AmphorStrategy.sol";
import {IdleCDOAmphorVariant} from "../../contracts/IdleCDOAmphorVariant.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IAmphorVault} from "../../contracts/interfaces/amphor/IAmphorVault.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 maxAssets);
error ERC4626ExceededMaxRedeem(address owner, uint256 assets, uint256 maxAssets);

contract TestAmphorStrategy is TestIdleCDOLossMgmt {
  using stdStorage for StdStorage;

  uint256 internal constant ONE_TRANCHE = 1e18;
  address internal constant usdcVault = 0x3b022EdECD65b63288704a6fa33A8B9185b5096b;
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant wstethVault = 0x2791EB5807D69Fe10C02eED6B4DC12baC0701744;
  address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

  // address internal defaultUnderlying = USDC;
  // IERC4626Upgradeable internal defaultVault = IERC4626Upgradeable(usdcVault);
  address internal defaultUnderlying = WSTETH;
  IERC4626Upgradeable internal defaultVault = IERC4626Upgradeable(wstethVault);

  uint256 internal lastVaultAssets;

  function setUp() public override {
    if (defaultUnderlying == WSTETH) {
      vm.createSelectFork("mainnet", 18670247); // WSTETH deposit/redeem window open
    } else {
      vm.createSelectFork("mainnet", 18678289); // USDC deposit/redeem window open
    }
    super.setUp();
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOAmphorVariant();
  }

  function _deployStrategy(address _owner)
    internal
    override
    returns (address _strategy, address _underlying)
  {
    _underlying = defaultUnderlying;
    strategyToken = IERC20Detailed(address(defaultVault));
    strategy = new AmphorStrategy();

    _strategy = address(strategy);

    // initialize
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    AmphorStrategy(_strategy).initialize(address(defaultVault), defaultUnderlying, _owner);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    AmphorStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function _toggleEpoch(bool _start, int256 gain) internal {
    IAmphorVault _vault = IAmphorVault(address(defaultVault));
    address _owner = _vault.owner();
    vm.startPrank(_owner); 
    if (_start) {
      lastVaultAssets = defaultVault.totalAssets();
      _vault.start();
    } else {
      uint256 newNAV = uint256(int256(lastVaultAssets) + gain);
      deal(defaultUnderlying, _owner, newNAV);
      IERC20Detailed(defaultUnderlying).approve(address(defaultVault), newNAV);
      _vault.end(newNAV);
    }
    vm.stopPrank(); 
  }

  function _donateToken(address to, uint256 amount) internal override {
    deal(defaultUnderlying, to, amount);
  }

  function _createLoss(uint256 _loss) internal override {
    uint256 totalAssets = defaultVault.totalAssets();
    uint256 loss = totalAssets * _loss / FULL_ALLOC;
    uint256 bal = underlying.balanceOf(address(defaultVault));
    require(bal >= loss, "test: loss is too large");
    vm.prank(address(defaultVault));
    underlying.transfer(address(0xdead), loss);
    // update vault price
    _pokeLendingProtocol();
  }

  function testCantReinitialize() external override {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    AmphorStrategy(address(strategy)).initialize(address(1), address(2), owner);
  }

  function testCannotDepositWhenEpochRunning() external {
    _toggleEpoch(true, 0);

    uint256 amount = 10000 * ONE_SCALE;
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626ExceededMaxDeposit.selector, address(idleCDO), amount, 0)
    );
    idleCDO.depositAA(amount);
  }

  function testCannotRedeemWhenEpochRunning() external {
    uint256 amount = 1 * ONE_SCALE;
    idleCDO.depositAA(amount);
    vm.roll(block.number + 1);
    _toggleEpoch(true, 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626ExceededMaxRedeem.selector,
        address(strategy), 
        // amount - 1 because of the 1 wei rounding
        defaultVault.convertToShares(amount - 1), 
        0
      )
    );
    idleCDO.withdrawAA(0);
  }

  function testMinStkIDLEBalance() external override {
    uint256 tolerance = 100;
    _internalTestMinStkIDLEBalance(tolerance);
  }

  function testDeposits() external override {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;
    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);

    uint256 totAmount = amount * 2 * ONE_SCALE;

    uint256 balAA = IERC20(AAtranche).balanceOf(address(this));
    uint256 balBB = IERC20(BBtranche).balanceOf(address(this));

    // Minted amount is 1 wei less for each unit of underlying, scaled to 18 decimals
    assertGe(balAA, amount * ONE_TRANCHE - amount * 10**(18-decimals), "AAtranche bal");
    assertGe(balBB, amount * ONE_TRANCHE - amount * 10**(18-decimals), "BBtranche bal");

    assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal");
    assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal is != 0 in CDO");
    assertEq(
      strategyToken.balanceOf(address(idleCDO)), 
      defaultVault.convertToShares(totAmount), 
      "strategy bal"
    );
    uint256 strategyPrice = strategy.price();

    // check that trancheAPRSplitRatio and aprs are updated 
    assertApproxEqAbs(idleCDO.trancheAPRSplitRatio(), 25000, 1, "split ratio");
    // limit is 50% of the strategy apr if AAratio is <= 50%
    assertEq(idleCDO.getApr(address(AAtranche)), initialApr / 2, "AA apr");
    // apr will be 150% of the strategy apr if AAratio is == 50%
    assertEq(idleCDO.getApr(address(BBtranche)), initialApr * 3 / 2, "BB apr");

    // start epoch
    _toggleEpoch(true, 0);

    // end epoch with 10k gain
    _toggleEpoch(false, int256(10000 * ONE_SCALE));

    assertGt(strategy.price(), strategyPrice, "strategy price");

    // virtualPrice should increase too
    assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
    assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
  }

  function testRedeems() external override {
    uint256 amount = 10000 * ONE_SCALE;
    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    // start epoch
    _toggleEpoch(true, 0);
    // end epoch with 10k gain
    _toggleEpoch(false, int256(10000 * ONE_SCALE));

    vm.roll(block.number + 1);

    // redeem all
    uint256 resAA = idleCDO.withdrawAA(0);
    assertGt(resAA, amount, 'AA gained something');
    uint256 resBB = idleCDO.withdrawBB(0);
    assertGt(resBB, amount, 'BB gained something');
  
    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
    assertGt(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  function testMultipleDeposits() external {
    uint256 _val = 100 * ONE_SCALE;
    uint256 scaledVal = _val * 10**(18 - decimals);
    deal(address(underlying), address(this), _val * 100000000);

    uint256 priceAAPre = idleCDO.virtualPrice(address(AAtranche));
    // try to deposit the correct bal
    idleCDO.depositAA(_val);
    assertApproxEqAbs(
      IERC20Detailed(address(AAtranche)).balanceOf(address(this)), 
      scaledVal, 
      // 1 wei less for each unit of underlying, scaled to 18 decimals
      // check _mintShares for more info
      100 * 10**(18 - decimals) + 1, 
      'AA Deposit 1 is not correct'
    );
    uint256 priceAAPost = idleCDO.virtualPrice(address(AAtranche));

    // now deposit again
    address user1 = makeAddr('user1');
    _depositWithUser(user1, _val, true);
    assertApproxEqAbs(
      IERC20Detailed(address(AAtranche)).balanceOf(user1), 
      scaledVal, 
      // 1 wei less for each unit of underlying, scaled to 18 decimals
      // check _mintShares for more info
      100 * 10**(18 - decimals) + 1, 
      'AA Deposit 2 is not correct'
    );
    uint256 priceAAPost2 = idleCDO.virtualPrice(address(AAtranche));

    assertApproxEqAbs(priceAAPost, priceAAPre, 1, 'AA price is not the same after deposit 1');
    assertApproxEqAbs(priceAAPost2, priceAAPost, 1, 'AA price is not the same after deposit 2');
  }

  // @dev Loss is between 0% and lossToleranceBps and is socialized
  function testDepositWithLossSocialized(uint256 depositAmountAARatio) external override {
    vm.assume(depositAmountAARatio >= 0);
    vm.assume(depositAmountAARatio <= FULL_ALLOC);

    uint256 amountAA = 100000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
    uint256 amountBB = 100000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;
    uint256 preAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 preBBPrice = idleCDO.virtualPrice(address(BBtranche));

    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);

    uint256 prePrice = strategy.price();
    uint256 unclaimedFees = idleCDO.unclaimedFees();

    // now let's simulate a loss by decreasing strategy price
    // curr price - about 0.25%
    _createLoss(idleCDO.lossToleranceBps() / 2);

    uint256 priceDelta = ((prePrice - strategy.price()) * 1e18) / prePrice;
    uint256 lastNAVAA = idleCDO.lastNAVAA();
    uint256 currentAARatioScaled = lastNAVAA * ONE_SCALE / (idleCDO.lastNAVBB() + lastNAVAA);
    uint256 postAAPrice = idleCDO.virtualPrice(address(AAtranche));
    uint256 postBBPrice = idleCDO.virtualPrice(address(BBtranche));

    // Both junior and senior lost
    if (currentAARatioScaled > 0) {
      assertApproxEqAbs(postAAPrice, (preAAPrice * (1e18 - priceDelta)) / 1e18, 100, "AA price after loss");
    } else {
      assertApproxEqAbs(postAAPrice, preAAPrice, 1, "AA price not changed");
    }
    if (currentAARatioScaled < ONE_SCALE) {
      assertApproxEqAbs(postBBPrice, (preBBPrice * (1e18 - priceDelta)) / 1e18, 100, "BB price after loss");
    } else {
      assertApproxEqAbs(postBBPrice, preBBPrice, 1, "BB price not changed");
    }

    assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 1, "AA price not updated until new interaction");
    assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 1, "BB price not updated until new interaction");
    assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 0, "Fees did not increase");
  }
}
