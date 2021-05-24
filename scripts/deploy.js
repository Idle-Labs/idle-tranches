const hre = require("hardhat");
const { HardwareSigner } = require("../lib/HardwareSigner");
const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require("../lib/index");
const helpers = require("./helpers");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));

const LedgerSigner = HardwareSigner;
const mainnetContracts = addresses.IdleTokens.mainnet;

async function main() {
  const networkName = hre.network.name;
  const oneToken = ONE_TOKEN(18);
  let [signer, otherAddr] = await ethers.getSigners();

  if (networkName == 'mainnet') {
    signer = new HardwareSigner(ethers.provider, null, "m/44'/60'/0'/0/0");
  }

  const address = await signer.getAddress();

  console.log("deploying with account", address);
  console.log("account balance", BN(await ethers.provider.getBalance(address)).toString(), "\n\n");

  const answer = await helpers.prompt("continue? [y/n]");
  if (answer !== "y" && answer !== "yes") {
    console.log("exiting...");
    process.exit(1);
  }

  console.log("starting...");
  // const verifiedContract = await hre.ethers.getVerifiedContractAt('<address>');
  const strategy = await helpers.deployUpgradableContract('IdleStrategy', [mainnetContracts.idleDAIBest], signer);
  const idleCDO = await helpers.deployUpgradableContract(
    'IdleCDO',
    [
      BN('1000000').mul(oneToken), // limit
      mainnetContracts.DAI,
      mainnetContracts.devLeagueMultisig,
      mainnetContracts.rebalancer,
      strategy.address,
      BN('10000') // 10% interest to AA and 90% BB
    ],
    signer
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
