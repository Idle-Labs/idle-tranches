const hre = require("hardhat");
const helpers = require("../../scripts/helpers");
const { BigNumber } = require("@ethersproject/bignumber");
const addresses = require("../../lib/addresses");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

async function main() {
  const cdoname = "idledai";
  const deployToken = addresses.deployTokens[cdoname];

  let { idleCDO, strategy, AAaddr, BBaddr } = await hre.run("deploy", { cdoname: cdoname });
  const implAddress = await getImplementationAddress(hre.ethers.provider, idleCDO.address);
  const cdoFactory = await hre.run("deploy-cdo-factory");

  const params = {
    factory: cdoFactory.address,
    cdoname: cdoname,
    cdoImplementation: idleCDO.address,
    limit: BN('500000').mul(ONE_TOKEN(deployToken.decimals)).toString(), // limit
    governanceFund: mainnetContracts.treasuryMultisig, // recovery address
    strategy: strategy.address,
    trancheAPRSplitRatio: BN('20000').toString(), // apr split: 20% interest to AA and 80% BB
    trancheIdealWeightRatio: BN('50000').toString(), // ideal value: 50% AA and 50% BB tranches
    incentiveTokens: [mainnetContracts.IDLE].join(","),
  }

  await hre.run("deploy-cdo-with-factory", params);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

