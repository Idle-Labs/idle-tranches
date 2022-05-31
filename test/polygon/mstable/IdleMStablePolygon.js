require("hardhat/config");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const erc20 = require("../../../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const vaultAbi = require("../../../artifacts/contracts/polygon/interfaces/mstable/IVaultPolygon.sol/IVaultPolygon.json").abi;
const masset = require("../../../artifacts/contracts/interfaces/IMAsset.sol/IMAsset.json");
const savingsManagerAbi = require("../../../artifacts/contracts/interfaces/ISavingsManager.sol/ISavingsManager.json").abi;
const idleMstableStrategyAbi =
  require("../../../artifacts/contracts/polygon/strategies/mstable/IdleMStableStrategyPolygon.sol/IdleMStableStrategyPolygon.json").abi;
const rewardDistributorAbi =
  require("../../../artifacts/contracts/polygon/interfaces/mstable/IL2EmissionController.sol/IL2EmissionController.json").abi;

const addresses = require("../../../utils/addresses");
const { expect } = require("chai");
const { FakeContract, smock } = require("@defi-wonderland/smock");
const { ethers } = require("hardhat");
const { isAddress } = require("@ethersproject/address");

require("chai").use(smock.matchers);

const waitBlocks = async (n) => {
  console.log(`mining ${n} blocks...`);
  for (var i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine");
  }
};

const BN = (n) => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const MAX_UINT = BN("115792089237316195423570985008687907853269984665640564039457584007913129639935");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const uniswapV2Factory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
const uniswapV2RouterV2 = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

const imUSD_ADDRESS = "0x5290Ad3d83476CA6A2b178Cd9727eE1EF72432af";
const mUSD_ADDRESS = "0xE840B73E5287865EEc17d250bFb1536704B43B21";
const META_ADDESS = "0xF501dd45a1198C2E1b5aEF5314A68B9006D842E0";
const VAULT_ADDRESS = "0x32aBa856Dc5fFd5A56Bcd182b13380e5C855aa29";

const wrappedETH = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const USDTAddress = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const USDCAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const DAIAddress = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063";

const dai_whale = "0x21dD24Ed8bA124077784e2b25604337bD4530f21";
const musd_whale = "0x21dD24Ed8bA124077784e2b25604337bD4530f21";

// const AMOUNT_TO_TRANSFER = BN("1000000000000000000");
const AMOUNT_TO_TRANSFER = BN("10000000000000000000").div(2); // 5

// const KEY_SAVINGS_MANAGER = "0x12fe936c77a1e196473c4314f3bed8eeac1d757b319abb85bdda70df35511bf1";
const savingsManagerAddress = "0x10bFcCae079f31c451033798a4Fd9D2c33Ea5487";

describe.only("IdleMStableStrategyPolygon", function () {
  let IdleMStableStrategy;

  let owner;
  let user;
  let proxyAdmin;
  let rewardDistributor;

  let imUSD;
  let mUSD;
  let DAI;
  let meta;
  let vault;
  let savingsManager;

  let musd_signer;
  let dai_signer;
  let musd_emission = "0xDcCb7a6567603Af223C090bE4b9C83ecED210f18";
  let rewardDistributorAddress = "0x82182ac492fef111fb458fce8f4228553ed59a19";
  let musd_emission_signer;

  let snapshotId;

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [musd_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [musd_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [dai_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [musd_emission]);
    await hre.ethers.provider.send("hardhat_setBalance", [dai_whale, "0xffffffffffffffff"]);
    await hre.ethers.provider.send("hardhat_setBalance", [musd_emission, "0xffffffffffffffff"]);

    musd_emission_signer = await ethers.getSigner(musd_emission);
    [owner, user, user2, , proxyAdmin] = await ethers.getSigners();
    let IdleMStableStrategyFactory = await ethers.getContractFactory("IdleMStableStrategyPolygon");
    let IdleMStableStrategyLogic = await IdleMStableStrategyFactory.deploy();
    let TransparentUpgradableProxyFactory = await ethers.getContractFactory("TransparentUpgradeableProxy");
    let TransparentUpgradableProxy = await TransparentUpgradableProxyFactory.deploy(
      IdleMStableStrategyLogic.address,
      proxyAdmin.address,
      "0x"
    );
    await TransparentUpgradableProxy.deployed();
    IdleMStableStrategy = await ethers.getContractAt(idleMstableStrategyAbi, TransparentUpgradableProxy.address);
    imUSD = await ethers.getContractAt(erc20.abi, imUSD_ADDRESS);
    mUSD = await ethers.getContractAt(erc20.abi, mUSD_ADDRESS);
    DAI = await ethers.getContractAt(erc20.abi, DAIAddress);
    meta = await ethers.getContractAt(erc20.abi, META_ADDESS);
    vault = await ethers.getContractAt(vaultAbi, VAULT_ADDRESS);

    musd_signer = await ethers.getSigner(musd_whale);
    dai_signer = await ethers.getSigner(dai_whale);

    console.log("musd balance", await mUSD.balanceOf(musd_signer.address));
    await mUSD.connect(musd_signer).transfer(user.address, AMOUNT_TO_TRANSFER.mul(BN(2)));
    await DAI.connect(dai_signer).transfer(user.address, AMOUNT_TO_TRANSFER);
    savingsManager = await ethers.getContractAt(savingsManagerAbi, savingsManagerAddress);
    rewardDistributor = await ethers.getContractAt(rewardDistributorAbi, rewardDistributorAddress);

    await IdleMStableStrategy.connect(owner).initialize(
      imUSD.address,
      mUSD.address,
      vault.address,
      uniswapV2RouterV2,
      [META_ADDESS, DAIAddress],
      owner.address
    );

    // assuming that user itself if the idle CDO.
    await IdleMStableStrategy.connect(owner).setWhitelistedCDO(user.address);
    await IdleMStableStrategy.connect(owner).setReleaseBlocksPeriod(100);
  });

  beforeEach(async () => {
    snapshotId = await hre.network.provider.request({
      method: "evm_snapshot",
      params: [],
    });
  });

  afterEach(async () => {
    await hre.network.provider.request({
      method: "evm_revert",
      params: [snapshotId],
    });
  });

  it("Check contract address IdleMStableAddress", async () => {
    expect(isAddress(IdleMStableStrategy.address)).to.eq(true);
  });

  it("Check existing contracts", async () => {
    expect(await imUSD.name()).to.eq("Interest bearing mStable USD (Polygon PoS)");
    expect(await mUSD.name()).to.eq("mUSD");
    expect(await meta.name()).to.eq("Meta (PoS)");

    expect(await IdleMStableStrategy.latestHarvestBlock()).eq(0);
    expect(await IdleMStableStrategy.totalLpTokensLocked()).eq(0);
  });

  it("Deposit AMOUNT in Idle Tranche", async () => {
    let totalSharesBefore = await IdleMStableStrategy.totalSupply();

    // approve tokens to idle-mstable-strategy
    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    let totalSharesAfters = await IdleMStableStrategy.totalSupply();

    // strategy should not have any mUSD left
    expect(await mUSD.balanceOf(IdleMStableStrategy.address)).to.eq(0);

    expect(totalSharesAfters.sub(totalSharesBefore)).gt(0);

    // check states in vault
    expect(await vault.balanceOf(IdleMStableStrategy.address)).gt(0);
  });

  it("Redeem Tokens: redeem", async () => {
    let strategySharesBefore = await IdleMStableStrategy.totalSupply();

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
    let strategySharesAfter = await IdleMStableStrategy.totalSupply();

    let sharesReceived = strategySharesAfter.sub(strategySharesBefore);
    expect(sharesReceived).gt(0);

    let redeemAmount = sharesReceived.div(10); // claim back a fraction of shares received

    const mUSDBalanceBefore = await mUSD.connect(user).balanceOf(user.address);
    await IdleMStableStrategy.connect(user).redeem(redeemAmount);
    const mUSDBalanceAfter = await mUSD.connect(user).balanceOf(user.address);
    // +- 0.01
    expect(mUSDBalanceAfter.sub(mUSDBalanceBefore)).closeTo(AMOUNT_TO_TRANSFER.div(10), BN(1e16), "Approximate check failed");
  });

  it("Redeem Rewards", async () => {
    const oneDayInSec = 86400;
    const releaseBlocksPeriod = await IdleMStableStrategy.releaseBlocksPeriod();

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    // send some rewards to the vault contract
    const amount = BN("1000").mul(ONE_TOKEN(18));
    await meta.connect(musd_emission_signer).transfer(VAULT_ADDRESS, amount);
    await rewardDistributor.connect(musd_emission_signer).distributeRewards([vault.address]);

    // check price
    const initialStaked = await IdleMStableStrategy.totalLpTokensStaked();
    const pricePre = await IdleMStableStrategy.price();
    let rawBalanceBefore = await vault.balanceOf(IdleMStableStrategy.address);
    let strategySharesBefore = await IdleMStableStrategy.totalSupply();

    const staticRes = await helpers.sudoStaticCall(owner.address, IdleMStableStrategy, "redeemRewards()", []);
    await IdleMStableStrategy.connect(owner)["redeemRewards()"](); // will get MTA token, convert to musd and deposit to vault

    let strategySharesAfter = await IdleMStableStrategy.totalSupply();
    let rawBalanceAfter = await vault.balanceOf(IdleMStableStrategy.address);
    const pricePost = await IdleMStableStrategy.price();

    // check that price is not changed
    expect(pricePost).eq(pricePre);
    // check that totalSupply is not changed after redeeming rewards
    expect(strategySharesAfter.sub(strategySharesBefore)).eq(0);
    // rewards sold have been staked
    expect(rawBalanceAfter.sub(rawBalanceBefore)).gt(0);

    await waitBlocks(BN(releaseBlocksPeriod).div(2));
    const pricePost2 = await IdleMStableStrategy.price();
    expect(pricePost2.sub(pricePost)).gt(0);

    await waitBlocks(BN(releaseBlocksPeriod).div(2).add(1));
    const pricePost3 = await IdleMStableStrategy.price();
    expect(pricePost3.sub(pricePost2)).gt(0);
    await waitBlocks(BN(1));
    // price is not increasing anymore as release period is over
    const pricePost4 = await IdleMStableStrategy.price();
    expect(pricePost4.sub(pricePost3)).eq(0);

    expect(await IdleMStableStrategy.latestHarvestBlock()).gt(0);
    const lockedRewards = await IdleMStableStrategy.totalLpTokensLocked();
    const totStaked = await IdleMStableStrategy.totalLpTokensStaked();
    expect(lockedRewards).gt(0);
    expect(totStaked.sub(initialStaked)).eq(lockedRewards);
    // check return value of redeemRewards call
    expect(staticRes.length).eq(2);
    expect(staticRes[0]).gt(0);
    expect(staticRes[1]).gte(0);
    // check that rewardLastRound is updated and > 0
    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
  });

  it("APR", async () => {
    // initial apr is 0
    let apr = await IdleMStableStrategy.getApr();
    expect(apr).eq(0);

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    apr = await IdleMStableStrategy.getApr();
    expect(apr).eq(0);
    await savingsManager.connect(user).collectAndStreamInterest(mUSD.address);
    // apr is updated only on deposit and redeem
    apr = await IdleMStableStrategy.getApr();
    expect(apr).eq(0);
    await network.provider.request({ method: "evm_increaseTime", params: [4 * 86400] });
    await network.provider.request({ method: "evm_mine", params: [] });

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    apr = await IdleMStableStrategy.getApr();
    expect(apr).gt(0);
    await network.provider.request({ method: "evm_increaseTime", params: [4 * 86400] });
    await network.provider.request({ method: "evm_mine", params: [] });

    await savingsManager.connect(user).collectAndStreamInterest(mUSD.address);
    expect(apr).eq(await IdleMStableStrategy.getApr());

    await IdleMStableStrategy.connect(user).redeem(BN(await IdleMStableStrategy.balanceOf(user.address)).div(2));
    await network.provider.request({ method: "evm_increaseTime", params: [4 * 86400] });
    await network.provider.request({ method: "evm_mine", params: [] });
    await savingsManager.connect(user).collectAndStreamInterest(mUSD.address);
    expect(apr).lt(await IdleMStableStrategy.getApr());
  });
});
