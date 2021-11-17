require("hardhat/config");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const erc20 = require("../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json");
const addresses = require("../lib/addresses");
const { expect } = require("chai");
const { FakeContract, smock } = require("@defi-wonderland/smock");

require("chai").use(smock.matchers);

const BN = (n) => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const MAX_UINT = BN(
  "115792089237316195423570985008687907853269984665640564039457584007913129639935"
);
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("IdleLidoStrategy", function () {
  beforeEach(async () => {
    // deploy contracts
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

    one = ONE_TOKEN(18);

    await hre.network.provider.send("hardhat_setBalance", [owner.address, "0xfffffffffffffffffff"])

    const MockLido = await ethers.getContractFactory("MockLido"); // underlyingToken
    const MockWstETH = await ethers.getContractFactory("MockWstETH"); // strategyToken
    const MockLidoOracle = await ethers.getContractFactory("MockLidoOracle");

    lido = await MockLido.deploy();
    await lido.deployed();
    underlying = lido

    wstETH = await MockWstETH.deploy(lido.address);
    await wstETH.deployed();

    oracle = await MockLidoOracle.deploy();
    await oracle.deployed();

    // Params
    initialAmount = BN("10").mul(ONE_TOKEN(18));

    strategy = await helpers.deployUpgradableContract(
      "IdleLidoStrategy",
      [
        wstETH.address,
        underlying.address,
        owner.address,
      ],
      owner
    );

    await lido
      .connect(owner)
      .submit(ZERO_ADDRESS, { value: BN("50").mul(ONE_TOKEN(18)) });

    // Fund wallets
    await helpers.fundWallets(
      underlying.address,
      [
        AABuyerAddr,
        BBBuyerAddr,
        AABuyer2Addr,
        BBBuyer2Addr,
      ],
      owner.address,
      initialAmount
    );

    await lido.setOracle(oracle.address);
  });
  
  it("should not reinitialize the contract", async () => {
    await expect(
      strategy
        .connect(owner)
        .initialize(
          lido.address,
          wstETH.address,
          owner.address,
        )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize", async () => {
    expect(await strategy.strategyToken()).to.equal(wstETH.address);
    expect(await strategy.token()).to.equal(underlying.address);
    expect(await strategy.oneToken()).to.be.equal(one);
    expect(await strategy.tokenDecimals()).to.be.equal(BN(18));
    expect(await strategy.lido()).to.equal(lido.address);

    expect(
      await underlying.allowance(strategy.address, wstETH.address)
    ).to.be.equal(MAX_UINT);
    expect(await strategy.owner()).to.equal(owner.address);
  });

  it("should deposit", async () => {
    const addr = AABuyerAddr;
    const _amount = BN("1").mul(one);
    const _outputWstEth = await calcOuputWstEth(_amount);

    const initialWstEthBal = await wstETH.balanceOf(addr);

    await deposit(addr, _amount);
    const finalBal = await underlying.balanceOf(addr);
    const finalWstEthBal = await wstETH.balanceOf(addr);

    expect(initialAmount.sub(finalBal)).to.equal(_amount);
    expect(finalWstEthBal.sub(initialWstEthBal)).to.equal(_outputWstEth);

    // No token left in the contract
    expect(await underlying.balanceOf(strategy.address)).to.equal(0);
    expect(await wstETH.balanceOf(strategy.address)).to.equal(0);
  });

  const calcOuputWstEth = async (deposit) => {
    return await lido.getSharesByPooledEth(deposit);
  };

  it("should redeem", async () => {
    const addr = AABuyerAddr;
    const _amount = BN("1").mul(one);
    const _outputWstEth = await calcOuputWstEth(_amount);

    await deposit(addr, _amount);

    const initialBal = await underlying.balanceOf(addr);
    const initialWstEthBal = await wstETH.balanceOf(addr);

    await redeem(addr, _outputWstEth);

    const finalBal = await underlying.balanceOf(addr);
    const finalWstEthBal = await wstETH.balanceOf(addr);

    expect(finalWstEthBal).to.equal(0);
    expect(finalBal.sub(initialBal)).to.equal(_amount);

    // No token left in the contract
    expect(await underlying.balanceOf(strategy.address)).to.equal(0);
    expect(await wstETH.balanceOf(strategy.address)).to.equal(0);
  });

  it("should skip redeem if amount is 0", async () => {
    const addr = AABuyerAddr;
    const _amount = BN("1").mul(one);

    await deposit(addr, _amount);

    const initialBal = await underlying.balanceOf(addr);
    const initialWstEthBal = await wstETH.balanceOf(addr);

    await redeem(addr, BN("0"));

    const finalBal = await underlying.balanceOf(addr);
    const finalWstEthBal = await wstETH.balanceOf(addr);

    expect(finalWstEthBal).to.equal(initialWstEthBal);
    expect(finalBal).to.equal(initialBal);

    // No token left in the contract
    expect(await underlying.balanceOf(strategy.address)).to.equal(0);
    expect(await wstETH.balanceOf(strategy.address)).to.equal(0);
  });
  it("should redeemUnderlying", async () => {
    const addr = AABuyerAddr;
    const _amount = BN("1").mul(one);

    await deposit(addr, _amount);

    const initialWstEthBal = await wstETH.balanceOf(addr);
    const initialBal = await underlying.balanceOf(addr);

    await redeemUnderlying(addr, _amount);

    const finalWstEthBal = await wstETH.balanceOf(addr);
    const finalBal = await underlying.balanceOf(addr);

    expect(finalWstEthBal).to.equal(0);
    expect(finalBal.sub(initialBal)).to.equal(_amount);

    // No token left in the contract
    expect(await underlying.balanceOf(strategy.address)).to.equal(0);
    expect(await wstETH.balanceOf(strategy.address)).to.equal(0);
  });
  it("should skip redeemRewards if bal is 0", async () => {
    const addr = RandomAddr;
    await strategy.connect(Random).redeemRewards();

    // No token left in the contract
    expect(await underlying.balanceOf(strategy.address)).to.equal(0);
    expect(await lido.balanceOf(strategy.address)).to.equal(0);
  });
  it("setWhitelistedCDO should set the relative address and be called only by the owner", async () => {
    const val = RandomAddr;
    await strategy.setWhitelistedCDO(val);
    expect(await strategy.whitelistedCDO()).to.be.equal(val);

    await expect(
      strategy.setWhitelistedCDO(addresses.addr0)
    ).to.be.revertedWith("IS_0");

    await expect(
      strategy.connect(BBBuyer).setWhitelistedCDO(val)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should return the current price", async () => {
    const stEthPerToken = await wstETH.stEthPerToken();
    expect(await strategy.price()).to.equal(stEthPerToken);
  });

  it("should return the current net apr", async () => {
    const _amount = BN("10").mul(one);
    const postTotalPooledEther = BN("1314070").mul(one);
    const preTotalPooledEther = BN("1313868").mul(one);
    const timeElapsed = BN("86400");

    // set lido mocked params
    await oracle.setLastCompletedEpochDelta(
      postTotalPooledEther,
      preTotalPooledEther,
      timeElapsed
    );

    expect(await strategy.getApr()).to.equal(
      calcApr(
        postTotalPooledEther,
        preTotalPooledEther,
        timeElapsed,
        BN("1000")
      )
    );
  });

  const calcApr = (
    postTotalPooledEther,
    preTotalPooledEther,
    timeElapsed,
    feeBps
  ) => {
    const secondsInYear = BN((365 * 24 * 3600).toString());
    const apr = postTotalPooledEther
      .sub(preTotalPooledEther)
      .mul(secondsInYear)
      .mul(one)
      .mul("100")
      .div(preTotalPooledEther.mul(timeElapsed));
    return apr.sub(apr.mul(feeBps).div(BN("10000")));
  };

  const deposit = async (addr, amount) => {
    await helpers.sudoCall(addr, underlying, "approve", [
      strategy.address,
      MAX_UINT,
    ]);
    await helpers.sudoCall(addr, strategy, "deposit", [amount]);
  };
  const redeem = async (addr, amount) => {
    await helpers.sudoCall(addr, wstETH, "approve", [strategy.address, MAX_UINT]);
    await helpers.sudoCall(addr, strategy, "redeem", [amount]);
  };
  const redeemUnderlying = async (addr, amount) => {
    await helpers.sudoCall(addr, wstETH, "approve", [strategy.address, MAX_UINT]);
    await helpers.sudoCall(addr, strategy, "redeemUnderlying", [amount]);
  };
  const redeemRewards = async (addr, amount) => {
    await helpers.sudoCall(addr, wstETH, "approve", [strategy.address, MAX_UINT]);
    const [a, b, res] = await helpers.sudoCall(
      addr,
      strategy,
      "redeemRewards",
      []
    );
    return res;
  };
  const staticRedeemRewards = async (addr, amount) => {
    await helpers.sudoCall(addr, lido, "approve", [strategy.address, MAX_UINT]);
    return await helpers.sudoStaticCall(addr, strategy, "redeemRewards", []);
  };
});
