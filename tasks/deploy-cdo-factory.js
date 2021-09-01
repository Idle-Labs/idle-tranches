require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

/**
 * @name deploy
 * eg `npx hardhat deploy-cdo-factory`
 */
task("deploy-cdo-factory", "Deploy IdleCDOFactory")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    console.log("creator: ", creator);
    console.log("network: ", hre.network.name);
    await helpers.prompt("continue? [y/n]", true);

    const cdoFactory = await helpers.deployContract("IdleCDOFactory", [], signer);
    console.log("cdoFactory deployed at", cdoFactory.address);
    return cdoFactory;
  });
