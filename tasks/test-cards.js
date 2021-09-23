require("hardhat/config");
const helper = require("../scripts/card-helpers");

task("deploy-cards-test", "Deploy all contract and mocks needed to demo Idle CDO Cards").setAction(async (args) => {
    await helper.idleCDOCardsTestDeploy();
});