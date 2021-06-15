const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require('../lib/addresses');

const BN = v => BigNumber.from(v.toString());

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
      addresses.addr0,
    ]);

    await this.cdo.setTrancheRewardsContract(this.contract.address);

    this.tokenUtils = erc20Utils("18");
    await this.rewardToken1.connect(owner).approve(this.contract.address, this.tokenUtils.fromUnits("10000").toString());
  });

  it('test', async () => {
    const [user0, user1, user2, user3] = this.accounts;

    const check = async () => {
      log("\n-----------------------------");
      log("CDO available rewards   ", this.tokenUtils.toUnitsS(await this.rewardToken1.balanceOf(this.cdo.address)));
      log("total rewards           ", this.tokenUtils.toUnitsS(await this.contract.totalRewards(this.rewardToken1.address)));
      log("rewards index           ", this.tokenUtils.toUnitsS(await this.contract.rewardsIndexes(this.rewardToken1.address)));

      log("contract tranche balance", this.tokenUtils.toUnitsS(await this.tranche.balanceOf(this.contract.address)));
      log("total staked            ", this.tokenUtils.toUnitsS(await this.contract.totalStaked()));

      log("");
      log("user1 stakes            ", this.tokenUtils.toUnitsS(await this.contract.usersStakes(user1.address)));
      log("user1 reward balance    ", this.tokenUtils.toUnitsS(await this.rewardToken1.balanceOf(user1.address)));
      log("user1 index             ", this.tokenUtils.toUnitsS(await this.contract.usersIndexes(this.rewardToken1.address, user1.address)));

      log("");
      log("user2 stakes            ", this.tokenUtils.toUnitsS(await this.contract.usersStakes(user2.address)));
      log("user2 reward balance    ", this.tokenUtils.toUnitsS(await this.rewardToken1.balanceOf(user2.address)));
      log("user2 index             ", this.tokenUtils.toUnitsS(await this.contract.usersIndexes(this.rewardToken1.address, user2.address)));
      log("-----------------------------\n");
    }

    const stake = async(user, amount) => {
      amount = this.tokenUtils.fromUnits(amount);
      await this.tranche.transfer(user.address, amount);
      await this.tranche.connect(user).approve(this.contract.address, amount);
      await this.contract.connect(user).stake(amount);
    }

    await check();

    log("user1 stakes 100");
    await stake(user1, "100")
    await check();

    log("deposit 1000 reward1");
    await this.rewardToken1.connect(this.owner).transfer(this.cdo.address, this.tokenUtils.fromUnits("1000").toString());
    await check();

    log("user2 stakes 100");
    await stake(user2, "100")
    await check();

    log("deposit 1000 reward1");
    await this.rewardToken1.connect(this.owner).transfer(this.cdo.address, this.tokenUtils.fromUnits("1000").toString());
    await check();

    await stake(user2, "1");
    log("stake 1 from user 2")
    await check();

    log("stake 1 from user 1")
    await stake(user1, "1");
    await check();

  });
});
