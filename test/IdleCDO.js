require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { expect } = require("chai");

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');

describe("IdleCDO", function () {
  beforeEach(async () => {
    // deploy contracts
    signers = await ethers.getSigners();
    owner = signers[0];

    const IdleCDOTranche = await ethers.getContractFactory("IdleCDOTranche");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const MockIdleToken = await ethers.getContractFactory("MockIdleToken");

    weth = await MockERC20.deploy("WETH", "WETH");
    await weth.deployed();

    underlying = await MockERC20.deploy("DAI", "DAI");
    await underlying.deployed();

    incentiveToken = await MockERC20.deploy("IDLE", "IDLE");
    await incentiveToken.deployed();
    incentiveTokens = [incentiveToken.address];

    idleToken = await MockIdleToken.deploy(underlying.address);
    await idleToken.deployed();

    strategy = await helpers.deployUpgradableContract('IdleStrategy', [idleToken.address, owner.address], owner);
    idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens
      ],
      owner
    );

    AA = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
    BB = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());

    const stakingRewardsParams = [
      incentiveTokens,
      owner.address, // owner / guardian
      idleCDO.address,
      owner.address // recovery address
    ];
    stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AA.address, ...stakingRewardsParams], owner
    );
    stakingRewardsBB = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [BB.address, ...stakingRewardsParams], owner
    );
    await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);

    // set IdleToken mocked params
    await idleToken.setTokenPriceWithFee(BN(10**18));
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
        incentiveTokens
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize params", async () => {
    expect(await idleCDO.AATranche()).to.equal(AA.address);
    expect(await idleCDO.BBTranche()).to.equal(BB.address);
    expect(await idleCDO.token()).to.equal(underlying.address);
    expect(await idleCDO.strategy()).to.equal(strategy.address);
    expect(await idleCDO.strategyToken()).to.equal(idleToken.address);
    expect(await idleCDO.rebalancer()).to.equal(owner.address);
    expect(await idleCDO.trancheAPRSplitRatio()).to.be.bignumber.equal(BN('20000'));
    expect(await idleCDO.trancheIdealWeightRatio()).to.be.bignumber.equal(BN('50000'));
    expect(await idleCDO.idealRange()).to.be.bignumber.equal(BN('10000'));
    expect(await idleCDO.oneToken()).to.be.bignumber.equal(BN(10**18));
    expect(await idleCDO.priceAA()).to.be.bignumber.equal(BN(10**18));
    expect(await idleCDO.priceBB()).to.be.bignumber.equal(BN(10**18));
    expect(await idleCDO.lastAAPrice()).to.be.bignumber.equal(BN(10**18));
    expect(await idleCDO.lastBBPrice()).to.be.bignumber.equal(BN(10**18));
    expect(await idleCDO.allowAAWithdraw()).to.equal(true);
    expect(await idleCDO.allowBBWithdraw()).to.equal(true);
    expect(await idleCDO.revertIfTooLow()).to.equal(true);
    expect(await idleToken.allowance(idleCDO.address, strategy.address)).to.be.bignumber.equal(MAX_UINT);
    expect(await underlying.allowance(idleCDO.address, strategy.address)).to.be.bignumber.equal(MAX_UINT);
    expect(await idleCDO.lastStrategyPrice()).to.be.bignumber.equal(BN(10**18));
    expect(await idleCDO.fee()).to.be.bignumber.equal(BN('10000'));
    expect(await idleCDO.feeReceiver()).to.equal('0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4');
    expect(await idleCDO.guardian()).to.equal(owner.address);
    expect(await idleCDO.weth()).to.equal('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2');
    expect(await idleCDO.incentiveTokens(0)).to.equal(incentiveTokens[0]);
    // OwnableUpgradeable
    expect(await idleCDO.owner()).to.equal(owner.address);
    // GuardedLaunchUpgradable
    expect(await idleCDO.limit()).to.be.bignumber.equal(BN('1000000').mul(ONE_TOKEN(18)));
    expect(await idleCDO.governanceRecoveryFund()).to.equal(owner.address);
  });

  it("should initialize params", async () => {

  });
  // TODO add more
});
