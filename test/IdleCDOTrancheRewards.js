const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require('../lib/addresses');

const BN = v => BigNumber.from(v.toString());

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

const log = console.log;

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

  it('test', async () => {
    const [user1, user2, user3] = this.accounts;

    const check = async () => {
      log("\n-----------------------------");
      // log("CDO available rewards   ", this.tokenUtils.toUnitsS(await this.rewardToken1.balanceOf(this.cdo.address)));
      log("total rewards           ", pn(await this.contract.totalRewards(this.rewardToken1.address)));
      log("rewards index           ", pn(await this.contract.rewardsIndexes(this.rewardToken1.address)));
      log("total staked            ", pn(await this.contract.totalStaked()));

      log("");
      log("user1 stakes            ", pn(await this.contract.usersStakes(user1.address)));
      log("user1 reward balance    ", pn(await this.rewardToken1.balanceOf(user1.address)));
      log("user1 index             ", pn(await this.contract.usersIndexes(user1.address, this.rewardToken1.address)));
      log("user1 expected          ", pn(await this.contract.userExpectedReward(user1.address, this.rewardToken1.address)));

      log("");
      log("user2 stakes            ", pn(await this.contract.usersStakes(user2.address)));
      log("user2 reward balance    ", pn(await this.rewardToken1.balanceOf(user2.address)));
      log("user2 index             ", pn(await this.contract.usersIndexes(user2.address, this.rewardToken1.address)));
      log("user2 expected          ", pn(await this.contract.userExpectedReward(user2.address, this.rewardToken1.address)));
      log("-----------------------------\n");
    }

    const stake = async(user, amount) => {
      await this.tranche.transfer(user.address, amount);
      await this.tranche.connect(user).approve(this.contract.address, amount);
      await this.contract.connect(user).stake(amount);
    }

    log("user1 stakes 10");
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await check();

    log("deposit 100 reward1");
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));
    await check();

    log("user2 stakes 10");
    await stake(user2, this.tokenUtils.fromUnits("10"))
    await check();

    log("user1 stakes 30");
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await stake(user1, this.tokenUtils.fromUnits("10"))
    await check();

    log("deposit 100 reward1");
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));
    await check();

    log("user2 stakes 10");
    await stake(user2, this.tokenUtils.fromUnits("10"))
    await check();

    log("deposit 100 reward1");
    await this.cdo.connect(this.owner).depositReward(this.rewardToken1.address, this.tokenUtils.fromUnits("100"));
    await check();
  });
});
