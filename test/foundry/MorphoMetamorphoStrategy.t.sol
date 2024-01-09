// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "morpho-urd/src/interfaces/IUniversalRewardsDistributor.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/morpho/MetaMorphoStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/interfaces/morpho/IUrdFactory.sol";
import "../../contracts/interfaces/morpho/IMerkle.sol";
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
  uint256 internal constant selectedBlock = 18963285;
  address internal constant MM_SNIPPETS = 0x7a928E2a07E093fb83db52E63DFB93c2F5FF42Ff;
  address internal MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal MORPHO = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
  address internal constant mmUSDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
  address internal constant mmWETH = 0x38989BBA00BDF8181F4082995b3DEAe96163aC5D;

  address internal constant defaultReward = DAI;
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
    bytes[] memory claimDatas = new bytes[](1);
    claimDatas[0] = abi.encode(reward, distributor, claimable, proof);
    extraData = abi.encode(claimDatas, 'bytes[]');

    // prepare extraDataSell to sell rewards on uni v3
    bytes[] memory _extraPath = new bytes[](1);

    if (defaultUnderlying == WETH) {
      _extraPath[0] = abi.encodePacked(DAI, uint24(3000), WETH);
    } else {
      _extraPath[0] = abi.encodePacked(DAI, uint24(100), USDC);
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
    tree[0] = keccak256(bytes.concat(keccak256(abi.encode(address(strategy), reward, claimable))));
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
    address[] memory rewardsTokens = new address[](1);
    rewardsTokens[0] = defaultReward;

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
    if (!includesMorhpo) {
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

  function testTransferRewards() external {
    MetaMorphoStrategy mmStrategy = MetaMorphoStrategy(address(strategy));
    uint256 amount = 100 * ONE_SCALE;
    
    // set rewards to defaultReward and MORPHO
    address[] memory _rewardTokens = new address[](2);
    _rewardTokens[0] = defaultReward;
    _rewardTokens[1] = MORPHO;
    vm.prank(owner);
    mmStrategy.setRewardTokens(_rewardTokens);

    // give defaultReward to strategy and then transfer
    deal(defaultReward, address(strategy), amount);
    mmStrategy.transferRewards();

    assertEq(IERC20Detailed(defaultReward).balanceOf(address(idleCDO)), amount, "idleCDO bal == amount");
    assertEq(IERC20Detailed(defaultReward).balanceOf(address(strategy)), 0, "strategy bal == 0");

    // Morpho is not transferred
    deal(MORPHO, address(strategy), amount);
    mmStrategy.transferRewards();
    assertEq(IERC20Detailed(MORPHO).balanceOf(address(idleCDO)), 0, "morpho bal cdo == 0");
    assertEq(IERC20Detailed(MORPHO).balanceOf(address(strategy)), amount, "morpho bal strategy != 0");

    // Morpho is now transferrable
    vm.prank(owner);
    mmStrategy.setMorphoTransferable(true);
    mmStrategy.transferRewards();
    assertEq(IERC20Detailed(MORPHO).balanceOf(address(idleCDO)), amount, "morpho bal strategy == 0");
    assertEq(IERC20Detailed(MORPHO).balanceOf(address(strategy)), 0, "morpho bal cdo != 0");
  }

  function _isGoerli() internal pure returns (bool) {
    return keccak256(abi.encode(selectedNetwork)) == keccak256(abi.encode("goerli"));
  }
}
