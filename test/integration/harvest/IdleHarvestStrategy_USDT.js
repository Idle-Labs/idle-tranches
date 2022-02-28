require("hardhat/config");
const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const BN = (n) => BigNumber.from(n.toString());

const erc20 = require("../../../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const idleHarvestStrategyAbi =
  require("../../../artifacts/contracts/strategies/harvest/IdleHarvestStrategy.sol/IdleHarvestStrategy.json").abi;
const harvestControllerAbi = require("../../../artifacts/contracts/interfaces/harvest/IController.sol/IHarvestController.json").abi;
const rewardPoolAbi = require("../../../artifacts/contracts/interfaces/harvest/IRewardPool.sol/IRewardPool.json").abi;
const harvestVaultAbi = require("../../../artifacts/contracts/interfaces/harvest/IHarvestVault.sol/IHarvestVault.json").abi;
const uniswapV2RouterV2Abi = require("../../../artifacts/contracts/interfaces/IUniswapV2Router02.sol/IUniswapV2Router02.json").abi;

const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

const USDTAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // USDT
const strategyToken = "0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C"; // fUSDT

const wrappedETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

const rewardPool = "0x6ac4a7AB91E6fD098E13B7d347c6d4d1494994a2"; // NoMintRewardPool for USDT

const dai_whale = "0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8";

let AMOUNT_TO_TRANSFER = BN("100000000000000000000"); // 100 DAI

const harvestControllerAddress = "0x3cC47874dC50D98425ec79e647d83495637C55e3";
const harvestGovernanceAddress = "0xf00dD244228F51547f0563e60bCa65a30FBF5f7f";

const uniswapV2RouterV2Address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

describe.only("Idle Harvest Strategy (USDT)", async () => {
  let IdleHarvestStrategy;
  let harvestController;
  let rewardPoolContract;
  let harvestVault;

  let DAI;
  let USDT;

  let owner;
  let user;
  let proxyAdmin;

  let dai_signer;
  let harvestGovernanceSigner;

  let uniswapV2RouterV2;
  let snapshotId;

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [dai_whale]);
    await ethers.provider.send("hardhat_setBalance", [dai_whale, "0xffffffffffffffff"]);

    await ethers.provider.send("hardhat_impersonateAccount", [harvestGovernanceAddress]);
    await ethers.provider.send("hardhat_setBalance", [harvestGovernanceAddress, "0xffffffffffffffff"]);

    [owner, user, , , proxyAdmin] = await ethers.getSigners();
    DAI = await ethers.getContractAt(erc20.abi, DAIAddress);
    USDT = await ethers.getContractAt(erc20.abi, USDTAddress);
    dai_signer = await ethers.getSigner(dai_whale);
    harvestGovernanceSigner = await ethers.getSigner(harvestGovernanceAddress);

    let IdleharvestStrategyFactory = await ethers.getContractFactory("IdleHarvestStrategy");
    let IdleHarvestStrategyLogic = await IdleharvestStrategyFactory.deploy();
    uniswapV2RouterV2 = await ethers.getContractAt(uniswapV2RouterV2Abi, uniswapV2RouterV2Address);

    let TransparentUpgradableProxyFactory = await ethers.getContractFactory("TransparentUpgradeableProxy");
    let TransparentUpgradableProxy = await TransparentUpgradableProxyFactory.deploy(
      IdleHarvestStrategyLogic.address,
      proxyAdmin.address,
      "0x"
    );
    await TransparentUpgradableProxy.deployed();
    IdleHarvestStrategy = await ethers.getContractAt(idleHarvestStrategyAbi, TransparentUpgradableProxy.address);

    await DAI.connect(dai_signer).transfer(user.address, AMOUNT_TO_TRANSFER);
    await DAI.connect(user).approve(uniswapV2RouterV2.address, AMOUNT_TO_TRANSFER);
    await uniswapV2RouterV2
      .connect(user)
      .swapExactTokensForTokens(AMOUNT_TO_TRANSFER, 0, [DAI.address, USDT.address], user.address, "9999999999999");
    AMOUNT_TO_TRANSFER = await USDT.connect(user).balanceOf(user.address);
    console.log({ AMOUNT_TO_TRANSFER: AMOUNT_TO_TRANSFER.toString() });

    rewardPoolContract = await ethers.getContractAt(rewardPoolAbi, rewardPool);
    let govToken = await rewardPoolContract.connect(owner).rewardToken();

    await IdleHarvestStrategy.connect(owner).initialize(
      strategyToken,
      USDTAddress,
      rewardPool,
      uniswapV2RouterV2Address,
      [govToken, wrappedETH, USDTAddress],
      owner.address
    );
    await IdleHarvestStrategy.connect(owner).setWhitelistedCDO(user.address);
    harvestVault = await ethers.getContractAt(harvestVaultAbi, strategyToken);

    harvestController = await ethers.getContractAt(harvestControllerAbi, harvestControllerAddress);
    await harvestController.connect(harvestGovernanceSigner).addMultipleToWhitelist([IdleHarvestStrategy.address]);
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

  it("Deposit", async () => {
    console.log("Idle Harvest Strategy", IdleHarvestStrategy.address);
    await USDT.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
  });

  it("Redeem", async () => {
    let AMOUNT_TO_REDEEM = BN("99000000");
    await USDT.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    await IdleHarvestStrategy.connect(user).redeem(AMOUNT_TO_REDEEM);
  });

  it("Redeem Underlying", async () => {
    let toRedeem = BN("90000000");
    await USDT.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    await IdleHarvestStrategy.connect(user).redeemUnderlying(toRedeem);
  });

  it("Price, apr and rewardTokens", async () => {
    let AMOUNT_TO_REDEEM = BN("99000000");
    await USDT.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    console.log("price before hard work", (await IdleHarvestStrategy.connect(user).price()).toString());
    console.log("reward tokens", await IdleHarvestStrategy.connect(user).getRewardTokens());
    console.log("Apr Before", (await IdleHarvestStrategy.connect(user).getApr()).toString());

    await harvestVault.connect(harvestGovernanceSigner).doHardWork();
    console.log("price after hardhwork", (await IdleHarvestStrategy.connect(user).price()).toString());
    console.log("Apr After", (await IdleHarvestStrategy.connect(user).getApr()).toString());
    await IdleHarvestStrategy.connect(user).redeem(AMOUNT_TO_REDEEM);

    await network.provider.request({
      method: "evm_increaseTime",
      params: [30 * 86400],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    console.log("Apr After Some redeem", (await IdleHarvestStrategy.connect(user).getApr()).toString());
  });

  it("Redeem Rewards", async () => {
    console.log({ user: user.address });
    await USDT.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    await network.provider.request({
      method: "evm_increaseTime",
      params: [30 * 86400],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    console.log("Apr Before", (await IdleHarvestStrategy.connect(user).getApr()).toString());

    await IdleHarvestStrategy.connect(user).redeemRewards("0x");

    await network.provider.request({
      method: "evm_increaseTime",
      params: [30 * 86400],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    console.log("Apr After", (await IdleHarvestStrategy.connect(user).getApr()).toString());
  });
});
