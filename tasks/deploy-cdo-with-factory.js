require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

/**
 * @name deploy
 * eg `npx hardhat deploy-with-cdo-factory`
 */
task("deploy-with-cdo-factory", "Deploy IdleCDO using IdleCDOFactory")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    const proxyAdminAddress = "0x9438904ABC7d8944A6E2A89671fEf51C629af351";

    console.log("creator: ", creator);
    console.log("network: ", hre.network.name);
    console.log("proxyAdminAddress: ", proxyAdminAddress);
    await helpers.prompt("continue? [y/n]", true);

    const cdoFactory = await hre.run("deploy-cdo-factory");

    const cdoname = "idledai";
    const deployToken = addresses.deployTokens[cdoname];
    const { idleCDO, strategy, AAaddr, BBaddr } = await hre.run("deploy", { cdoname: cdoname });

    const incentiveTokens = [mainnetContracts.IDLE];
    const IdleCDO = await ethers.getContractFactory("IdleCDO");
    const initMethodCall = idleCDO.interface.encodeFunctionData("initialize", [
      BN('500000').mul(ONE_TOKEN(deployToken.decimals)), // limit
      deployToken.underlying,
      mainnetContracts.treasuryMultisig, // recovery address
      creator, // guardian
      mainnetContracts.rebalancer,
      strategy.address,
      BN('20000'), // apr split: 20% interest to AA and 80% BB
      BN('50000'), // ideal value: 50% AA and 50% BB tranches
      incentiveTokens
    ]);

    console.log("deploying with factory...");
    const res = await cdoFactory.deployCDO(idleCDO.address, proxyAdminAddress, initMethodCall);
    const cdoDeployFilter = cdoFactory.filters.CDODeployed;
    const events = await cdoFactory.queryFilter(cdoDeployFilter, "latest");
    const proxyAddress = events[0].args.proxy;
    console.log("proxyAddress", proxyAddress)
  });
