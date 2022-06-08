require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");
const { expect } = require("chai");
const { FakeContract, smock } = require('@defi-wonderland/smock');

require('chai').use(smock.matchers);

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("LidoCDOTrancheGateway", function () {
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

    one = ONE_TOKEN(18);

    await hre.network.provider.send("hardhat_setBalance", [owner.address, "0xfffffffffffffffffff"])

    const Gateway = await ethers.getContractFactory("LidoCDOTrancheGateway");
    const MockLido = await ethers.getContractFactory("MockLido"); // underlyingToken
    const WETH = await ethers.getContractFactory("MockWETH"); // strategyToken
    const MockWstETH = await ethers.getContractFactory("MockWstETH"); // strategyToken
    const MockLidoOracle = await ethers.getContractFactory("MockLidoOracle");

    weth = await WETH.deploy({ value: BN('10').mul(ONE_TOKEN(18)) });
    await weth.deployed();

    stETH = await MockLido.deploy();
    await stETH.deployed();
    underlying = stETH

    wstETH = await MockWstETH.deploy(stETH.address);
    await wstETH.deployed();

    oracle = await MockLidoOracle.deploy();
    await oracle.deployed();

    await stETH
      .connect(owner)
      .submit(ZERO_ADDRESS, { value: BN("50").mul(ONE_TOKEN(18)) });

    await stETH.setOracle(oracle.address);

    strategy = await helpers.deployUpgradableContract(
      "IdleLidoStrategy",
      [
        wstETH.address,
        underlying.address,
        owner.address,
      ],
      owner
    );

    idleCDO = await helpers.deployUpgradableContract(
      'EnhancedIdleCDO',
      [
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        []
      ],
      owner
    );

    AA = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
    BB = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());

    gateway = await Gateway.deploy(weth.address, wstETH.address, stETH.address, idleCDO.address, owner.address);

    await idleCDO.setWethForTest(weth.address);
    await idleCDO.setUnlentPerc(BN('0'));
    await idleCDO.setIsStkAAVEActive(false);

    initialAmount = BN("10").mul(ONE_TOKEN(18));

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
  });

  it("should not reinitialize the contract", async () => {
    await expect(
      idleCDO.connect(owner).initialize(
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'),
        []
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize params", async () => {
    // Reset it here (it's set to 0 after initialization in beforeEach)
    await idleCDO.setUnlentPerc(BN('2000'));

    const AAERC20 = await ethers.getContractAt("IERC20Detailed", AA.address);
    const BBERC20 = await ethers.getContractAt("IERC20Detailed", BB.address);

    // IdleCDO
    expect(await idleCDO.AATranche()).to.equal(AA.address);
    expect(await idleCDO.BBTranche()).to.equal(BB.address);
    expect(await AAERC20.symbol()).to.equal('AA_wstETH');
    expect(await AAERC20.name()).to.equal('IdleCDO AA Tranche - wstETH');
    expect(await BBERC20.symbol()).to.equal('BB_wstETH');
    expect(await BBERC20.name()).to.equal('IdleCDO BB Tranche - wstETH');
    expect(await idleCDO.token()).to.equal(underlying.address);
    expect(await idleCDO.strategy()).to.equal(strategy.address);
    expect(await idleCDO.strategyToken()).to.equal(wstETH.address);
    expect(await idleCDO.rebalancer()).to.equal(owner.address);
    expect(await idleCDO.trancheAPRSplitRatio()).to.be.equal(BN('20000'));
    expect(await idleCDO.trancheIdealWeightRatio()).to.be.equal(BN('50000'));
    expect(await idleCDO.idealRange()).to.be.equal(BN('10000'));
    expect(await idleCDO.unlentPerc()).to.be.equal(BN('2000'));
    expect(await idleCDO.oneToken()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.priceAA()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.priceBB()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.allowAAWithdraw()).to.equal(true);
    expect(await idleCDO.allowBBWithdraw()).to.equal(true);
    expect(await idleCDO.revertIfTooLow()).to.equal(true);
    expect(await wstETH.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await underlying.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await idleCDO.lastStrategyPrice()).to.be.equal(await wstETH.stEthPerToken());
    expect(await idleCDO.fee()).to.be.equal(BN('10000'));
    expect(await idleCDO.releaseBlocksPeriod()).to.be.equal(BN('1500'));
    expect(await idleCDO.feeReceiver()).to.equal('0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814');
    expect(await idleCDO.guardian()).to.equal(owner.address);
    expect(await idleCDO.weth()).to.equal(weth.address);
    // OwnableUpgradeable
    expect(await idleCDO.owner()).to.equal(owner.address);
    // GuardedLaunchUpgradable
    expect(await idleCDO.limit()).to.be.equal(BN('1000000').mul(ONE_TOKEN(18)));
    expect(await idleCDO.governanceRecoveryFund()).to.equal(owner.address);

    // LidoCDOTrancheGateway
    expect(await gateway.wethToken()).to.be.eq(weth.address)
    expect(await gateway.wstETH()).to.be.eq(wstETH.address)
    expect(await gateway.stETH()).to.be.eq(stETH.address)
    expect(await gateway.idleCDO()).to.be.eq(idleCDO.address)
    expect(await gateway.referral()).to.be.eq(owner.address)
  });

  // ###############
  // AA deposit
  // ###############
  it("should depositAA with ETH", async () => {
    const _amount = BN('1000')
    await depositWithEthViaGateway(AABuyerAddr, "depositAAWithEth", _amount)
    const aaTrancheBal = await AA.balanceOf(AABuyerAddr)

    expect(await stETH.balanceOf(gateway.address)).to.be.eq(0);
    expect(await stETH.balanceOf(idleCDO.address)).to.be.equal(_amount);
    expect(aaTrancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount);
  });

  it("should depositAA with stETH", async () => {
    const _amount = BN('1000')
    await depositWithEthTokenViaGateway(AABuyerAddr, "depositAAWithEthToken", stETH, _amount)
    const aaTrancheBal = await AA.balanceOf(AABuyerAddr)

    expect(await stETH.balanceOf(gateway.address)).to.be.eq(0);
    expect(await stETH.balanceOf(idleCDO.address)).to.be.equal(_amount);
    expect(aaTrancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.sub(_amount));
  });

  it("should depositAA with WETH", async () => {
    const _amount = BN('1000')
    await wrapEth(AABuyerAddr, _amount);
    await depositWithEthTokenViaGateway(AABuyerAddr, "depositAAWithEthToken", weth, _amount)
    const aaTrancheBal = await AA.balanceOf(AABuyerAddr)

    expect(await stETH.balanceOf(gateway.address)).to.be.eq(0);
    expect(await stETH.balanceOf(idleCDO.address)).to.be.equal(_amount);
    expect(aaTrancheBal).to.be.equal(_amount);
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount);
  });

  const wrapEth = async (addr, amount) => {
    await helpers.sudoCall(addr, weth, "deposit", [{ value: amount }]);
  };

  const unwrapWEth = async (addr, amount) => {
    await helpers.sudoCall(addr, weth, "approve", [weth.address, amount])
    await helpers.sudoCall(addr, weth, "withdraw", [amount]);
  };

  const depositWithEthViaGateway = async (addr, funcName, amount) => {
    await helpers.sudoCall(addr, gateway, funcName, [{ value: amount }]);
  };

  const depositWithEthTokenViaGateway = async (addr, funcName, token, amount) => {
    await helpers.sudoCall(addr, token, "approve", [
      gateway.address,
      MAX_UINT,
    ]);
    await helpers.sudoCall(addr, gateway, funcName, [token.address, amount]);
  };

});
