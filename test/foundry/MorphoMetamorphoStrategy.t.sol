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
  string internal constant selectedNetwork = "goerli";
  uint256 internal constant selectedBlock = 10092750;
  address internal constant USDC = 0x62bD2A599664D421132d7C54AB4DbE3233f4f0Ae;
  address internal constant DAI = 0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844;
  address internal constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
  address internal constant mmUSDC = 0x4BC8E2c58C4210098D3B16b24E2a1Ec64e3bFf22;
  address internal constant mmWETH = 0x7cE27FC617e12C937dA933A65d1F40E3191a370e;
  address internal constant MORPHO_BLUE = 0x64c7044050Ba0431252df24fEd4d9635a275CB41;
  address internal MORPHO = makeAddr('MORPHO');

  address internal constant defaultReward = DAI;
  address internal constant defaultUnderlying = WETH;
  address internal constant defaultStrategyToken = mmWETH;

  address internal distributorOwner = makeAddr('distributorOwner');

  IMetamorphoSnippets internal mmSnippets;
  IUrdFactory internal urdFactory;
  IMerkle internal merkle;
  IUniversalRewardsDistributor internal distributor;

  function setUp() public override {
    // do not use _selectFork otherwise URD setup is wrong and needs to be done before super.setUp()
    vm.createSelectFork(selectedNetwork, 10092750);

    // setup URD
    // deployCode is used instead of 'new' to avoid compile issues with multiple solidity versions
    urdFactory = IUrdFactory(deployCode("UrdFactory.sol"));
    merkle = IMerkle(deployCode("Merkle.sol"));
    distributor = urdFactory.createUrd(distributorOwner, 0, bytes32(0), hex"", hex"");


    // TODO
    // mmSnippets = deployCode("MetamorphoSnippets.sol");



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
    _extraPath[0] = abi.encodePacked(DAI, uint24(3000), WETH);
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
        address(mmSnippets),
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
      mmUSDC,
      address(underlying),
      owner,
      address(mmSnippets),
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
    string memory noStkIDLENetwork = "goerli";
    if (keccak256(abi.encode(selectedNetwork)) == keccak256(abi.encode(noStkIDLENetwork))) {
      return;
    }

    super._testMinStkIDLEBalanceInternal();
  }
}
