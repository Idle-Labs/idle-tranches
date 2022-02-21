require("hardhat/config");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const erc20 = require("../../../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const vaultAbi = require("../../../artifacts/contracts/interfaces/IVault.sol/IVault.json").abi;
const masset = require("../../../artifacts/contracts/interfaces/IMAsset.sol/IMAsset.json");
const savingsManagerAbi = require("../../../artifacts/contracts/interfaces/ISavingsManager.sol/ISavingsManager.json").abi;
const idleMstableStrategyAbi = require("../../../artifacts/contracts/strategies/mstable/IdleMStableStrategy.sol/IdleMStableStrategy.json").abi;

const addresses = require("../../../lib/addresses");
const { expect } = require("chai");
const { FakeContract, smock } = require("@defi-wonderland/smock");
const { ethers } = require("hardhat");
const { isAddress } = require("@ethersproject/address");

require("chai").use(smock.matchers);


const waitBlocks = async (n) => {
  console.log(`mining ${n} blocks...`);
  for (var i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine");
  };
}

const BN = (n) => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const MAX_UINT = BN("115792089237316195423570985008687907853269984665640564039457584007913129639935");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const uniswapV2RouterV2 = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

const imUSD_ADDRESS = "0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19";
const mUSD_ADDRESS = "0xe2f2a5C287993345a840Db3B0845fbC70f5935a5";
const META_ADDESS = "0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2";
const VAULT_ADDRESS = "0x78BefCa7de27d07DC6e71da295Cc2946681A6c7B";

const wrappedETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const USDTAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const USDCAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

const dai_whale = "0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0";
const musd_whale = "0xe008464f754e85e37bca41cce3fbd49340950b29";

// const AMOUNT_TO_TRANSFER = BN("1000000000000000000");
const AMOUNT_TO_TRANSFER = BN("10000000000000000000000"); // 10k

// const KEY_SAVINGS_MANAGER = "0x12fe936c77a1e196473c4314f3bed8eeac1d757b319abb85bdda70df35511bf1";
const savingsManagerAddress = "0xBC3B550E0349D74bF5148D86114A48C3B4Aa856F";

describe("IdleMStableStrategy", function () {
  let IdleMStableStrategy;

  let owner;
  let user;
  let proxyAdmin;

  let imUSD;
  let mUSD;
  let DAI;
  let meta;
  let vault;
  let savingsManager;

  let musd_signer;
  let dai_signer;
  let musd_emission = '0xBa69e6FC7Df49a3b75b565068Fb91ff2d9d91780';
  let musd_emission_signer;

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [musd_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [musd_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [dai_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [musd_emission]);
    await hre.ethers.provider.send("hardhat_setBalance", [dai_whale, '0xffffffffffffffff']);
    await hre.ethers.provider.send("hardhat_setBalance", [musd_emission, '0xffffffffffffffff']);
  });

  beforeEach(async () => {
    musd_emission_signer = await ethers.getSigner(musd_emission);
    [owner, user, user2, , proxyAdmin] = await ethers.getSigners();
    let IdleMStableStrategyFactory = await ethers.getContractFactory("IdleMStableStrategy");
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

    await mUSD.connect(musd_signer).transfer(user.address, AMOUNT_TO_TRANSFER.mul(BN(2)));
    await DAI.connect(dai_signer).transfer(user.address, AMOUNT_TO_TRANSFER);
    savingsManager = await ethers.getContractAt(savingsManagerAbi, savingsManagerAddress);

    await IdleMStableStrategy.connect(owner).initialize(
      imUSD.address,
      mUSD.address,
      vault.address,
      uniswapV2RouterV2,
      [meta.address, wrappedETH, mUSD.address],
      owner.address
    );

    // assuming that user itself if the idle CDO.
    await IdleMStableStrategy.connect(owner).setWhitelistedCDO(user.address);
    await IdleMStableStrategy.connect(owner).setReleaseBlocksPeriod(100);
  });

  it("Check contract address IdleMStableAddress", async () => {
    expect(isAddress(IdleMStableStrategy.address)).to.eq(true);
  });

  it("Check existing contracts", async () => {
    expect(await imUSD.name()).to.eq("Interest bearing mUSD");
    expect(await mUSD.name()).to.eq("mStable USD");
    expect(await meta.name()).to.eq("Meta");
    expect(await vault.boostDirector()).to.eq("0xBa05FD2f20AE15B0D3f20DDc6870FeCa6ACd3592");
    expect(await IdleMStableStrategy.rewardLastRound()).eq(0);
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
    expect(await vault.rawBalanceOf(IdleMStableStrategy.address)).gt(0);
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
    const amount = BN('10000').mul(ONE_TOKEN(18));
    await meta.connect(musd_emission_signer).transfer(VAULT_ADDRESS, amount);
    await vault.connect(musd_emission_signer).notifyRewardAmount(amount);
    
    // check price 
    const initialStaked = await IdleMStableStrategy.totalLpTokensStaked();
    const pricePre = await IdleMStableStrategy.price();
    let rawBalanceBefore = await vault.rawBalanceOf(IdleMStableStrategy.address);
    let strategySharesBefore = await IdleMStableStrategy.totalSupply();

    const staticRes = await helpers.sudoStaticCall(owner.address, IdleMStableStrategy, 'redeemRewards()', []);
    await IdleMStableStrategy.connect(owner)["redeemRewards()"](); // will get MTA token, convert to musd and deposit to vault

    let strategySharesAfter = await IdleMStableStrategy.totalSupply();
    let rawBalanceAfter = await vault.rawBalanceOf(IdleMStableStrategy.address);
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
    // // check that rewardLastRound is updated and > 0
    // await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    // await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
    // // // 2 days later
    // // await network.provider.request({
    // //   method: "evm_increaseTime",
    // //   params: [2 * 86400],
    // // });
    // // await network.provider.request({
    // //   method: "evm_mine",
    // //   params: [],
    // // });
    // // await vault.connect(user).pokeBoost(IdleMStableStrategy.address);
    // await IdleMStableStrategy.connect(owner)["redeemRewards()"]();
    // // It saves endRound in rewardLastRound
    // expect(await IdleMStableStrategy.rewardLastRound()).gt(0);
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
    await network.provider.request({method: "evm_increaseTime",  params: [4 * 86400]});
    await network.provider.request({method: "evm_mine", params: []});
    
    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
    
    apr = await IdleMStableStrategy.getApr();
    expect(apr).gt(0);
    await network.provider.request({method: "evm_increaseTime",  params: [4 * 86400]});
    await network.provider.request({method: "evm_mine", params: []});
    
    await savingsManager.connect(user).collectAndStreamInterest(mUSD.address);
    expect(apr).eq(await IdleMStableStrategy.getApr());
    
    await IdleMStableStrategy.connect(user).redeem(BN(await IdleMStableStrategy.balanceOf(user.address)).div(2));
    await network.provider.request({method: "evm_increaseTime",  params: [4 * 86400]});
    await network.provider.request({method: "evm_mine", params: []});
    await savingsManager.connect(user).collectAndStreamInterest(mUSD.address);
    expect(apr).lt(await IdleMStableStrategy.getApr());
  });
});
