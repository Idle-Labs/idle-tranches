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

  let cdoAddress = undefined;
  let cdoFactoryAddress = undefined;
  let strategyAddress = undefined;

  if (hre.network.name == "hardhat") {
    console.log("\n⚠️  Local network detected, deploying test CDO and CDOFactory\n");
    let { idleCDO, strategy, AAaddr, BBaddr } = await hre.run("deploy", { cdoname: cdoname });
    const implAddress = await getImplementationAddress(hre.ethers.provider, idleCDO.address);
    const cdoFactory = await hre.run("deploy-cdo-factory");

    cdoAddress = idleCDO.address;
    cdoFactoryAddress = cdoFactory.address;
    strategyAddress = strategy.address;
  }

  if (helpers.isEmptyString(cdoAddress)) {
    console.log("🛑 cdoAddress must be specified")
    return;
  }

  if (helpers.isEmptyString(cdoFactoryAddress)) {
    console.log("🛑 cdoFactoryAddress must be specified")
    return;
  }

  if (helpers.isEmptyString(strategyAddress)) {
    console.log("🛑 strategyAddress must be specified")
    return;
  }

  const params = {
    factory: cdoFactoryAddress,
    cdoname: cdoname,
    // cdoImplementation: implAddress,
    cloneFromProxy: cdoAddress,
    limit: BN('500000').mul(ONE_TOKEN(deployToken.decimals)).toString(), // limit
    governanceFund: mainnetContracts.treasuryMultisig, // recovery address
    strategy: strategyAddress,
    trancheAPRSplitRatio: BN('20000').toString(), // apr split: 20% interest to AA and 80% BB
    trancheIdealWeightRatio: BN('50000').toString(), // ideal value: 50% AA and 50% BB tranches
    incentiveTokens: [mainnetContracts.IDLE].join(","),
  }

  const proxyAddress = await hre.run("deploy-cdo-with-factory", params);
  console.log("cdo proxy deployed at", proxyAddress)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

