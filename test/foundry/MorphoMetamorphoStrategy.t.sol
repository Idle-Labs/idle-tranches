// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "morpho-urd/src/interfaces/IUniversalRewardsDistributor.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/morpho/MetaMorphoStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/interfaces/morpho/IUrdFactory.sol";
import "../../contracts/interfaces/morpho/IMerkle.sol";
import "../../contracts/interfaces/morpho/IMorpho.sol";
import "../../contracts/interfaces/morpho/IMMVault.sol";
import "../../contracts/interfaces/morpho/IMetamorphoSnippets.sol";
import "../../contracts/interfaces/IWETH.sol";
import "./TestIdleCDOBase.sol";

contract TestMorphoMetamorphoStrategy is TestIdleCDOBase {
  using stdStorage for StdStorage;

  // These are goerli addresses!
  // string internal constant selectedNetwork = "goerli";
  // uint256 internal constant selectedBlock = 10279600;
  // address internal constant USDC = 0x62bD2A599664D421132d7C54AB4DbE3233f4f0Ae;
  // address internal constant DAI = 0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844;
  // address internal constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
  // address internal constant mmUSDC = 0x4BC8E2c58C4210098D3B16b24E2a1Ec64e3bFf22;
  // address internal constant mmWETH = 0x7cE27FC617e12C937dA933A65d1F40E3191a370e;
  // address internal constant MORPHO_BLUE = 0x64c7044050Ba0431252df24fEd4d9635a275CB41;
  // address internal constant MM_SNIPPETS = 0x594077C8Dab3b233761806EcE28A2cb62fd5d16e;
  // address internal MORPHO = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
  // mainnet
  string internal constant selectedNetwork = "mainnet";
  uint256 internal constant selectedBlock = 19225935;
  address internal constant MM_SNIPPETS = 0xDfd98F2FaB869B18aD4322B2c7B1227c576402c6;
  address internal MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
  address internal MORPHO = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
  address internal constant mmUSDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
  address internal constant mmWETH = 0x38989BBA00BDF8181F4082995b3DEAe96163aC5D;

  address internal constant defaultReward = WSTETH;
  address internal constant defaultUnderlying = WETH;
  address internal constant defaultStrategyToken = mmWETH;

  address internal distributorOwner = makeAddr('distributorOwner');

  IUrdFactory internal urdFactory;
  IMerkle internal merkle;
  IUniversalRewardsDistributor internal distributor;

  function setUp() public override {
    // do not use _selectFork otherwise URD setup is wrong and needs to be done before super.setUp()
    vm.createSelectFork(selectedNetwork, selectedBlock);

    // setup URD
    // deployCode is used instead of 'new' to avoid compile issues with multiple solidity versions
    // MetamorphoHelper is a contract that is used to compile Merkle and UrdFactory
    urdFactory = IUrdFactory(deployCode("UrdFactory.sol"));
    merkle = IMerkle(deployCode("Merkle.sol"));
    distributor = urdFactory.createUrd(distributorOwner, 0, bytes32(0), hex"", hex"");
    // deploy an ERC20 to be used as MORPHO (now transferable)
    deployCodeTo("ERC20.sol", abi.encode("MORPHO", "MORPHO", uint8(18)), MORPHO);

    super.setUp();
    
    // setup rewards
    address reward = strategy.getRewardTokens()[0];
    uint256 claimable = 1e18;
    bytes32[] memory tree = _setupRewards(reward, claimable);
    // give 1 rewards token to the distributor
    deal(reward, address(distributor), claimable * 2); // min 2 leaf needed
    bytes32[] memory proof = merkle.getProof(tree, 0);

    // prepare extraData to claim
    bytes[] memory claimDatas = new bytes[](2);
    claimDatas[0] = abi.encode(reward, distributor, claimable, proof);
    extraData = abi.encode(claimDatas, 'bytes[]');

    // prepare extraDataSell to sell rewards on uni v3
    bytes[] memory _extraPath = new bytes[](2);

    if (defaultUnderlying == WETH) {
      _extraPath[0] = abi.encodePacked(WSTETH, uint24(100), WETH);
    } else {
      _extraPath[0] = abi.encodePacked(WSTETH, uint24(100), WETH, uint24(500), USDC);
    }
    extraDataSell = abi.encode(_extraPath);

    // uniswap addresses are the same on all networks but we need to change WETH
    stdstore.target(address(idleCDO)).sig(idleCDO.weth.selector).checked_write(WETH);
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

  function _setupRewards(address reward, uint256 claimable) internal returns (bytes32[] memory tree) {
    tree = new bytes32[](2);
    tree[0] = keccak256(bytes.concat(keccak256(abi.encode(address(idleCDO), reward, claimable))));
    tree[1] = keccak256(bytes.concat(keccak256(abi.encode(makeAddr('deadrandom'), reward, claimable))));

    bytes32 root = merkle.getRoot(tree);
    vm.prank(distributorOwner);
    distributor.setRoot(root, bytes32(0));
  }

  function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
    _underlying = defaultUnderlying;
    strategyToken = IERC20Detailed(defaultStrategyToken);
    strategy = new MetaMorphoStrategy();

    _strategy = address(strategy);
    address[] memory rewardsTokens = new address[](2);
    rewardsTokens[0] = defaultReward;
    rewardsTokens[1] = MORPHO;

    // initialize
    stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
    MetaMorphoStrategy(_strategy).initialize(
        address(strategyToken),
        _underlying,
        _owner,
        MM_SNIPPETS,
        rewardsTokens
    );

    vm.label(address(strategyToken), "Vault");
    vm.label(_underlying, "Underlying");
    vm.label(address(distributor), "URD");
  }

  function _postDeploy(address _cdo, address _owner) internal override {
    vm.startPrank(_owner);
    MetaMorphoStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    vm.stopPrank();
  }

  function testCantReinitialize() external override {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    MetaMorphoStrategy(address(strategy)).initialize(
      defaultStrategyToken,
      address(underlying),
      owner,
      MM_SNIPPETS,
      new address[](0)
    );
  }

  function testRedeemRewards() external virtual override {
    super._testRedeemRewardsInternal();

    // if rewards includes MORPHO, then we check MORPHO balance
    bool includesMorhpo = false;
    for (uint256 i = 0; i < rewards.length; i++) {
      if (rewards[i] == MORPHO) {
        includesMorhpo = true;
        break;
      }
    }
    if (!includesMorhpo || !MetaMorphoStrategy(address(idleCDO.strategy())).morphoTransferable()) {
      return;
    }

    // NOTE: right now MORPHO is not transferable
    assertGt(IERC20Detailed(MORPHO).balanceOf(address(idleCDO)), 0, "morpho bal > 0");
  }

  // Not applicable in goearli
  function testMinStkIDLEBalance() external override {
    // if we are in goerli, we skip this test
    if (_isGoerli()) {
      return;
    }

    super._testMinStkIDLEBalanceInternal();
  }

  function testRewardsApr(uint256 firstDeposit, uint256 secondDeposit) external virtual {
    // accrueInterest on all markets before
    _blueAccrueInterest();

    firstDeposit = bound(firstDeposit, ONE_SCALE / 100, 10_000 * ONE_SCALE);
    secondDeposit = bound(secondDeposit, ONE_SCALE / 100, 10_000 * ONE_SCALE);
  
    _setupRewardsData();
    MetaMorphoStrategy strat = MetaMorphoStrategy(address(idleCDO.strategy()));

    // first deposit and harvest to get strategy tokens
    uint256 simulated1 = strat.getRewardsApr(firstDeposit, 0);
    idleCDO.depositAA(firstDeposit);
    _cdoHarvest(true);
    uint256 rewardsApr = strat.getRewardsApr(0, 0);
    assertApproxEqRel(simulated1, rewardsApr, 1e13, "simulated apr is not equal to real apr after first deposit");
    assertGt(rewardsApr / 1e17, 0, "apr is == 0 and/or not with 18 decimals");

    // Simulate a second deposit
    uint256 simulated2 = strat.getRewardsApr(secondDeposit, 0);
    // second deposit and harvest
    idleCDO.depositAA(secondDeposit);
    _cdoHarvest(true);
    uint256 rewardsAprAfterDeposits = strat.getRewardsApr(0, 0);
    assertGt(rewardsApr, rewardsAprAfterDeposits, "apr is not decreasing when amount is increasing");
    // 1e13 -> maxDelta 0.001%
    assertApproxEqRel(simulated2, rewardsAprAfterDeposits, 1e13, "simulated apr is not equal to real apr");

    // Simulate a redeem of all
    uint256 simulatedRedeem = strat.getRewardsApr(0, firstDeposit + secondDeposit);
    // withdraw all
    idleCDO.withdrawAA(0);
    uint256 rewardsAprFinal = strat.getRewardsApr(0, 0);
    // 1e13 -> maxDelta 0.001%
    assertApproxEqRel(simulatedRedeem, rewardsAprFinal, 1e13, "simulated apr on redeem is not equal to real apr");
  }

  function _blueAccrueInterest() internal {
    IMMVault vault = IMMVault(defaultStrategyToken);
    IMorpho blue = IMorpho(MORPHO_BLUE);
    for (uint256 i = 0; i < vault.withdrawQueueLength(); i++) {
      blue.accrueInterest(blue.idToMarketParams(vault.withdrawQueue(i)));
    }
  }

  function _getUnlentLiquidity() internal view returns (uint256 unlentLiquidity) {
    // find available liquidity of the unlent market
    IMMVault vault = IMMVault(defaultStrategyToken);
    IMorpho blue = IMorpho(MORPHO_BLUE);
    IMorpho.Market memory unlentMarket;
    IMorpho.Position memory pos;
    bytes32 unlentMarketId;
    uint256 availableLiquidity;
    uint256 vaultAssets;
    for (uint256 i = 0; i < vault.withdrawQueueLength(); i++) {
      unlentMarketId = vault.withdrawQueue(i);
      IMorpho.MarketParams memory marketParams = blue.idToMarketParams(unlentMarketId);
      if (marketParams.collateralToken == address(0)) {
        pos = blue.position(unlentMarketId, address(vault));
        unlentMarket = blue.market(unlentMarketId);
        availableLiquidity = unlentMarket.totalSupplyAssets - unlentMarket.totalBorrowAssets;
        vaultAssets = pos.supplyShares * unlentMarket.totalSupplyAssets / unlentMarket.totalSupplyShares;
        // get max withdrawable amount for this market (min between available liquidity and vault assets)
        unlentLiquidity = vaultAssets > availableLiquidity ? availableLiquidity : vaultAssets;
        break; 
      }
    }
  }

  function testGetAprWithLiquidityChange(uint8 add, uint8 sub) external {
    _setupRewardsData();
    uint256 scaledAdd = uint256(add) * ONE_SCALE;
    uint256 scaledSub = uint256(sub) * ONE_SCALE;
    MetaMorphoStrategy strat = MetaMorphoStrategy(address(idleCDO.strategy()));
    assertEq(strat.getAprWithLiquidityChange(0, 0), strat.getApr(), "getApr and getAprWithLiquidityChange(0, 0) are not equal");

    uint256 baseApr = IMetamorphoSnippets(MM_SNIPPETS).supplyAPRVault(defaultStrategyToken, scaledAdd, scaledSub) * 365 days * 100;
    assertEq(strat.getAprWithLiquidityChange(scaledAdd, scaledSub), baseApr + strat.getRewardsApr(scaledAdd, scaledSub), "getAprWithLiquidityChange is not correct");
  }

  function _setupRewardsData() internal {
    address sender = 0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143;
    // MORPHO reward data
    address morphoURD = 0x678dDC1d07eaa166521325394cDEb1E4c086DF43;
    address morphoReward = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
    bytes32 morphoMarketUSDC = 0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc;
    bytes32 morphoMarketWETH = 0xc54d7acf14de29e0e5527cabd7a576506870346a78a11a6762e2cca66322ec41;
    // WSTETH reward data
    address wstethURD = 0x2EfD4625d0c149EbADf118EC5446c6de24d916A4;
    address wstethReward = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    bytes32 wstethMarketUSDC = 0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc;
    bytes32 wstethMarketWETH = 0xc54d7acf14de29e0e5527cabd7a576506870346a78a11a6762e2cca66322ec41;
    bytes memory wstethUSDCPath = abi.encodePacked(WSTETH, uint24(100), WETH, uint24(500), USDC);
    bytes memory wstethWETHPath = abi.encodePacked(WSTETH, uint24(100), WETH);

    MetaMorphoStrategy strat = MetaMorphoStrategy(address(idleCDO.strategy()));
  
    // set reward data in strategy
    vm.startPrank(strat.owner());
    strat.setRewardData(0, sender, morphoURD, morphoReward, morphoMarketUSDC, '');
    strat.setRewardData(1, sender, morphoURD, morphoReward, morphoMarketWETH, '');
    strat.setRewardData(0, sender, wstethURD, wstethReward, wstethMarketUSDC, wstethUSDCPath);
    strat.setRewardData(1, sender, wstethURD, wstethReward, wstethMarketWETH, wstethWETHPath);
    vm.stopPrank();

    // set unlentPerc to 0
    vm.prank(idleCDO.owner());
    idleCDO.setUnlentPerc(0);
  }

  function _isGoerli() internal pure returns (bool) {
    return keccak256(abi.encode(selectedNetwork)) == keccak256(abi.encode("goerli"));
  }
}
