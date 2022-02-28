require("hardhat/config");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const addresses = require("../../../lib/addresses");
const stkAAVEjson = require("../../../artifacts/contracts/interfaces/IStakedAave.sol/IStakedAave.json");
const { expect } = require("chai");
const { FakeContract, smock } = require("@defi-wonderland/smock");
const erc20 = require("../../../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");

require("chai").use(smock.matchers);

const BN = (n) => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const MAX_UINT = BN(
  "115792089237316195423570985008687907853269984665640564039457584007913129639935"
);

const AMOUNT_TO_TRANSFER = BN("10000").mul(ONE_TOKEN(18));
const AMOUNT_TO_TEST = BN("1").mul(ONE_TOKEN(18));

const mUSD_ADDRESS = "0xe2f2a5C287993345a840Db3B0845fbC70f5935a5";

const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

const dai_whale = "0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0";

describe.only("IdleMStable Strategy Wrapper", function () {
  before(async () => {
    await hre.ethers.provider.send("hardhat_setBalance", [dai_whale, '0xffffffffffffffff']);
    await ethers.provider.send("hardhat_impersonateAccount", [dai_whale]);
  });

  beforeEach(async () => {
    // deploy contracts
    addr0 = addresses.addr0;
    signers = await ethers.getSigners();
    owner = signers[0];
    AABuyer = signers[1];
    AABuyerAddr = AABuyer.address;
    BBBuyer = signers[2];
    BBBuyerAddr = BBBuyer.address;
    AABuyer2 = signers[3];
    AABuyer2Addr = AABuyer2.address;
    BBBuyer2 = signers[4];
    BBBuyer2Addr = BBBuyer2.address;
    Random = signers[5];
    RandomAddr = Random.address;
    Random2 = signers[6];
    Random2Addr = Random2.address;
    stkAAVEAddr = addresses.IdleTokens.mainnet.stkAAVE;

    dai_signer = await ethers.getSigner(dai_whale);
    DAI = await ethers.getContractAt(erc20.abi, DAIAddress);
    await DAI.connect(dai_signer).transfer(
      AABuyer.address,
      AMOUNT_TO_TRANSFER.mul(10)
    );
    await DAI.connect(dai_signer).transfer(
      BBBuyer.address,
      AMOUNT_TO_TRANSFER.mul(10)
    );
    one = ONE_TOKEN(18);
    const IdleCDOTranche = await ethers.getContractFactory("IdleCDOTranche");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const MockIdleToken = await ethers.getContractFactory("MockIdleToken");
    const MockUniRouter = await ethers.getContractFactory("MockUniRouter");

    uniRouter = await MockUniRouter.deploy();
    await uniRouter.deployed();

    weth = await MockERC20.deploy("WETH", "WETH");
    await weth.deployed();

    // data forked from mainnet
    underlying = await ethers.getContractAt(erc20.abi, mUSD_ADDRESS);

    incentiveToken = await MockERC20.deploy("IDLE", "IDLE");
    await incentiveToken.deployed();
    incentiveTokens = [incentiveToken.address];

    idleToken = await MockIdleToken.deploy(underlying.address);
    await idleToken.deployed();
    idleToken2 = await MockIdleToken.deploy(underlying.address);
    await idleToken2.deployed();

    strategy = await helpers.deployUpgradableContract(
      "IdleStrategy",
      [idleToken.address, owner.address],
      owner
    );
    strategy2 = await helpers.deployUpgradableContract(
      "IdleStrategy",
      [idleToken2.address, owner.address],
      owner
    );
    idleCDO = await helpers.deployUpgradableContract(
      "EnhancedIdleCDO",
      [
        BN("1000000").mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN("20000"), // apr split: 20% interest to AA and 80% BB
        BN("50000"), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens,
      ],
      owner
    );

    await idleCDO.setWethForTest(weth.address);
    await idleCDO.setUniRouterForTest(uniRouter.address);

    AA = await ethers.getContractAt(
      "IdleCDOTranche",
      await idleCDO.AATranche()
    );
    BB = await ethers.getContractAt(
      "IdleCDOTranche",
      await idleCDO.BBTranche()
    );

    const stakingRewardsParams = [
      incentiveTokens,
      owner.address, // owner / guardian
      idleCDO.address,
      owner.address, // recovery address
      10, // cooling period
    ];
    stakingRewardsAA = await helpers.deployUpgradableContract(
      "IdleCDOTrancheRewards",
      [AA.address, ...stakingRewardsParams],
      owner
    );
    stakingRewardsBB = await helpers.deployUpgradableContract(
      "IdleCDOTrancheRewards",
      [BB.address, ...stakingRewardsParams],
      owner
    );
    await idleCDO.setStakingRewards(
      stakingRewardsAA.address,
      stakingRewardsBB.address
    );

    await idleCDO.setUnlentPerc(BN("0"));
    await idleCDO.setIsStkAAVEActive(false);

    // set IdleToken mocked params
    await idleToken.setTokenPriceWithFee(BN(10 ** 18));
    // set IdleToken2 mocked params
    await idleToken2.setTokenPriceWithFee(BN(2 * 10 ** 18));

    let idleMStableStrategyWrapperFactory = await ethers.getContractFactory(
      "IdleMStableStrategyWrapper"
    );
    idleMStableStrategyWrapper = await idleMStableStrategyWrapperFactory.deploy(
      mUSD_ADDRESS,
      idleCDO.address
    );
  });

  it("Deposit with with AA token", async () => {
    let AATrancheTokenAddress = await idleCDO.AATranche();
    let aaTokenContract = await ethers.getContractAt(
      erc20.abi,
      AATrancheTokenAddress
    );
    let aaTokenBalanceBefore = await aaTokenContract.balanceOf(AABuyer.address);
    await DAI.connect(AABuyer).approve(
      idleMStableStrategyWrapper.address,
      AMOUNT_TO_TEST
    );
    await idleMStableStrategyWrapper
      .connect(AABuyer)
      .depositAAWithToken(DAI.address, AMOUNT_TO_TEST, "1");
    let aaTokenBalanceAfter = await aaTokenContract.balanceOf(AABuyer.address);
    expect(aaTokenBalanceAfter.sub(aaTokenBalanceBefore)).gt(0);
  });

  it("Deposit with BB Token", async () => {
    let BBTrancheTokenAddress = await idleCDO.BBTranche();
    let bbTokenContract = await ethers.getContractAt(
      erc20.abi,
      BBTrancheTokenAddress
    );
    let bbTokenBalanceBefore = await bbTokenContract.balanceOf(BBBuyer.address);
    await DAI.connect(BBBuyer).approve(
      idleMStableStrategyWrapper.address,
      AMOUNT_TO_TEST
    );
    await idleMStableStrategyWrapper
      .connect(BBBuyer)
      .depositBBWithToken(DAI.address, AMOUNT_TO_TEST, "1");
    let bbTokenBalanceAfter = await bbTokenContract.balanceOf(BBBuyer.address);
    expect(bbTokenBalanceAfter.sub(bbTokenBalanceBefore)).gt(0);
  });

  it("Withdraw AA Token", async () => {
    let AATrancheTokenAddress = await idleCDO.AATranche();
    let aaTokenContract = await ethers.getContractAt(
      erc20.abi,
      AATrancheTokenAddress
    );
    let aaTokenBalanceBefore = await aaTokenContract.balanceOf(AABuyer.address);
    await DAI.connect(AABuyer).approve(
      idleMStableStrategyWrapper.address,
      AMOUNT_TO_TEST
    );
    await idleMStableStrategyWrapper
      .connect(AABuyer)
      .depositAAWithToken(DAI.address, AMOUNT_TO_TEST, "1");
    let aaTokenBalanceAfter = await aaTokenContract.balanceOf(AABuyer.address);

    let aaTokensReceived = aaTokenBalanceAfter.sub(aaTokenBalanceBefore);

    let daiBalanceBefore = await DAI.balanceOf(AABuyer.address);
    await aaTokenContract
      .connect(AABuyer)
      .approve(idleMStableStrategyWrapper.address, aaTokensReceived);
    await idleMStableStrategyWrapper
      .connect(AABuyer)
      .withdrawTokenViaBurningAA(DAI.address, aaTokensReceived, "1");
    let daiBalanceAfter = await DAI.balanceOf(AABuyer.address);
    expect(daiBalanceAfter.sub(daiBalanceBefore)).gt(0);
  });

  it("Withdraw BB Token", async () => {
    let BBTrancheTokenAddress = await idleCDO.BBTranche();
    let bbTokenContract = await ethers.getContractAt(
      erc20.abi,
      BBTrancheTokenAddress
    );
    let bbTokenBalanceBefore = await bbTokenContract.balanceOf(BBBuyer.address);
    await DAI.connect(BBBuyer).approve(
      idleMStableStrategyWrapper.address,
      AMOUNT_TO_TEST
    );
    await idleMStableStrategyWrapper
      .connect(BBBuyer)
      .depositBBWithToken(DAI.address, AMOUNT_TO_TEST, "1");
    let bbTokenBalanceAfter = await bbTokenContract.balanceOf(BBBuyer.address);

    let bbTokensReceived = bbTokenBalanceAfter.sub(bbTokenBalanceBefore);

    let daiBalanceBefore = await DAI.balanceOf(BBBuyer.address);
    await bbTokenContract
      .connect(BBBuyer)
      .approve(idleMStableStrategyWrapper.address, bbTokensReceived);
    await idleMStableStrategyWrapper
      .connect(BBBuyer)
      .withdrawTokenViaBurningBB(DAI.address, bbTokensReceived, "1");
    let daiBalanceAfter = await DAI.balanceOf(BBBuyer.address);
    expect(daiBalanceAfter.sub(daiBalanceBefore)).gt(0);
  });
});