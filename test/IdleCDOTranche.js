require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");
const { expect } = require("chai");

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));

describe("IdleCDOTranche", function () {
  beforeEach(async () => {
    // deploy contracts
    signers = await ethers.getSigners();
    owner = signers[0];
    random = signers[1];

    const IdleCDOTranche = await ethers.getContractFactory("IdleCDOTranche");
    tranche = await IdleCDOTranche.deploy("AA tranche", "AA");
  });

  it("should initialize variables in constructor", async () => {
    expect(await tranche.name()).to.be.equal("AA tranche");
    expect(await tranche.symbol()).to.be.equal("AA");
    expect(await tranche.minter()).to.be.equal(owner.address);
  });

  it("should allow minter and only minter to mint", async () => {
    await expect(
      tranche.connect(random).mint(random.address, BN('100'))
    ).to.be.revertedWith("6");

    await tranche.mint(random.address, BN('10000'));
    // minus 1000 is because on first mint 1000 wei are burned
    expect(await tranche.balanceOf(random.address)).to.be.equal(10000 - 1000);
  });

  it("should allow minter and only minter to burn", async () => {
    await tranche.mint(random.address, BN('10000'));

    await expect(
      tranche.connect(random).burn(random.address, BN('50'))
    ).to.be.revertedWith("6");

    await tranche.burn(random.address, BN('50'));

    // minus 1000 is because on first mint 1000 wei are burned
    expect(await tranche.balanceOf(random.address)).to.be.equal(10000 - 50 - 1000);
  });
});
