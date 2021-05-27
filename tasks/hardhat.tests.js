const { HardwareSigner } = require("../lib/HardwareSigner");
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/index");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

/**
 * @name deploy
 */
task("deploy")
  .setAction(async function (args, hardh) {
    await run("compile");

    let [signer] = await ethers.getSigners();
    if (hardh.network.name == 'mainnet') {
      signer = new HardwareSigner(ethers.provider, null, "m/44'/60'/0'/0/0");
    }
    const address = await signer.getAddress();

    console.log("deploying with account", address);
    console.log("account balance", BN(await ethers.provider.getBalance(address)).toString(), "\n\n");

    await helpers.prompt("continue? [y/n]");

    console.log("starting...");
    const strategy = await helpers.deployUpgradableContract(hardh, 'IdleStrategy', [mainnetContracts.idleDAIBest], signer);
    const idleCDO = await helpers.deployUpgradableContract(
      hardh,
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

// /**
//  * @name increase-time
//  * @param time
//  */
// task("increase-time-mine")
//   .addPositionalParam("time")
//   .setAction(async function ({ time }) {
//     await ethers.provider.send("evm_increaseTime", [Number(time)]);
//     await run("mine");
//     await run("blocknumber");
//   });
