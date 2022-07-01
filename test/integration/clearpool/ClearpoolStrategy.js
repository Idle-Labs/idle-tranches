require("hardhat/config");
const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

const usdcAddress = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"; // USDC
const circleAddress = "0x55fe002aeff02f77364de339a1292923a15844b8"; // Holds a lot of USDC
const lendingPoolAddress = "0xe3D20A721522874D32548B4097d1afc6f024e45b"; // One of Clearpool pools

describe.only("Idle Clearpool Strategy", async () => {
  let idleClearpoolStrategy, usdc, lendingPool, cpool, strategyToken;
  let owner, user, circle;
  let snapshotId;

  before(async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [circleAddress]);
    await ethers.provider.send("hardhat_setBalance", [
      circleAddress,
      "0xffffffffffffffff",
    ]);

    [owner, user] = await ethers.getSigners();
    circle = await ethers.getSigner(circleAddress);

    usdc = await ethers.getContractAt("IERC20Detailed", usdcAddress);
    lendingPool = await ethers.getContractAt("IPoolMaster", lendingPoolAddress);
    strategyToken = await ethers.getContractAt(
      "IERC20Detailed",
      lendingPoolAddress
    );
    const poolFactory = await ethers.getContractAt(
      "IPoolFactory",
      await lendingPool.factory()
    );
    cpool = await ethers.getContractAt(
      "IERC20Detailed",
      await poolFactory.cpool()
    );

    const IdleClearpoolStrategyFactory = await ethers.getContractFactory(
      "IdleClearpoolStrategy"
    );
    idleClearpoolStrategy = await upgrades.deployProxy(
      IdleClearpoolStrategyFactory,
      [
        lendingPool.address,
        usdc.address,
        owner.address,
      ]
    );
    await idleClearpoolStrategy.connect(owner).setWhitelistedCDO(user.address);

    await usdc
      .connect(circle)
      .transfer(user.address, ethers.utils.parseUnits("1000000", 6));
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
    const oneToken = ethers.utils.parseUnits("1", 6);
    const one18 = ethers.utils.parseUnits("1", 18);
    const amountToTransfer = ethers.utils.parseUnits("1000", 6);

    const userUsdcBefore = await usdc.balanceOf(user.address);
    const poolUsdcBefore = await usdc.balanceOf(lendingPool.address);

    await usdc
      .connect(user)
      .approve(idleClearpoolStrategy.address, amountToTransfer);
    await idleClearpoolStrategy.connect(user).deposit(amountToTransfer);

    const userUsdcAfter = await usdc.balanceOf(user.address);
    const poolUsdcAfter = await usdc.balanceOf(lendingPool.address);

    expect(userUsdcBefore.sub(userUsdcAfter)).to.equal(amountToTransfer);
    expect(poolUsdcAfter.sub(poolUsdcBefore)).to.equal(amountToTransfer);

    const cpTokenBal = await strategyToken.balanceOf(idleClearpoolStrategy.address);
    expect(
      cpTokenBal.mul(one18).div(oneToken)
    ).to.equal(await idleClearpoolStrategy.balanceOf(user.address));
  });

  it("Redeem", async () => {
    const amountToTransfer = ethers.utils.parseUnits("1000", 6);
    await usdc
      .connect(user)
      .approve(idleClearpoolStrategy.address, amountToTransfer);
    await idleClearpoolStrategy.connect(user).deposit(amountToTransfer);

    const userUsdcBefore = await usdc.balanceOf(user.address);
    const poolUsdcBefore = await usdc.balanceOf(lendingPool.address);

    await idleClearpoolStrategy
      .connect(user)
      .redeem(await strategyToken.balanceOf(idleClearpoolStrategy.address));

    const userUsdcAfter = await usdc.balanceOf(user.address);
    const poolUsdcAfter = await usdc.balanceOf(lendingPool.address);

    expect(userUsdcAfter.sub(userUsdcBefore)).to.be.closeTo(amountToTransfer, 5);
    expect(poolUsdcBefore.sub(poolUsdcAfter)).to.be.closeTo(amountToTransfer, 5);

    expect(
      await strategyToken.balanceOf(idleClearpoolStrategy.address)
    ).to.equal(0);
  });

  it("Redeem underlying", async () => {
    const amountToTransfer = ethers.utils.parseUnits("1000", 6);
    await usdc
      .connect(user)
      .approve(idleClearpoolStrategy.address, amountToTransfer);
    await idleClearpoolStrategy.connect(user).deposit(amountToTransfer);

    const userUsdcBefore = await usdc.balanceOf(user.address);
    const poolUsdcBefore = await usdc.balanceOf(lendingPool.address);

    await idleClearpoolStrategy
      .connect(user)
      .redeemUnderlying(amountToTransfer.div(2));

    const userUsdcAfter = await usdc.balanceOf(user.address);
    const poolUsdcAfter = await usdc.balanceOf(lendingPool.address);

    expect(userUsdcAfter.sub(userUsdcBefore)).to.be.gt(
      amountToTransfer.div(2).sub(1)
    );
    expect(poolUsdcBefore.sub(poolUsdcAfter)).to.be.gt(
      amountToTransfer.div(2).sub(1)
    );
  });

  it("Price, apr and rewardTokens", async () => {
    const amountToTransfer = ethers.utils.parseUnits("1000", 6);
    await usdc
      .connect(user)
      .approve(idleClearpoolStrategy.address, amountToTransfer);
    await idleClearpoolStrategy.connect(user).deposit(amountToTransfer);

    const priceBefore = await idleClearpoolStrategy.price();

    const rate = await lendingPool.getSupplyRate();

    await network.provider.request({
      method: "evm_increaseTime",
      params: [100000],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    const interest = amountToTransfer
      .mul(rate)
      .mul(100000)
      .div(ethers.utils.parseUnits("1"));

    const priceAfter = await idleClearpoolStrategy.price();

    // As Idle's prices use lower precision there is slight imprecision
    expect(
      priceAfter.mul(amountToTransfer).div(ethers.utils.parseUnits("1", 9))
    ).to.equal(
      priceBefore
        .mul(amountToTransfer.add(interest))
        .div(ethers.utils.parseUnits("1", 9))
    );

    expect(await idleClearpoolStrategy.connect(user).getApr()).to.be.gt(0);
  });

  it("Redeem rewards", async () => {
    const amountToTransfer = ethers.utils.parseUnits("1000", 6);
    await usdc
      .connect(user)
      .approve(idleClearpoolStrategy.address, amountToTransfer);
    await idleClearpoolStrategy.connect(user).deposit(amountToTransfer);

    await network.provider.request({
      method: "evm_increaseTime",
      params: [100000],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    await idleClearpoolStrategy.connect(user).redeemRewards("0x");
    expect(await cpool.balanceOf(user.address)).to.be.gt(0);
  });
});
