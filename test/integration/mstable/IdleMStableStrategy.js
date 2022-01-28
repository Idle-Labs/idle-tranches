require("hardhat/config");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const erc20 = require("../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const vaultAbi = require("../artifacts/contracts/interfaces/IVault.sol/IVault.json").abi;
const masset = require("../artifacts/contracts/interfaces/IMAsset.sol/IMAsset.json");
const savingsManagerAbi = require("../artifacts/contracts/interfaces/ISavingsManager.sol/ISavingsManager.json").abi;
const idleMstableStrategyAbi = require("../artifacts/contracts/strategies/mstable/IdleMStableStrategy.sol/IdleMStableStrategy.json").abi;

const addresses = require("../lib/addresses");
const { expect } = require("chai");
const { FakeContract, smock } = require("@defi-wonderland/smock");
const { ethers } = require("hardhat");
const { isAddress } = require("@ethersproject/address");

require("chai").use(smock.matchers);

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

const dai_whale = "0x45fD5AF82A8af6d3f7117eBB8b2cfaD72B27342b";
const musd_whale = "0xe008464f754e85e37bca41cce3fbd49340950b29";

const AMOUNT_TO_TRANSFER = BN("1000000000000000000");

// const KEY_SAVINGS_MANAGER = "0x12fe936c77a1e196473c4314f3bed8eeac1d757b319abb85bdda70df35511bf1";
const savingsManagerAddress = "0xBC3B550E0349D74bF5148D86114A48C3B4Aa856F";

describe.only("IdleMStableStrategy", function () {
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

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [musd_whale]);
    await ethers.provider.send("hardhat_impersonateAccount", [dai_whale]);
  });

  beforeEach(async () => {
    [owner, user, , , proxyAdmin] = await ethers.getSigners();
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

    await mUSD.connect(musd_signer).transfer(user.address, AMOUNT_TO_TRANSFER);
    savingsManager = await ethers.getContractAt(savingsManagerAbi, savingsManagerAddress);

    await IdleMStableStrategy.connect(owner).initialize(
      imUSD.address,
      mUSD.address,
      vault.address,
      user.address, // assuming that user itself if the idle CDO.
      uniswapV2RouterV2,
      [meta.address, wrappedETH, mUSD.address],
      owner.address
    );
  });

  it("Check contract address IdleMStableAddress", async () => {
    expect(isAddress(IdleMStableStrategy.address)).to.eq(true);
  });

  it("Check existing contracts", async () => {
    expect(await imUSD.name()).to.eq("Interest bearing mUSD");
    expect(await mUSD.name()).to.eq("mStable USD");
    expect(await meta.name()).to.eq("Meta");
    expect(await vault.boostDirector()).to.eq("0xBa05FD2f20AE15B0D3f20DDc6870FeCa6ACd3592");
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
    expect(mUSDBalanceAfter.sub(mUSDBalanceBefore)).closeTo(AMOUNT_TO_TRANSFER.div(10), "100000", "Approximate check failed");
  });

  it("Redeem Rewards", async () => {
    let strategySharesBefore = await IdleMStableStrategy.totalSupply();

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    let strategySharesAfter = await IdleMStableStrategy.totalSupply();

    let sharesReceived = strategySharesAfter.sub(strategySharesBefore);
    expect(sharesReceived).gt(0);

    let rawBalanceBefore = await vault.rawBalanceOf(IdleMStableStrategy.address);
    await IdleMStableStrategy.connect(user)["redeemRewards()"](); // will get MTA token, convert to musd and deposit to vault
    let rawBalanceAfter = await vault.rawBalanceOf(IdleMStableStrategy.address);

    expect(rawBalanceAfter.sub(rawBalanceBefore)).gt(0);
  });

  it("APR", async () => {
    const musdSwapingContract = await ethers.getContractAt(masset.abi, mUSD.address);

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    await mUSD.connect(musd_signer).transfer(user.address, AMOUNT_TO_TRANSFER);
    await DAI.connect(dai_signer).transfer(user.address, AMOUNT_TO_TRANSFER);

    await DAI.connect(user).approve(musdSwapingContract.address, AMOUNT_TO_TRANSFER);

    await musdSwapingContract.connect(user).swap(DAIAddress, USDCAddress, AMOUNT_TO_TRANSFER.div(2), 0, user.address);

    await network.provider.request({
      method: "evm_increaseTime",
      params: [30 * 86400],
    });

    await savingsManager.connect(user).collectAndStreamInterest(mUSD.address);

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    expect(await IdleMStableStrategy.getApr()).gt(0);
  });
});
