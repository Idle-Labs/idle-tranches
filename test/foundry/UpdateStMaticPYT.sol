// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../contracts/interfaces/IIdleCDOStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "../../contracts/IdleCDO.sol";
import "../../contracts/IdleCDOPoLidoVariant.sol";
import "../../contracts/interfaces/IProxyAdmin.sol";
import "../../contracts/interfaces/IStMatic.sol";
import "forge-std/Test.sol";

// @notice contract used to test the update of lido PYT to the new 
// IdleCDO implementation with the adaptive yield split strategy and referrals
contract TestUpdateStMaticPYT is Test {
  using stdStorage for StdStorage;
  event Referral(uint256 _amount, address _ref);

  uint256 internal constant FULL_ALLOC = 100000;
  uint256 internal constant MAINNET_CHIANID = 1;
  uint256 internal initialBal;
  uint256 internal decimals;
  uint256 internal ONE_SCALE;
  uint256 internal initialAAVirtual;
  uint256 internal initialBBVirtual;
  address[] internal rewards;
  address public owner;
  address public newImpl;
  bytes internal extraData;
  bytes internal extraDataSell;
  IdleCDO internal idleCDO;
  IERC20Detailed internal underlying;
  IERC20Detailed internal strategyToken;
  IdleCDOTranche internal AAtranche;
  IdleCDOTranche internal BBtranche;
  IIdleCDOStrategy internal strategy;
  IPoLidoNFT internal poLidoNFT;
  IStMATIC internal constant stMatic = IStMATIC(0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599);
  address public constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

  function _setUpParams() internal virtual {
    idleCDO = IdleCDO(0xF87ec7e1Ee467d7d78862089B92dd40497cBa5B8);
    // example with stMATIC, inherit this contract and override this method to test other
    // IdleCDO upgrades
    address MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // deploy new implementation or use an existing
    // implementation already deployed
    newImpl = address(new IdleCDOPoLidoVariant());
    bytes[] memory _extraPath = new bytes[](1);
    _extraPath[0] = abi.encodePacked(LDO, uint24(3000), WETH, uint24(3000), address(MATIC));
    extraDataSell = abi.encode(_extraPath);
    extraData = '0x';
  }

  function setUp() public virtual {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 16917511));

    _setUpParams();

    AAtranche = IdleCDOTranche(idleCDO.AATranche());
    BBtranche = IdleCDOTranche(idleCDO.BBTranche());
    // initial values pre-upgrade
    initialAAVirtual = idleCDO.virtualPrice(address(AAtranche));
    initialBBVirtual = idleCDO.virtualPrice(address(BBtranche));

    IProxyAdmin admin = IProxyAdmin(0x9438904ABC7d8944A6E2A89671fEf51C629af351);
    vm.prank(admin.owner());
    admin.upgrade(address(idleCDO), newImpl);

    // activate AYS and remove fees and unlet perc for easy testing
    vm.startPrank(idleCDO.owner());
    idleCDO.setUnlentPerc(0);
    idleCDO.setFee(0);
    vm.stopPrank();

    owner = idleCDO.owner();
    underlying = IERC20Detailed(idleCDO.token());
    decimals = underlying.decimals();
    ONE_SCALE = 10 ** decimals;
    strategy = IIdleCDOStrategy(idleCDO.strategy());
    strategyToken = IERC20Detailed(strategy.strategyToken());
    rewards = strategy.getRewardTokens();
    poLidoNFT = stMatic.poLidoNFT();
    // fund (deal cheatcode is not working directly for stETH apparently)
    initialBal = 1000000 * ONE_SCALE;

    deal(address(underlying), address(this), initialBal);
    underlying.approve(address(idleCDO), type(uint256).max);

    // label
    vm.label(address(idleCDO), "idleCDO");
    vm.label(address(AAtranche), "AAtranche");
    vm.label(address(BBtranche), "BBtranche");
    vm.label(address(strategy), "strategy");
    vm.label(address(underlying), "underlying");
    vm.label(address(strategyToken), "strategyToken");
  }

  function testInitialValue() external virtual {
    assertEq(idleCDO.token(), address(underlying));
    assertGe(idleCDO.virtualPrice(address(AAtranche)), initialAAVirtual);
    assertGe(idleCDO.virtualPrice(address(BBtranche)), initialBBVirtual);
  }

  function testDeposits() external virtual {
    uint256 amount = 10000 * ONE_SCALE;
    uint256 priceAA = idleCDO.virtualPrice(address(AAtranche));
    uint256 priceBB = idleCDO.virtualPrice(address(BBtranche));
    // AARatio 50%
    idleCDO.depositAA(amount);
    idleCDO.depositBB(amount);

    uint256 totAmount = amount * 2;

    assertEq(IERC20(AAtranche).balanceOf(address(this)), amount * 1e18 / priceAA, "AAtranche bal");
    assertEq(IERC20(BBtranche).balanceOf(address(this)), amount * 1e18 / priceBB, "BBtranche bal");
    assertEq(underlying.balanceOf(address(this)), initialBal - totAmount, "underlying bal");
    uint256 strategyPrice = strategy.price();

    // skip rewards and deposit underlyings to the strategy
    _cdoHarvest(true);

    // claim rewards
    _cdoHarvest(false);
    assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal after harvest");    

    // Skip 7 day forward to accrue interest
    skip(7 days);
    vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);

    assertGe(strategy.price(), strategyPrice, "strategy price");

    // virtualPrice should increase too
    assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
    assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
  }

  function testRedeems() external virtual {
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

  function testRedeemRewards() external virtual {
    // give LDO to idleCDO contract
    vm.prank(0x09F82Ccd6baE2AeBe46bA7dd2cf08d87355ac430);
    IERC20Detailed(LDO).transfer(address(idleCDO), 10000 * 1e18);

    // sell some rewards
    uint256 pricePre = idleCDO.virtualPrice(address(AAtranche));
    _cdoHarvest(false);

    uint256 pricePost = idleCDO.virtualPrice(address(AAtranche));
    assertGt(pricePost, pricePre, "virtual price increased");
  }

  function _cdoHarvest(bool _skipRewards) internal {
    uint256 numOfRewards = rewards.length;
    bool[] memory _skipFlags = new bool[](4);
    bool[] memory _skipReward = new bool[](numOfRewards);
    uint256[] memory _minAmount = new uint256[](numOfRewards);
    uint256[] memory _sellAmounts = new uint256[](numOfRewards);
    bytes[] memory _extraData = new bytes[](2);
    if(!_skipRewards){
      _extraData[0] = extraData;
      _extraData[1] = extraDataSell;
    }
    // skip fees distribution
    _skipFlags[3] = _skipRewards;

    vm.prank(idleCDO.rebalancer());
    idleCDO.harvest(_skipFlags, _skipReward, _minAmount, _sellAmounts, _extraData);

    // linearly release all sold rewards
    vm.roll(block.number + idleCDO.releaseBlocksPeriod() + 1); 
  }
  function _strategyReleaseBlocksPeriod() internal returns (uint256 releaseBlocksPeriod) {
    (bool success, bytes memory returnData) = address(strategy).staticcall(abi.encodeWithSignature("releaseBlocksPeriod()"));
    if (success){
      releaseBlocksPeriod = abi.decode(returnData, (uint32));
    } else {
      emit log("can't find releaseBlocksPeriod() on strategy");
      emit logs(returnData);
    }
  }

  function onERC721Received(
      address,
      address,
      uint256,
      bytes calldata
  ) external pure returns (bytes4) {
      return IERC721Receiver.onERC721Received.selector;
  }
}