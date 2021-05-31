require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { expect } = require("chai");

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));

describe("IdleCDO", function () {
  beforeEach(async () => {
    // deploy contracts
    this.signers = await ethers.getSigners();
    this.owner = this.signers[0];

    const IdleCDOTranche = await ethers.getContractFactory("IdleCDOTranche");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const MockIdleToken = await ethers.getContractFactory("MockIdleToken");

    this.underlying = await MockERC20.deploy("DAI", "DAI");
    await this.underlying.deployed();

    this.incentiveToken = await MockERC20.deploy("IDLE", "IDLE");
    await this.incentiveToken.deployed();

    this.idleToken = await MockIdleToken.deploy(this.underlying.address);
    await this.idleToken.deployed();

    this.strategy = await helpers.deployUpgradableContract('IdleStrategy', [this.idleToken.address, this.owner.address], this.owner);
    this.idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        this.underlying.address,
        this.owner.address,
        this.owner.address,
        this.owner.address,
        this.strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000') // ideal value: 50% AA and 50% BB tranches
      ],
      this.owner
    );

    this.AA = await ethers.getContractAt("IdleCDOTranche", await this.idleCDO.AATranche());
    this.BB = await ethers.getContractAt("IdleCDOTranche", await this.idleCDO.BBTranche());
  });

  it("should not reinitialize the contract", async () => {
    await expect(
      this.idleCDO.connect(this.owner).initialize(
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        this.underlying.address,
        this.owner.address,
        this.owner.address,
        this.owner.address,
        this.strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000')
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize params", async () => {
    expect(await this.idleCDO.token()).to.equal(this.underlying.address);
  });

  // TODO add more
});
