require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

task("deploy-with-factory", "Deploy IdleCDO with CDOFactory, IdleStrategy and Staking contract for rewards with default parameters")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const cdoname = args.cdoname;
    let cdoProxyAddressToClone = undefined;
    const deployToken = addresses.deployTokens[cdoname];

    if (deployToken === undefined) {
      console.log(`🛑 deployToken not found with specified cdoname (${cdoname})`)
      return;
    }

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    let cdoFactoryAddress = mainnetContracts.cdoFactory;

    if (hre.network.name === 'hardhat') {
      console.log("\n⚠️  Local network - deploying test CDO\n");
      let { idleCDO, strategy, AAaddr, BBaddr } = await hre.run("deploy", { cdoname: cdoname });
      cdoProxyAddressToClone = idleCDO.address;

      if (cdoFactoryAddress === undefined) {
        console.log("\n⚠️  Local network - cdoFactoryAddress is undefined, deploying CDOFactory\n");
        const cdoFactory = await hre.run("deploy-cdo-factory");
        cdoFactoryAddress = cdoFactory.address;
      }
    }

    if (helpers.isEmptyString(cdoProxyAddressToClone)) {
      console.log("🛑 cdoProxyAddressToClone must be specified")
      return;
    }

    if (helpers.isEmptyString(cdoFactoryAddress)) {
      console.log("🛑 cdoFactoryAddress must be specified")
      return;
    }

    await helpers.prompt("continue? [y/n]", true);

    const incentiveTokens = [mainnetContracts.IDLE];
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [deployToken.idleToken, creator], signer);

    const deployParams = {
      factory: cdoFactoryAddress,
      cdoname: cdoname,
      // cdoImplementation: implAddress,
      cloneFromProxy: cdoProxyAddressToClone,
      limit: BN('500000').mul(ONE_TOKEN(deployToken.decimals)).toString(), // limit
      governanceFund: mainnetContracts.treasuryMultisig, // recovery address
      strategy: strategy.address,
      trancheAPRSplitRatio: BN('20000').toString(), // apr split: 20% interest to AA and 80% BB
      trancheIdealWeightRatio: BN('50000').toString(), // ideal value: 50% AA and 50% BB tranches
      incentiveTokens: [mainnetContracts.IDLE].join(","),
    }
    const idleCDOAddress = await hre.run("deploy-cdo-with-factory", deployParams);
    const idleCDO = await ethers.getContractAt("IdleCDO", idleCDOAddress);

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
