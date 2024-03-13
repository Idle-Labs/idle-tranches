// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {EthenaSusdeStrategy} from "../../contracts/strategies/ethena/EthenaSusdeStrategy.sol";
import {EthenaCooldownRequest} from "../../contracts/strategies/ethena/EthenaCooldownRequest.sol";
import {IdleCDOEthenaVariant} from "../../contracts/IdleCDOEthenaVariant.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {IStakedUSDeV2} from "../../contracts/interfaces/ethena/IStakedUSDeV2.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";

contract TestEthenaSusdeStrategy is TestIdleCDOLossMgmt {
  using stdStorage for StdStorage;

  event NewCooldownRequestContract(address indexed contractAddress, address indexed user, uint256 susdeAmount);

  uint256 internal constant ONE_TRANCHE = 1e18;
  address internal constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
  address internal constant SUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

  address internal defaultUnderlying = USDe;
  IERC4626Upgradeable internal defaultVault = IERC4626Upgradeable(SUSDe);

  uint256 internal lastVaultAssets;

  function _selectFork() public override {
    vm.createSelectFork("mainnet", 19369820); // USDC deposit/redeem window open
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOEthenaVariant();
  }

  function _deployStrategy(address _owner)
    internal
    override
    returns (address _strategy, address _underlying)
  {
    _underlying = defaultUnderlying;
    strategyToken = IERC20Detailed(address(defaultVault));
    strategy = new EthenaSusdeStrategy();

    _strategy = address(strategy);

    // initialize
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    EthenaSusdeStrategy(_strategy).initialize(address(defaultVault), defaultUnderlying, _owner);
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    EthenaSusdeStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
  }

  function _donateToken(address to, uint256 amount) internal override {
    address donator = makeAddr('donator');
    deal(defaultUnderlying, donator, amount, true);
    vm.prank(donator);
    IERC20Detailed(defaultUnderlying).transfer(to, amount);
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
    EthenaSusdeStrategy(address(strategy)).initialize(address(1), address(2), owner);
  }

  function testMinStkIDLEBalance() external override {
    uint256 tolerance = 100;
    _internalTestMinStkIDLEBalance(tolerance);
  }

  function testCooldownRequestContract() external {
    uint256 initAmount = underlying.balanceOf(address(this));
    uint256 amount = 10000 * ONE_SCALE;

    idleCDO.depositAA(amount);
    _cdoHarvest(true);
    vm.roll(block.number + 1);

    // increase strategyToken price
    _donateToken(address(defaultVault), amount / 1000);

    vm.recordLogs();
    idleCDO.withdrawAA(0);
    Vm.Log[] memory logsAA = vm.getRecordedLogs();
    Vm.Log memory newCooldownLogAA = logsAA[logsAA.length - 1];
    // convert bytes32 to address
    address clone = address(uint160(uint256(newCooldownLogAA.topics[1])));

    // wait cooldown
    vm.warp(block.timestamp + uint256(IStakedUSDeV2(SUSDe).cooldownDuration()) + 1);

    vm.startPrank(makeAddr('badActor'));
    vm.expectRevert(bytes("6"));
    EthenaCooldownRequest(clone).startCooldown();

    vm.expectRevert(bytes("6"));
    EthenaCooldownRequest(clone).rescue(SUSDe);
    EthenaCooldownRequest(clone).unstake();
    vm.stopPrank();

    uint256 finalAmount = underlying.balanceOf(address(this));
    assertGe(finalAmount, initAmount, "USDe balance is not the same or increasing");

    // Test rescue
    uint256 rescueAmount = 1000 * ONE_SCALE;
    _donateToken(clone, rescueAmount);
    vm.prank(TL_MULTISIG);
    EthenaCooldownRequest(clone).rescue(USDe);

    assertEq(underlying.balanceOf(TL_MULTISIG), rescueAmount, "USDe balance is not eq to rescueAmount");
  }

  function testDeposits() external override {
    uint256 amount = 10000;
    uint256 amountWei = amount * ONE_SCALE;
    // AARatio 50%
    idleCDO.depositAA(amountWei);
    idleCDO.depositBB(amountWei);
    _cdoHarvest(true);
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
      defaultVault.convertToShares(totAmount) - 1, 
      "strategy bal"
    );
    uint256 strategyPrice = strategy.price();

    // check that trancheAPRSplitRatio and aprs are updated 
    assertApproxEqAbs(idleCDO.trancheAPRSplitRatio(), 25000, 1, "split ratio");
    // limit is 50% of the strategy apr if AAratio is <= 50%
    assertEq(idleCDO.getApr(address(AAtranche)), initialApr / 2, "AA apr");
    // apr will be 150% of the strategy apr if AAratio is == 50%
    assertEq(idleCDO.getApr(address(BBtranche)), initialApr * 3 / 2, "BB apr");

    // simulate increase in strategyToken price
    _donateToken(address(defaultVault), amountWei / 1000);

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
    _cdoHarvest(true);
    vm.roll(block.number + 1);

    // increase strategyToken price
    _donateToken(address(defaultVault), amount / 1000);

    // redeem all AA
    vm.recordLogs();
    // expectEmit has 4 params: first 3 for the indexed value, last one for the rest of data 
    // that should match with the provided emitted event right after if true
    vm.expectEmit(false, true, false, false);
    // The event we expect
    emit NewCooldownRequestContract(address(1), address(this), 0);
    uint256 resAA = idleCDO.withdrawAA(0);
    Vm.Log[] memory logsAA = vm.getRecordedLogs();
    Vm.Log memory newCooldownLogAA = logsAA[logsAA.length - 1];
    // convert bytes32 to address
    address clone1 = address(uint160(uint256(newCooldownLogAA.topics[1])));
    assertGt(resAA, amount, 'AA gained something');
    assertEq(IERC20(AAtranche).balanceOf(address(this)), 0, "AAtranche bal");

    // redeem all BB
    vm.recordLogs();
    vm.expectEmit(false, true, false, false);
    // The event we expect
    emit NewCooldownRequestContract(address(1), address(this), 0);
    uint256 resBB = idleCDO.withdrawBB(0);
    Vm.Log[] memory logsBB = vm.getRecordedLogs();
    Vm.Log memory newCooldownLogBB = logsBB[logsBB.length - 1];
    // convert bytes32 to address
    address clone2 = address(uint160(uint256(newCooldownLogBB.topics[1])));
    assertGt(resBB, amount, 'BB gained something');
    assertEq(IERC20(BBtranche).balanceOf(address(this)), 0, "BBtranche bal");
  
    // wait cooldown
    vm.warp(block.timestamp + uint256(IStakedUSDeV2(SUSDe).cooldownDuration()));

    // Trigger unstake (anyone can call)
    vm.startPrank(makeAddr('badActor'));
    EthenaCooldownRequest(clone1).unstake();
    EthenaCooldownRequest(clone2).unstake();
    vm.stopPrank();
  
    assertEq(clone1 != clone2, true, 'clones are different');
    assertGt(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
  }

  // @dev Loss is between 0% and lossToleranceBps and is socialized
  // function testRedeemWithLossSocialized2(uint256 amountAA, uint256 amountBB) external {
  function testRedeemWithLossSocialized(uint256 depositAmountAARatio) external override {
    vm.assume(depositAmountAARatio >= 0);
    vm.assume(depositAmountAARatio <= FULL_ALLOC);

    uint256 amountAA = 10000 * ONE_SCALE * depositAmountAARatio / FULL_ALLOC;
    uint256 amountBB = 10000 * ONE_SCALE * (FULL_ALLOC - depositAmountAARatio) / FULL_ALLOC;

    idleCDO.depositAA(amountAA);
    idleCDO.depositBB(amountBB);
    _cdoHarvest(true);

    uint256 prePrice = strategy.price();

    vm.roll(block.number + 1);

    // now let's simulate a loss by decreasing strategy price
    // curr price - about 0.25%
    _createLoss(idleCDO.lossToleranceBps() / 2);
    uint256 priceDelta = ((prePrice - strategy.price()) * 1e18) / prePrice;
    uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));
    uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));

    // redeem all
    uint256 resAA;
    if (depositAmountAARatio > 0) {
      resAA = idleCDO.withdrawAA(0);
      assertApproxEqRel(
        resAA,
        amountAA * (1e18 - priceDelta) / 1e18, 
        10**14, 
        "AA amount after loss"
      );
      // Abs = 11 because min deposit for AA is 0.1 underlying (with depositAmountAARatio = 1)
      // and this can cause a price diff of up to 11 wei
      assertApproxEqAbs(priceAA, ONE_SCALE - (priceDelta / 10**(18-decimals)), 11, "AA price after loss");
    } else {
      assertApproxEqRel(resAA, amountAA, 1, "AA amount not changed");
    }

    uint256 resBB;
    if (depositAmountAARatio < FULL_ALLOC) {
      resBB = idleCDO.withdrawBB(0);
      assertApproxEqRel(
        resBB, 
        (amountBB * (1e18 - priceDelta)) / 1e18, 
        10**14,
        "BB amount after loss"
      );
      assertApproxEqAbs(priceBB, ONE_SCALE - (priceDelta / 10**(18-decimals)), 11, "BB price after loss");
    } else {
      assertApproxEqRel(resBB, amountBB, 1, "BB amount not changed");
    }

    assertApproxEqAbs(IERC20(AAtranche).balanceOf(address(this)), 0, 1, "AAtranche bal");
    assertApproxEqAbs(IERC20(BBtranche).balanceOf(address(this)), 0, 1, "BBtranche bal");
    assertLe(underlying.balanceOf(address(this)), initialBal, "underlying bal increased");
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
    _cdoHarvest(true);

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

    assertApproxEqAbs(idleCDO.priceAA(), preAAPrice, 2, "AA price not updated until new interaction");
    assertApproxEqAbs(idleCDO.priceBB(), preBBPrice, 2, "BB price not updated until new interaction");
    assertApproxEqAbs(idleCDO.unclaimedFees(), unclaimedFees, 0, "Fees did not increase");
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
      100 * 10**(18 - decimals) + 1, 
      'AA Deposit 1 is not correct'
    );
    uint256 priceAAPost = idleCDO.virtualPrice(address(AAtranche));
    _cdoHarvest(true);

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
}
