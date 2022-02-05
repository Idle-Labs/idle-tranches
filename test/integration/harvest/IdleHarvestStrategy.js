require("hardhat/config");
const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const BN = (n) => BigNumber.from(n.toString());

const erc20 = require("../../../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const idleHarvestStrategyAbi =
  require("../../../artifacts/contracts/strategies/harvest/IdleHarvestStrategy.sol/IdleHarvestStrategy.json").abi;
const harvestControllerAbi = require("../../../artifacts/contracts/interfaces/harvest/IController.sol/IHarvestController.json").abi;

const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const strategyToken = "0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C"; // fDAI
const rewardPool = "0x15d3A64B2d5ab9E152F16593Cdebc4bB165B5B4A"; // NoMintRewardPool

const dai_whale = "0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8";
const AMOUNT_TO_TRANSFER = BN("1000000000000000000");

const harvestControllerAddress = "0x3cC47874dC50D98425ec79e647d83495637C55e3";
const harvestGovernanceAddress = "0xf00dD244228F51547f0563e60bCa65a30FBF5f7f";

describe.only("Idle Harvest Strategy", async () => {
  let IdleHarvestStrategy;
  let harvestController;

  let DAI;

  let owner;
  let user;
  let proxyAdmin;

  let dai_signer;
  let harvestGovernanceSigner;

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [dai_whale]);
    await ethers.provider.send("hardhat_setBalance", [dai_whale, "0xffffffffffffffff"]);

    await ethers.provider.send("hardhat_impersonateAccount", [harvestGovernanceAddress]);
    await ethers.provider.send("hardhat_setBalance", [harvestGovernanceAddress, "0xffffffffffffffff"]);
  });

  beforeEach(async () => {
    [owner, user, , , proxyAdmin] = await ethers.getSigners();
    DAI = await ethers.getContractAt(erc20.abi, DAIAddress);
    dai_signer = await ethers.getSigner(dai_whale);
    harvestGovernanceSigner = await ethers.getSigner(harvestGovernanceAddress);

    let IdleharvestStrategyFactory = await ethers.getContractFactory("IdleHarvestStrategy");
    let IdleHarvestStrategyLogic = await IdleharvestStrategyFactory.deploy();

    let TransparentUpgradableProxyFactory = await ethers.getContractFactory("TransparentUpgradeableProxy");
    let TransparentUpgradableProxy = await TransparentUpgradableProxyFactory.deploy(
      IdleHarvestStrategyLogic.address,
      proxyAdmin.address,
      "0x"
    );
    await TransparentUpgradableProxy.deployed();
    IdleHarvestStrategy = await ethers.getContractAt(idleHarvestStrategyAbi, TransparentUpgradableProxy.address);

    await DAI.connect(dai_signer).transfer(user.address, AMOUNT_TO_TRANSFER);

    await IdleHarvestStrategy.connect(owner).initialize(strategyToken, DAIAddress, rewardPool, owner.address);
    await IdleHarvestStrategy.connect(owner).setWhitelistedCDO(user.address);

    harvestController = await ethers.getContractAt(harvestControllerAbi, harvestControllerAddress);
    await harvestController.connect(harvestGovernanceSigner).addMultipleToWhitelist([IdleHarvestStrategy.address]);
  });

  it("Deposit", async () => {
    console.log("Idle Harvest Strategy", IdleHarvestStrategy.address);
    await DAI.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);
  });

  it("Redeem", async () => {
    let AMOUNT_TO_REDEEM = BN("100000000000000");
    await DAI.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    await IdleHarvestStrategy.connect(user).redeem(AMOUNT_TO_REDEEM);
  });

  it("Redeem Underlying", async () => {
    await DAI.connect(user).approve(IdleHarvestStrategy.address, AMOUNT_TO_TRANSFER);
    await IdleHarvestStrategy.connect(user).deposit(AMOUNT_TO_TRANSFER);

    await IdleHarvestStrategy.connect(user).redeemUnderlying(AMOUNT_TO_TRANSFER);
  });

  it("Price, apr and rewardTokens", async () => {
    console.log("price", await IdleHarvestStrategy.connect(user).price());
    console.log("reward tokens", await IdleHarvestStrategy.connect(user).getRewardTokens());
    console.log("Apr", await IdleHarvestStrategy.connect(user).getApr());
  });
});
