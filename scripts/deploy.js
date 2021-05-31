const hre = require("hardhat");
const { HardwareSigner } = require("../lib/HardwareSigner");
const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require("../lib/addresses");
const helpers = require("./helpers");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));

const LedgerSigner = HardwareSigner;
const mainnetContracts = addresses.IdleTokens.mainnet;

async function main() {
  // let [signer] = await ethers.getSigners();
  // if (hre.network.name == 'mainnet') {
  //   signer = new HardwareSigner(ethers.provider, null, "m/44'/60'/0'/0/0");
  // }
  // const address = await signer.getAddress();
  //
  // console.log("deploying with account", address);
  // console.log("account balance", BN(await ethers.provider.getBalance(address)).toString(), "\n\n");
  //
  // await helpers.prompt("continue? [y/n]");
  //
  // console.log("starting...");
  // const strategy = await helpers.deployUpgradableContract('IdleStrategy', [mainnetContracts.idleDAIBest], signer);
  // const idleCDO = await helpers.deployUpgradableContract(
  //   'IdleCDO',
  //   [
  //     BN('1000000').mul(ONE_TOKEN(18)), // limit
  //     mainnetContracts.DAI,
  //     mainnetContracts.devLeagueMultisig,
  //     mainnetContracts.rebalancer,
  //     strategy.address,
  //     BN('10000'), // apr split: 10% interest to AA and 90% BB
  //     BN('50000') // ideal value: 50% AA and 50% BB tranches
  //   ],
  //   signer
  // );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
