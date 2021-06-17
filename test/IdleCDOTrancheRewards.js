const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require('../lib/addresses');

const BN = v => BigNumber.from(v.toString());

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
    const [owner, ...accounts] = await ethers.getSigners();
    this.owner = owner;
    this.accounts = accounts;
    this.tokenUtils = erc20Utils("18");

    const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
    this.accounts = accounts;

    this.tranche = await MockERC20.deploy("Test", "TEST");
    this.rewardToken1 = await MockERC20.deploy("Reward 1", "REWARD1");

    const MockIdleCDO = await hre.ethers.getContractFactory("MockIdleCDO");
    this.cdo = await MockIdleCDO.deploy([this.rewardToken1.address]);
    this.rewardToken1.transfer(this.cdo.address, this.tokenUtils.fromUnits("10000"));

    const IdleCDOTrancheRewards = await hre.ethers.getContractFactory("IdleCDOTrancheRewards");
    this.contract = await upgrades.deployProxy(IdleCDOTrancheRewards, [
      this.tranche.address,
      [this.rewardToken1.address],
      owner.address,
      this.cdo.address,
      addresses.addr0,
    ]);

    await this.cdo.setTrancheRewardsContract(this.contract.address);

    await this.rewardToken1.connect(owner).approve(this.contract.address, this.tokenUtils.fromUnits("10000").toString());
  });

  it('full test', async () => {
    const [user1, user2, user3] = this.accounts;

    const dump = async () => {
      if (!debug) {
        return;
      }

      log("\n-----------------------------");
      log("total rewards           ", pn(await this.rewardToken1.balanceOf(this.contract.address)));
      log("rewards index           ", pn(await this.contract.rewardsIndexes(this.rewardToken1.address)));
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

    const stake = async (user, amount) => {
      await this.tranche.transfer(user.address, amount);
      await this.tranche.connect(user).approve(this.contract.address, amount);
      await this.contract.connect(user).stake(amount);
    }

    const checkUserStakes = async (user, expected) => {
      expect(await this.contract.usersStakes(user.address)).to.be.closeTo(this.tokenUtils.fromUnits(expected), "40" /* 40 WEI */);
    }

    const checkExpectedUserRewards = async (user, expected) => {
      expect(await this.contract.expectedUserReward(user.address, this.rewardToken1.address)).to.be.closeTo(this.tokenUtils.fromUnits(expected), "40" /* 40 WEI */);
    }

    const checkRewardBalance = async (user, expected) => {
      expect(await this.rewardToken1.balanceOf(user.address)).to.be.closeTo(this.tokenUtils.fromUnits(expected), "40" /* 40 WEI */);
    }

    log("user1 stakes 10");
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await dump();
    await checkUserStakes(user1, "10");
    await checkUserStakes(user2, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");

    log("deposit 100 reward1");
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));
    await dump();
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("user2 stakes 10");
    await stake(user2, this.tokenUtils.fromUnits("10"))
    await dump();
    await checkUserStakes(user1, "10");
    await checkUserStakes(user2, "10");
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("user1 stakes 30");
    await stake(user1, this.tokenUtils.fromUnits("20"))
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await dump();
    await checkUserStakes(user1, "40");
    await checkUserStakes(user2, "10");
    await checkExpectedUserRewards(user1, "100");
    await checkExpectedUserRewards(user2, "0");

    log("deposit 100 reward1");
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));
    await dump();
    await checkExpectedUserRewards(user1, "180");
    await checkExpectedUserRewards(user2, "20");

    await checkRewardBalance(user1, "0");
    await checkRewardBalance(user2, "0");

    log("user1 unstakes 40");
    await this.contract.connect(user1).unstake(this.tokenUtils.fromUnits("40"));
    await dump();
    await checkUserStakes(user1, "0");
    await checkUserStakes(user2, "10");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "20");
    await checkRewardBalance(user1, "180");
    await checkRewardBalance(user2, "0");

    log("user2 unstakes 20");
    await this.contract.connect(user2).unstake(this.tokenUtils.fromUnits("10"));
    await dump();
    await checkUserStakes(user1, "0");
    await checkUserStakes(user2, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");
    await checkRewardBalance(user1, "180");
    await checkRewardBalance(user2, "20");

    log("user1 stakes 10");
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await dump();
    await checkUserStakes(user1, "10");
    await checkUserStakes(user2, "0");
    await checkExpectedUserRewards(user1, "0");
    await checkExpectedUserRewards(user2, "0");

    log("deposit 100 reward1");
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));
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
});
