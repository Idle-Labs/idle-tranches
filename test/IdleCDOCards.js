require("hardhat/config");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { initialIdleContractsDeploy, setAprs, balance, mint, mintAABuyer, approveNFT } = require("../scripts/card-helpers");
const expectEvent = require("@openzeppelin/test-helpers/src/expectEvent");

const BN = (n) => BigNumber.from(n.toString());
const D18 = (n) => ethers.utils.parseUnits(n.toString(), 18);

const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const ONE_THOUSAND_TOKEN = BN("1000").mul(ONE_TOKEN(18));

describe("IdleCDOCards", () => {
  beforeEach(async () => {
    // deploy mocks and idle CDO trenches contracts
    await initialIdleContractsDeploy();

    //deploy Idle CDO Cards contract
    const IdleCDOCards = await ethers.getContractFactory("IdleCDOCards");
    cards = await IdleCDOCards.deploy([idleCDO.address,idleCDOFEI.address]);
    await cards.deployed();
  });

  it("should be successfully initialized", async () => {
    expect(await cards.name()).to.be.equal("IdleCDOCards");
  });

  it("should return a not empty list of idleCDOs", async () => {
    expect(await cards.getIdleCDOs()).not.to.be.empty;
  });

  it("should return a idleCDOS list with two items (DAI and FEI)", async () => {
    expect(await cards.getIdleCDOs()).to.have.lengthOf(2);
    expect(await cards.getIdleCDOs()).to.be.eql([idleCDO.address, idleCDOFEI.address]);
  });


 describe("when mint an idle cdo card", async () => {
    it("should deposit all the amount in AA if the risk exposure is 0%", async () => {
      const exposure = D18(0);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(ONE_THOUSAND_TOKEN);
    });

    it("should deposit all the amount in BB if the risk exposure is 100%", async () => {
      const exposure = D18(1);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(ONE_THOUSAND_TOKEN);
    });

    it("should deposit 50% in AA / 50% in BB of the amount if the risk exposure 50%", async () => {
      const exposure = D18(0.5);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(BN("500").mul(ONE_TOKEN(18)));

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(BN("500").mul(ONE_TOKEN(18)));
    });

    it("should deposit 75% in AA / 25% in BB of the amount if the risk exposure 25%", async () => {
      const exposure = D18(0.25);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(BN("750").mul(ONE_TOKEN(18)));

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(BN("250").mul(ONE_TOKEN(18)));
    });

    it("should revert the transaction if risk exposure is greater than 100%", async () => {
      const exposure = D18(1.000000001);
      await expect(mintAABuyer(exposure, ONE_THOUSAND_TOKEN)).to.be.revertedWith("percentage should be between 0 and 1");
    });
  });

 it("should allow to list tokens by owner", async () => {
    await mintAABuyer(D18(0.25), ONE_THOUSAND_TOKEN);
    await mintAABuyer(D18(0.3), ONE_THOUSAND_TOKEN);

    const balance = await cards.balanceOf(AABuyerAddr);
    expect(balance).to.be.equal(2);

    expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 0)).to.be.equal(1);
    expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 1)).to.be.equal(2);
  });

 describe("when returns APRs", async () => {
    it("should return the AA tranche APR if exposure is 0%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const exposure = D18(0);
      const apr = await cards.getApr(exposure);
      expect(apr).to.be.equal(BN(4).mul(ONE_TOKEN(18)));
    });

    it("should return the BB tranche APR if exposure is 100%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const exposure = D18(1);
      const apr = await cards.getApr(exposure);
      expect(apr).to.be.equal(BN(16).mul(ONE_TOKEN(18)));
    });

    it("should return the avg AA/BB tranches APR if exposure is 50%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const exposure = D18(0.5);
      const apr = await cards.getApr(exposure);
      const expected = 4 * 0.5 + 16 * 0.5;
      expect(apr).to.be.equal(BN(expected).mul(ONE_TOKEN(18)));
    });

    it("should return the 0.25 APR BB and 0.75 APR AA tranche if exposure is 25%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const exposure = D18(0.25);
      const apr = await cards.getApr(exposure);
      const expected = 4 * 0.75 + 16 * 0.25;
      expect(apr).to.be.equal(BN(expected).mul(ONE_TOKEN(18)));
    });
  });

 describe("when burn an idle cdo card", async () => {
    it("should withdraw all AA amount if card exposure is 0%", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      const exposure = D18(0);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      tx = await cards.connect(AABuyer).burn(1);
      await tx.wait();

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(0);
    });

    it("should burn the cdo card", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      const exposure = D18(0);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      tx = await cards.connect(AABuyer).burn(1);
      await tx.wait();

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, cards.address);
      expect(aaTrancheBalAfterBurn).to.be.equal(0);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(0);
    });

    it("should not burn a risk card if not the owner", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      const exposure = D18(0);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      await expect(cards.connect(BBBuyer).burn(1)).to.be.revertedWith("burn of risk card that is not own");

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(ONE_THOUSAND_TOKEN);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);
    });

    it("should transfer to the owner all AA amount if card exposure is 0%", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      const exposure = D18(0);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      tx = await cards.connect(AABuyer).burn(1);
      await tx.wait();

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, cards.address);
      expect(aaTrancheBalAfterBurn).to.be.equal(0);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(0);

      const buyerBalanceBeforeBurn = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeBurn).to.be.equal(buyerBalanceAfterMint);
    });

    it("should transfer to the owner all BB amount if card exposure is 100%", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      const exposure = D18(1);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1);
      expect(balanceAA).to.be.equal(0);
      expect(balanceBB).to.be.equal(ONE_THOUSAND_TOKEN);

      tx = await cards.connect(AABuyer).burn(1);
      await tx.wait();

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(0);

      const bbTrancheBalAfterBurn = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBalAfterBurn).to.be.equal(0);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(0);

      const buyerBalanceBeforeBurn = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeBurn).to.be.equal(buyerBalanceAfterMint);
    });

    it("should withdraw and transfer all 25% BB + 75% AA amount if exposure card is 25%", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      const exposure = D18(0.25);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(exposure));
      expect(pos.cardAddress).to.be.not.undefined;

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(BN("750").mul(ONE_TOKEN(18)));

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(BN("250").mul(ONE_TOKEN(18)));

      tx = await cards.connect(AABuyer).burn(1);
      await tx.wait();

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(0);

      const bbTrancheBalAfterBurn = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBalAfterBurn).to.be.equal(0);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(0);

      const buyerBalanceBeforeBurn = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeBurn).to.be.equal(buyerBalanceAfterMint);
    });

    it("should withdraw and transfer all AA amount and period earnings if exposure card is 0%", async () => {
      // APR AA=4 BB=16
      await idleToken.setFee(BN("0"));
      await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);

      //mint
      const exposure = D18(0);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);
      // deposit in the lending protocol
      await idleCDO.harvest(true, true, false, [true], [BN("0")], [BN("0")]);

      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest(false, true, false, [true], [BN("0")], [BN("0")]);

      //burn
      const tokenIdCard = 2;
      tx = await cards.connect(AABuyer).burn(tokenIdCard);
      await tx.wait();

      //gain with fee: apr: 26.66% fee:10% = 1000*0.2666*0.9 = 240
      //initialAmount - 1000 + 1240
      expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("240").mul(ONE_TOKEN(18))));
    });

    it("should withdraw and transfer all 25% BB + 75% AA (amount + period earnings) if exposure card is 25%", async () => {
      // APR AA=4 BB=16
      await idleToken.setFee(BN("0"));
      await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);

      //mint
      const exposure = D18(0.25);
      await mintAABuyer(exposure, ONE_THOUSAND_TOKEN);
      // deposit in the lending protocol
      await idleCDO.harvest(true, true, false, [true], [BN("0")], [BN("0")]);

      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest(false, true, false, [true], [BN("0")], [BN("0")]);

      //burn
      const tokenIdCard = 2;
      tx = await cards.connect(AABuyer).burn(tokenIdCard);
      await tx.wait();

      //gain with fee: apr: 77.33% fee:10% = (750*32% + 250*213.33% )*0.9 = 1000*77.33% = 696
      //initialAmount - 1000 + 1696
      expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("696").mul(ONE_TOKEN(18))));
    });
  });

 it("should not able to get a balance of an inexistent card", async () => {
    await expect(cards.balance(1)).to.be.revertedWith("inexistent card");
  });

 describe("Inner IdleCDOCard", () => {
    it("should not be deployed by a not IdleCDOCardManger", async () => {
      const IdleCDOCards = await ethers.getContractFactory("IdleCDOCard");
      await expect(IdleCDOCards.deploy()).to.be.revertedWith("function call to a non-contract account");
    });

    it("should not allow non manager owner minting", async () => {
      // mint a card with exposure 0.5
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      // get a card address
      const card = await cards.card(1);

      //deploy the evil Idle CDO Cards contract
      const IdleCDOCards = await ethers.getContractFactory("EvilIdleCdoCardManager");
      const evilManager = await IdleCDOCards.deploy([idleCDO.address]);
      await evilManager.deployed();

      //approve
      await approveNFT(idleCDO, evilManager, BBBuyer.address, ONE_THOUSAND_TOKEN);

      await expect(evilManager.connect(BBBuyer).evilMint(card.cardAddress, ONE_THOUSAND_TOKEN, 0)).to.be.revertedWith("Ownable: card caller is not the card manager owner");
    });

    it("should not allow non manager owner to burn", async () => {
      // mint a card with exposure 0.5
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      // get a card address
      const card = await cards.card(1);

      //deploy the evil Idle CDO Cards contract
      const IdleCDOCards = await ethers.getContractFactory("EvilIdleCdoCardManager");
      const evilManager = await IdleCDOCards.deploy([idleCDO.address]);
      await evilManager.deployed();

      //approve
      await approveNFT(idleCDO, evilManager, BBBuyer.address, ONE_THOUSAND_TOKEN);

      await expect(evilManager.connect(BBBuyer).evilBurn(card.cardAddress)).to.be.revertedWith("Ownable: card caller is not the card manager owner");
    });
  });
});
