require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

const deployToken = addresses.deployTokens.DAI;

/**
 * @name deploy
 */
task("deploy", "Deploy IdleCDO, IdleStrategy and Staking contract for rewards with default parameters")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    if (deployToken.cdo && hre.network == 'mainnet') {
      console.log(`CDO Already deployed here ${deployToken.cdo}`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);

    const incentiveTokens = [mainnetContracts.IDLE];
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [deployToken.idleToken, creator], signer);
    const idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('1000000').mul(ONE_TOKEN(deployToken.decimals)), // limit
        deployToken.underlying,
        mainnetContracts.treasuryMultisig, // recovery address
        creator, // guardian
        mainnetContracts.rebalancer,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens
      ],
      signer
    );
    const AAaddr = await idleCDO.AATranche();
    const BBaddr = await idleCDO.BBTranche();
    console.log(`AATranche: ${AAaddr}, BBTranche: ${BBaddr}`);

    const stakingCoolingPeriod = BN(1500);
    const stakingRewardsParams = [
      incentiveTokens,
      creator, // owner / guardian
      idleCDO.address,
      mainnetContracts.devLeagueMultisig, // recovery address
      stakingCoolingPeriod
    ];
    const stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AAaddr, ...stakingRewardsParams], signer
    );
    const stakingRewardsBB = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [BBaddr, ...stakingRewardsParams], signer
    );
    await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);
    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`staking reward contract set`);
    console.log();
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

/**
 * @name upgrade
 */
task("upgrade", "Upgrade IdleCDO instance")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const contractAddress = deployToken.cdo;
    if (!contractAddress && hre.network == 'mainnet') {
      console.log(`IdleCDO Must be deployed`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);

    let signer;
    if (hre.network != 'mainnet') {
      signer = await helpers.impersonateSigner(addresses.idleDeployer);
    } else {
      signer = await helpers.getSigner();
    }

    console.log('Usign signer with address: ', await signer.getAddress());
    await helpers.upgradeContract(contractAddress, 'IdleCDO', [], signer);
    console.log(`IdleCDO upgraded`);
  });
