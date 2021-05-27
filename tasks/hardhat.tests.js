require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/index");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

/**
 * @name deploy
 */
task("deploy", "Deploy IdleCDO and IdleStrategy with default parameters")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    await helpers.prompt("continue? [y/n]");
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [mainnetContracts.idleDAIBest], signer);
    const idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('1000000').mul(ONE_TOKEN(18)), // limit
        mainnetContracts.DAI,
        mainnetContracts.devLeagueMultisig,
        mainnetContracts.rebalancer,
        strategy.address,
        BN('10000'), // apr split: 10% interest to AA and 90% BB
        BN('50000') // ideal value: 50% AA and 50% BB tranches
      ],
      signer
    );
  });

/**
 * @name test-price
 */
task("test-price")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("deploy");

  });
