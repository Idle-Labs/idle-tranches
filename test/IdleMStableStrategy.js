require("hardhat/config");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const erc20 = require("../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const vaultAbi = require("../artifacts/contracts/interfaces/IVault.sol/IVault.json").abi;

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
const musd_whale = "0xe008464f754e85e37bca41cce3fbd49340950b29";

const AMOUNT_TO_TRANSFER = BN("1000000000000000000");

describe.only("IdleMStableStrategy", function () {
  let IdleMStableStrategy;

  let owner;
  let user;

  let imUSD;
  let mUSD;
  let meta;
  let vault;

  let musd_signer;

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [musd_whale]);
  });

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();
    let IdleMStableStrategyFactory = await ethers.getContractFactory("IdleMStableStrategy");
    IdleMStableStrategy = await IdleMStableStrategyFactory.deploy();
    await IdleMStableStrategy.deployed();

    imUSD = await ethers.getContractAt(erc20.abi, imUSD_ADDRESS);
    mUSD = await ethers.getContractAt(erc20.abi, mUSD_ADDRESS);
    meta = await ethers.getContractAt(erc20.abi, META_ADDESS);
    vault = await ethers.getContractAt(vaultAbi, VAULT_ADDRESS);

    musd_signer = await ethers.getSigner(musd_whale);

    await mUSD.connect(musd_signer).transfer(user.address, AMOUNT_TO_TRANSFER);

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

    await IdleMStableStrategy.connect(user).redeem(redeemAmount);
  });

  it("Redeem Rewards", async () => {
    let strategySharesBefore = await IdleMStableStrategy.totalSupply();

    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    let strategySharesAfter = await IdleMStableStrategy.totalSupply();

    let sharesReceived = strategySharesAfter.sub(strategySharesBefore);
    expect(sharesReceived).gt(0);

    await IdleMStableStrategy.connect(user)["redeemRewards()"]();
  });

  it("APR", async () => {
    await mUSD.connect(user).approve(IdleMStableStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleMStableStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
    console.log(await IdleMStableStrategy.getApr());
  });
});
