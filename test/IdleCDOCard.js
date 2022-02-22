require("hardhat/config");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { initialIdleContractsDeploy,  mint, approveNFT } = require("../scripts/card-helpers");

const BN = (n) => BigNumber.from(n.toString()); // BigNumber
const D18 = (n) => ethers.utils.parseUnits(n.toString(), 18); // 18 decimals

const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n)); // 1 token
const ONE_THOUSAND_TOKEN = BN("1000").mul(ONE_TOKEN(18)); // 1000 tokens

describe("IdleCDOCard", () => {
  beforeEach(async () => {
    // deploy mocks and idle CDO trenches contracts
    await initialIdleContractsDeploy();

    //deploy Idle CDO Cards contract
    const IdleCDOCardManager = await ethers.getContractFactory("IdleCDOCardManager");
    cards = await IdleCDOCardManager.deploy([idleCDO.address, idleCDOFEI.address]);
    await cards.deployed();
  });

  it("should not be deployed by a not IdleCDOCardManger", async () => {
    const IdleCDOCard = await ethers.getContractFactory("IdleCDOCard");
    await expect(IdleCDOCard.deploy()).to.be.revertedWith("Transaction reverted: function returned an unexpected amount of data");
  });

  it("should not allow non manager owner minting", async () => {
    // mint a card with exposure 0.5
    await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
    // get a card address
    const card = await cards.card(1,0);

    //deploy the evil Idle CDO Cards contract
    const IdleCDOCardManager = await ethers.getContractFactory("EvilIdleCdoCardManager");
    const evilManager = await IdleCDOCardManager.deploy([idleCDO.address]);
    await evilManager.deployed();

    //approve
    await approveNFT(idleCDO, evilManager, BBBuyer.address, ONE_THOUSAND_TOKEN);

    await expect(evilManager.connect(BBBuyer).evilMint(card.cardAddress, ONE_THOUSAND_TOKEN, 0)).to.be.revertedWith("Ownable: card caller is not the card manager owner");
  });

  it("should not allow non manager owner to burn", async () => {
    // mint a card with exposure 0.5
    await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
    // get a card address
    const card = await cards.card(1,0);

    //deploy the evil Idle CDO Cards contract
    const IdleCDOCardManager = await ethers.getContractFactory("EvilIdleCdoCardManager");
    const evilManager = await IdleCDOCardManager.deploy([idleCDO.address]);
    await evilManager.deployed();

    //approve
    await approveNFT(idleCDO, evilManager, BBBuyer.address, ONE_THOUSAND_TOKEN);

    await expect(evilManager.connect(BBBuyer).evilBurn(card.cardAddress)).to.be.revertedWith("Ownable: card caller is not the card manager owner");
  });
});
