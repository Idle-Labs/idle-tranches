const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require('../lib/addresses');
const helpers = require('../scripts/helpers');
const BN = v => BigNumber.from(v.toString());

const waitBlocks = async (n) => {
  log(`mining ${n} blocks...`);
  for (var i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine");
  };
}

// pretty number
const pn = (_n) => {
  const n = _n.toString();
  let s = "";
  for (let i = 0; i < n.length; i++) {
    if (i != 0 && i % 3 == 0) {
      s = "_" + s;
    }

    s = n[n.length - 1 - i] + s;
  };

  return s;
}

const erc20Utils = (decimals) => {
  const one = BN("10").pow(BN(decimals));
  const toUnits = v => BN(v).div(one);
  const toUnitsS = v => toUnits(BN(v)).toString();
  const fromUnits = u => BN(u).mul(one);

  return {
    toUnits,
    toUnitsS,
    fromUnits,
  }
}

const debug = process.env.DEBUG != undefined && process.env.DEBUG != "";

const log = function() {
  if (!debug) {
    return;
  }

  console.log(...arguments);
}

describe('IdleCDOTrancheRewards', function() {
  beforeEach(async () => {
    const [owner, recoveryFund, ...accounts] = await ethers.getSigners();
    this.owner = owner;
    this.recoveryFund = recoveryFund;
    this.accounts = accounts;
    this.tokenUtils = erc20Utils("18");
    this.coolingPeriod = 100;

    const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
    this.accounts = accounts;

    this.tranche = await MockERC20.deploy("Test", "TEST");
    this.rewardToken1 = await MockERC20.deploy("Reward 1", "REWARD1");

    const MockIdleCDO = await hre.ethers.getContractFactory("MockIdleCDO");
    this.cdo = await MockIdleCDO.deploy([this.rewardToken1.address]);

    const IdleCDOTrancheRewards = await hre.ethers.getContractFactory("IdleCDOTrancheRewards");
    this.contract = await upgrades.deployProxy(IdleCDOTrancheRewards, [
      this.tranche.address,
      [this.rewardToken1.address],
      owner.address,
      this.cdo.address,
      this.recoveryFund.address,
      this.coolingPeriod,
    ]);

    await this.cdo.setTrancheRewardsContract(this.contract.address);
  });

  const stake = async (user, amount) => {
    amount = this.tokenUtils.fromUnits(amount);
    // owner sends amount to user
    await this.tranche.connect(this.owner).transfer(user.address, amount);
    // user approves amount for contract
    await this.tranche.connect(user).approve(this.contract.address, amount);
    // user stakes amount
    await this.contract.connect(user).stake(amount);
  }

  const stakeFor = async (user, amount) => {
    amount = this.tokenUtils.fromUnits(amount);
    // owner sends amount to cdo address
    await this.tranche.connect(this.owner).transfer(this.cdo.address, amount);
    const signer = await helpers.impersonateSigner(this.cdo.address);
    await this.tranche.connect(signer).approve(this.contract.address, amount);
    // cdo stakes amount for the user
    await this.contract.connect(signer).stakeFor(user.address, amount);
  }

  const depositReward = async (amount) => {
    amount = this.tokenUtils.fromUnits(amount);
    await this.rewardToken1.transfer(this.cdo.address, amount);
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, amount);
  }

  const unstake = async (user, amount, blocksToMine) => {
    if (blocksToMine == undefined) {
      blocksToMine = 0;
    }

    await waitBlocks(blocksToMine);

    amount = this.tokenUtils.fromUnits(amount);
    await this.contract.connect(user).unstake(amount);
  }

  const claim = async (user) => {
    await this.contract.connect(user).claim();
  }

  const checkUserStakes = async (user, expected) => {
    expect(await this.contract.usersStakes(user.address)).to.be.closeTo(this.tokenUtils.fromUnits(expected), "60" /* 60 WEI */);
  }

  const checkExpectedUserRewards = async (user, expected) => {
    expect(await this.contract.expectedUserReward(user.address, this.rewardToken1.address)).to.be.closeTo(this.tokenUtils.fromUnits(expected), "60" /* 60 WEI */);
  }

  const checkRewardBalance = async (user, expected) => {
    expect(await this.rewardToken1.balanceOf(user.address)).to.be.closeTo(this.tokenUtils.fromUnits(expected), "60" /* 60 WEI */);
  }

  const dump = async () => {
    if (!debug) {
      return;
    }

    const [user1, user2] = this.accounts;

    log("\n-----------------------------");
    log("total rewards           ", pn(await this.rewardToken1.balanceOf(this.contract.address)));
    log("rewards index           ", pn(await this.contract.rewardsIndexes(this.rewardToken1.address)));
    log("adjusted rewards index  ", pn(await this.contract.adjustedRewardIndex(this.rewardToken1.address)));
    log("locked rewards          ", pn(await this.contract.lockedRewards(this.rewardToken1.address)));
    log("locked block            ", pn(await this.contract.lockedRewardsLastBlock(this.rewardToken1.address)));
    log("current block           ", pn((await ethers.provider.getBlockNumber())));
    log("cooling period          ", pn((await this.contract.coolingPeriod())));
    log("total staked            ", pn(await this.contract.totalStaked()));

    log("");
    log("user1 stakes            ", pn(await this.contract.usersStakes(user1.address)));
    log("user1 reward balance    ", pn(await this.rewardToken1.balanceOf(user1.address)));
    log("user1 index             ", pn(await this.contract.usersIndexes(user1.address, this.rewardToken1.address)));
    log("user1 expected          ", pn(await this.contract.expectedUserReward(user1.address, this.rewardToken1.address)));

    log("");
    log("user2 stakes            ", pn(await this.contract.usersStakes(user2.address)));
    log("user2 reward balance    ", pn(await this.rewardToken1.balanceOf(user2.address)));
    log("user2 index             ", pn(await this.contract.usersIndexes(user2.address, this.rewardToken1.address)));
    log("user2 expected          ", pn(await this.contract.expectedUserReward(user2.address, this.rewardToken1.address)));
    log("-----------------------------\n");
  }

  it ('stake', async () => {
    const [user1] = this.accounts;
    await stake(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");

    await waitBlocks(this.coolingPeriod / 2);
    await checkExpectedUserRewards(user1, "50");

    await waitBlocks(this.coolingPeriod / 2);
    await checkExpectedUserRewards(user1, "100");

    await stake(user1, "10")
    await checkUserStakes(user1, "20");
    await checkExpectedUserRewards(user1, "100");
  });

  it ('stakeFor', async () => {
    const [user1] = this.accounts;
    await stake(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");
    await dump();

    await depositReward("100");
    let depositBlockNumber = await ethers.provider.getBlockNumber();
    await dump();
    await checkExpectedUserRewards(user1, "0");

    await stake(user1, "10")
    await stake(user1, "10")
    await stake(user1, "10")
    const blocksMined = (await ethers.provider.getBlockNumber()) - depositBlockNumber;
    const expectedReward = blocksMined * 100 / this.coolingPeriod;
    await dump();

    await checkExpectedUserRewards(user1, expectedReward.toString());
    await waitBlocks(this.coolingPeriod - blocksMined - 1);
    await checkExpectedUserRewards(user1, "99");
    await waitBlocks(1);

    await checkUserStakes(user1, "40");
    await checkExpectedUserRewards(user1, "100");
    await dump();
  });

  it ('unstake', async () => {
    const [user1] = this.accounts;
    await stake(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");

    await unstake(user1, "10")
    await checkUserStakes(user1, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkRewardBalance(user1, "100");
  });

  it ('unstake after stakeFor', async () => {
    const [user1] = this.accounts;
    await stakeFor(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");

    await unstake(user1, "10")
    await checkUserStakes(user1, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkRewardBalance(user1, "100");
  });

  it ('unstake before cooling period are proportional', async () => {
    const [user1, user2] = this.accounts;
    await stake(user1, "10")
    await stake(user2, "10")

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");

    await waitBlocks(this.coolingPeriod / 2);
    await checkExpectedUserRewards(user1, "25");
    await checkExpectedUserRewards(user2, "25");

    await waitBlocks(this.coolingPeriod / 2);
    await checkExpectedUserRewards(user1, "50");
    await checkExpectedUserRewards(user2, "50");
  });

  it ('owner can set the cooling period', async () => {
    expect(await this.contract.coolingPeriod()).to.be.equal(this.coolingPeriod);

    await expect(
      this.contract.connect(this.accounts[0]).setCoolingPeriod("0")
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await this.contract.connect(this.owner).setCoolingPeriod(this.coolingPeriod * 2);
    const newCoolingPeriod = await this.contract.coolingPeriod();
    expect(newCoolingPeriod).to.not.be.equal(this.coolingPeriod);
    expect(newCoolingPeriod).to.be.equal(this.coolingPeriod * 2);
  });

  it ('unstake when paused should not claim rewards', async () => {
    const [user1] = this.accounts;
    await stake(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");

    await this.contract.connect(this.owner).pause();
    await unstake(user1, "10")

    await checkUserStakes(user1, "0");
    await checkExpectedUserRewards(user1, "0");
    // rewards are not sent to the user
    await checkRewardBalance(user1, "0");
  });

  it ('claim', async () => {
    const [user1] = this.accounts;
    await stake(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");
    await claim(user1);

    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");
    await checkRewardBalance(user1, "100");
  });

  it ('claim after stakeFor', async () => {
    const [user1] = this.accounts;
    await stakeFor(user1, "10")
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");
    await claim(user1);

    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");
    await checkRewardBalance(user1, "100");
  });

  it ('expectedUserReward', async () => {
    const [user1] = this.accounts;
    await stake(user1, "10")
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "100");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "200");

    await claim(user1);

    await checkExpectedUserRewards(user1, "0");

    const unsupportedTokenAddress = this.accounts[0].address;
    await expect(
      this.contract.expectedUserReward(user1.address, unsupportedTokenAddress)
    ).to.be.revertedWith("!SUPPORTED");
  });

  it ('expectedUserReward after stakeFor', async () => {
    const [user1] = this.accounts;
    await stakeFor(user1, "10")
    await checkExpectedUserRewards(user1, "0");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "0");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");

    await depositReward("100");
    await checkExpectedUserRewards(user1, "100");
    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "200");

    await claim(user1);

    await checkExpectedUserRewards(user1, "0");
  });

  it ('throws an error if token is not supported', async () => {
    const [user1] = this.accounts;
    const unsupportedTokenAddress = this.accounts[0].address;
    await expect(
      this.contract.expectedUserReward(user1.address, unsupportedTokenAddress)
    ).to.be.revertedWith("!SUPPORTED");
  });

  it('full test', async () => {
    const [user1, user2, user3] = this.accounts;

    log("user1 stakes 10");
    await stake(user1, "10")
    await dump();
    await checkUserStakes(user1, "10");
    await checkUserStakes(user2, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");

    log("deposit 100 reward1");
    await depositReward("100");
    await dump();
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");

    await waitBlocks(this.coolingPeriod);
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("user2 stakes 10");
    await stake(user2, "10");
    await dump();
    await checkUserStakes(user1, "10");
    await checkUserStakes(user2, "10");
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("user1 stakes 30");
    await stake(user1, "20")
    await stake(user1, "10")
    await dump();
    await checkUserStakes(user1, "40");
    await checkUserStakes(user2, "10");
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("deposit 100 reward1");
    await depositReward("100");
    await waitBlocks(this.coolingPeriod);
    await dump();
    await checkExpectedUserRewards(user1, "180");
    await checkExpectedUserRewards(user2, "20");

    await checkRewardBalance(user1, "0");
    await checkRewardBalance(user2, "0");

    log("user1 unstakes 40");
    await unstake(user1 ,"40");
    await dump();
    await checkUserStakes(user1, "0");
    await checkUserStakes(user2, "10");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "20");
    await checkRewardBalance(user1, "180");
    await checkRewardBalance(user2, "0");

    log("user2 unstakes 20");
    await unstake(user2, "10");
    await dump();
    await checkUserStakes(user1, "0");
    await checkUserStakes(user2, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");
    await checkRewardBalance(user1, "180");
    await checkRewardBalance(user2, "20");

    log("user1 stakes 10");
    await stake(user1, "10");
    await dump();
    await checkUserStakes(user1, "10");
    await checkUserStakes(user2, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");

    log("deposit 100 reward1");
    await depositReward("100");
    await waitBlocks(this.coolingPeriod);
    await dump();
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("user1 calls claim");
    await this.contract.connect(user1).claim();
    await checkUserStakes(user1, "10");
    await checkExpectedUserRewards(user1, "0");
    await checkRewardBalance(user1, "280");
    await dump();
  });

  it("claims the maximum available if expectedUserReward is more", async () => {
    const user = this.accounts[0];
    await stake(user, "10")
    await depositReward("100");
    const depositBlockNumber = await ethers.provider.getBlockNumber();
    await checkExpectedUserRewards(user, "0");

    await stake(user, "20")
    await stake(user, "30")

    const blocksMined = (await ethers.provider.getBlockNumber()) - depositBlockNumber;
    const expectedReward = blocksMined * 100 / this.coolingPeriod;
    await checkExpectedUserRewards(user, expectedReward.toString());

    await waitBlocks(this.coolingPeriod - blocksMined);
    await checkExpectedUserRewards(user, "100");

    // for rounding problems, the user expected Reward is
    // 100_000_000_000_000_000_020 instead of
    // 100_000_000_000_000_000_000
    const expected = BN(await this.contract.expectedUserReward(user.address, this.rewardToken1.address));
    const balance = BN(await this.rewardToken1.balanceOf(this.contract.address));
    expect(expected.gt(balance)).to.be.true;

    await dump();
    await unstake(user, "60");
    await dump();

    const balanceAfter = BN(await this.rewardToken1.balanceOf(this.contract.address));
    expect(BN(await this.rewardToken1.balanceOf(this.contract.address))).to.be.bignumber.equal(BN("0"));
  });

  it("can be paused/unpaused by owner", async () => {
    expect(await this.contract.paused()).to.be.false;
    await this.contract.connect(this.owner).pause();
    expect(await this.contract.paused()).to.be.true;
    await this.contract.connect(this.owner).unpause();
    expect(await this.contract.paused()).to.be.false;
  });

  it("cannot be paused by non-owner", async () => {
    expect(await this.contract.paused()).to.be.false;
    await expect(
      this.contract.connect(this.accounts[0]).pause()
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("cannot be unpaused by non-owner", async () => {
    await this.contract.connect(this.owner).pause();
    expect(await this.contract.paused()).to.be.true;
    await expect(
      this.contract.connect(this.accounts[0]).unpause()
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should revert when calling stake and contract is paused", async () => {
    await this.contract.connect(this.owner).pause();
    await expect(
      stake(this.accounts[0], "10")
    ).to.be.revertedWith("Pausable: paused");
  });

  it("should revert when calling claim and contract is paused", async () => {
    await this.contract.connect(this.owner).pause();
    await expect(
      claim(this.accounts[0])
    ).to.be.revertedWith("Pausable: paused");
  });

  it("transferToken can be called by owner", async () => {
    await this.rewardToken1.connect(this.owner).transfer(this.contract.address, this.tokenUtils.fromUnits("100"));

    expect(await this.rewardToken1.balanceOf(this.contract.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("100"));
    expect(await this.rewardToken1.balanceOf(this.recoveryFund.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("0"));

    await this.contract.connect(this.owner).transferToken(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));

    expect(await this.rewardToken1.balanceOf(this.contract.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("0"));
    expect(await this.rewardToken1.balanceOf(this.recoveryFund.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("100"));
  });

  it("transferToken failes if address is 0", async () => {
    await expect(
      this.contract.connect(this.owner).transferToken(addresses.addr0, this.tokenUtils.fromUnits("100"))
    ).to.be.revertedWith("Address is 0");
  });

  it("transferToken cannot be called by non-owner", async () => {
    await expect(
      this.contract.connect(this.accounts[0]).transferToken(this.rewardToken1.address, this.tokenUtils.fromUnits("100"))
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("depositReward can be called by the CDO", async () => {
    await this.rewardToken1.connect(this.owner).transfer(this.cdo.address, this.tokenUtils.fromUnits("100"));

    expect(await this.rewardToken1.balanceOf(this.cdo.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("100"));
    expect(await this.rewardToken1.balanceOf(this.contract.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("0"));

    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));

    expect(await this.rewardToken1.balanceOf(this.cdo.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("0"));
    expect(await this.rewardToken1.balanceOf(this.contract.address)).to.be.bignumber.equal(this.tokenUtils.fromUnits("100"));
  });

  it("depositReward fails if called by an address different from the CDO", async () => {
    await expect(
      this.contract.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"))
    ).to.be.revertedWith("!AUTH");
  })

  it("depositReward fails if called with an unsupported token", async () => {
    const unsupportedTokenAddress = this.accounts[0].address;
    await expect(
      this.cdo.connect(this.owner).depositRewardWithoutApprove(unsupportedTokenAddress, this.tokenUtils.fromUnits("100"))
    ).to.be.revertedWith("!SUPPORTED");
  })
});
