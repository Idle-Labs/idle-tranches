// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "./TestIdleCDOLossMgmt.sol";

import {GearboxStrategy} from "../../contracts/strategies/gearbox/GearboxStrategy.sol";
import {IERC20Detailed} from "../../contracts/interfaces/IERC20Detailed.sol";
import {DToken} from "../../contracts/interfaces/gearbox/DToken.sol";
import {IERC4626Upgradeable} from "../../contracts/interfaces/IERC4626Upgradeable.sol";
import {IWETH} from "../../contracts/interfaces/IWETH.sol";
import {IdleCDOGearboxVariant} from "../../contracts/IdleCDOGearboxVariant.sol";

contract TestGearboxStrategyWETH is TestIdleCDOLossMgmt {
  using stdStorage for StdStorage;

  uint256 internal constant ONE_TRANCHE = 1e18;
  address internal constant GEAR = 0xBa3335588D9403515223F109EdC4eB7269a9Ab5D;

  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant dWETH = 0xda0002859B2d05F66a753d8241fCDE8623f26F4f;
  address internal constant sdWETH = 0x0418fEB7d0B25C411EB77cD654305d29FcbFf685;
  bytes internal constant gearWETHPath = abi.encodePacked(GEAR, uint24(10000), WETH);

  address internal defaultUnderlying = WETH;
  address internal defaultStaking = sdWETH;
  bytes internal defaultUniv3Path = gearWETHPath;
  IERC4626Upgradeable internal defaultVault = IERC4626Upgradeable(dWETH);

  function _selectFork() public override {
    vm.createSelectFork("mainnet", 19659800);
  }

  function _deployCDO() internal override returns (IdleCDO _cdo) {
    _cdo = new IdleCDOGearboxVariant();
  }

  function _deployStrategy(address _owner)
    internal
    override
    returns (address _strategy, address _underlying)
  {
    _underlying = defaultUnderlying;
    // strategyToken here is the staked strategy token (sdToken)
    strategyToken = IERC20Detailed(defaultStaking);
    strategy = new GearboxStrategy();

    _strategy = address(strategy);

    // initialize
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    GearboxStrategy(_strategy).initialize(address(defaultVault), defaultUnderlying, _owner, defaultStaking, defaultUniv3Path);
  }

  function _fundTokens() internal override {
    if (defaultUnderlying == WETH) {
      // deal ETH to this contract
      uint256 amount = 1000000 * ONE_SCALE;
      vm.deal(address(this), amount);
      // set initialBal storage, we add eventual ETH sent to this contract
      initialBal = underlying.balanceOf(address(this)) + amount;
      // Wrap ETH into WETH
      IWETH(WETH).deposit{value: address(this).balance}();
    } else {
      super._fundTokens();
    }
  }

  function _pokeLendingProtocol() internal override {
    // do a deposit to update lastQuotaRevenueUpdate and lastBaseInterestUpdate
    DToken dToken = DToken(address(defaultVault));
    address user = makeAddr('rando');
    uint256 amount = 1e18;
    if (defaultUnderlying == WETH) {
      vm.deal(user, amount);
      vm.prank(user);
      IWETH(WETH).deposit{value: amount}();
    } else {
      deal(defaultUnderlying, user, amount, true);
    }
    vm.startPrank(user);
    IERC20Detailed(defaultUnderlying).approve(address(defaultVault), amount);
    IERC4626Upgradeable(address(dToken)).deposit(amount, user);
    vm.stopPrank();
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.prank(_owner);
    GearboxStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));

    _pokeLendingProtocol();

    bytes[] memory _extraPath = new bytes[](1);
    _extraPath[0] = defaultUniv3Path;
    extraDataSell = abi.encode(_extraPath);
    extraData = '0x';
  }

  function _donateToken(address to, uint256 amount) internal override {
    if (defaultUnderlying == WETH) {
      address maker = 0x2F0b23f53734252Bda2277357e97e1517d6B042A;
      uint256 bal = underlying.balanceOf(maker);
      require(bal > amount, "doesn't have enough tokens");
      vm.prank(maker);
      underlying.transfer(to, amount);
    } else {
      deal(defaultUnderlying, to, amount);
    }
  }

  function _createLoss(uint256 _loss) internal override {
    DToken dToken = DToken(address(defaultVault));

    uint256 totalAssets = dToken.expectedLiquidity();
    uint256 loss = totalAssets * _loss / FULL_ALLOC;
    // set _expectedLiquidityLU storage variable (slot 13, found with `cast storage`) to simulate a loss
    vm.store(address(defaultVault), bytes32(uint256(13)), bytes32(uint256(totalAssets - loss)));

    // update vault price
    _pokeLendingProtocol();
  }

  function testCantReinitialize() external override {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    GearboxStrategy(address(strategy)).initialize(address(1), address(2), owner, defaultStaking, defaultUniv3Path);
  }

  function testMultipleDeposits() external {
    uint256 _val = 100 * ONE_SCALE;
    uint256 scaledVal = _val * 10**(18 - decimals);
    deal(address(underlying), address(this), _val * 100_000_000);

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
    uint256 priceAAPostHarvest = idleCDO.virtualPrice(address(AAtranche));

    // now deposit again
    address user1 = makeAddr('user1');
    _depositWithUser(user1, _val, true);
    uint256 priceAAPost2 = idleCDO.virtualPrice(address(AAtranche));

    if (decimals < 18) {
      assertApproxEqAbs(
        IERC20Detailed(address(AAtranche)).balanceOf(user1), 
        // This is used to better account for slight differences in prices when using low decimals
        scaledVal * ONE_SCALE / priceAAPostHarvest, 
        1,
        'AA Deposit 2 is not correct'
      );
    } else {
      assertApproxEqAbs(
        IERC20Detailed(address(AAtranche)).balanceOf(user1), 
        scaledVal, 
        // 1 wei less for each unit of underlying, scaled to 18 decimals
        // check _mintShares for more info
        100 * 10**(18 - decimals) + 1, 
        'AA Deposit 2 is not correct'
      );
    }

    assertApproxEqAbs(priceAAPost, priceAAPre, 1, 'AA price is not the same after deposit 1');
    assertApproxEqAbs(priceAAPost, priceAAPostHarvest, 1, 'AA price is not the same after harvest');
    assertApproxEqAbs(priceAAPost2, priceAAPost, 1, 'AA price is not the same after deposit 2');
  }
}
