require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

/**
 * @name deploy
 * eg `npx hardhat deploy --cdoname idledai`
 */
task("deploy", "Deploy IdleCDO, IdleStrategy and Staking contract for rewards with default parameters")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const deployToken = addresses.deployTokens[args.cdoname];

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    if (deployToken.cdo && deployToken.cdo.cdoAddr && hre.network == 'mainnet') {
      console.log(`CDO Already deployed here ${deployToken.cdo.cdoAddr}`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);

    const incentiveTokens = [mainnetContracts.IDLE];
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [deployToken.idleToken, creator], signer);
    const idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('500000').mul(ONE_TOKEN(deployToken.decimals)), // limit
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
    await strategy.connect(signer).setWhitelistedCDO(idleCDO.address);
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
    await idleCDO.connect(signer).setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);
    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`staking reward contract set`);
    console.log();
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

/**
 * @name info
 */
task("info", "IdleCDO info")
  .addParam("cdo")
  .setAction(async (args) => {
    console.log(args.cdo);
    let idleCDO = await ethers.getContractAt("IdleCDO", args.cdo);
    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`AATranche: ${await idleCDO.AATranche()}, BBTranche: ${await idleCDO.BBTranche()}`);
    console.log(`IdleStrategy: ${await idleCDO.strategy()}`);
  });

/**
 * @name upgrade-cdo
 */
task("upgrade-cdo", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const deployToken = addresses.deployTokens[args.cdoname];

    const contractAddress = deployToken.cdo.cdoAddr;
    if (!contractAddress) {
      console.log(`IdleCDO Must be deployed`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');
    await helpers.upgradeContract(contractAddress, 'IdleCDO', signer);
    console.log(`IdleCDO upgraded`);
  });

/**
 * @name upgrade-strategy
 */
task("upgrade-strategy", "Upgrade IdleCDO strategy")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const deployToken = addresses.deployTokens[args.cdoname];
    console.log('deployToken', deployToken)
    console.log('deployToken.cdo', deployToken.cdo)
    const contractAddress = deployToken.cdo.strategy;
    if (!contractAddress) {
      console.log(`IdleCDO strategy Must be deployed`);
      return;
    }
    console.log(contractAddress);

    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');
    await helpers.upgradeContract(contractAddress, 'IdleStrategy', signer);
    console.log(`IdleStrategy upgraded`);
  });

/**
 * @name get-signer-or-fake
 */
task("get-signer-or-fake", "Upgrade IdleCDO instance")
  .setAction(async (args) => {
    let signer;
    if (hre.network.name !== 'mainnet') {
      signer = await helpers.impersonateSigner(args.fakeAddress || addresses.idleDeployer);
    } else {
      signer = await helpers.getSigner();
    }
    console.log('Using signer with address: ', await signer.getAddress());
    return signer;
  });
