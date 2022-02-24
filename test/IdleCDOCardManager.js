require("hardhat/config");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { initialIdleContractsDeploy, setAprs, setFEIAprs, balance, mint, mintAABuyer, approveNFT, mintCDO, combineCDOs } = require("../scripts/card-helpers");
const expectEvent = require("@openzeppelin/test-helpers/src/expectEvent");
const { id } = require("ethers/lib/utils");

const BN = (n) => BigNumber.from(n.toString());
const D18 = (n) => ethers.utils.parseUnits(n.toString(), 18);

const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const ONE_THOUSAND_TOKEN = BN("1000").mul(ONE_TOKEN(18));
const EXPOSURE = (exposure) =>  D18(exposure);

describe("IdleCDOCardManager", () => {
  beforeEach(async () => {
    // deploy mocks and idle CDO trenches contracts
    await initialIdleContractsDeploy();

    //deploy Idle CDO Cards contract
    const IdleCDOCardManager = await ethers.getContractFactory("IdleCDOCardManager");
    cards = await IdleCDOCardManager.deploy([idleCDO.address, idleCDOFEI.address]);
    await cards.deployed();
  });
  it("should be successfully initialized", async () => {
    expect(await cards.name()).to.be.equal("IdleCDOCardManager");
  });

  it("should return a not empty list of idleCDOs", async () => {
    expect(await cards.getIdleCDOs()).not.to.be.empty;
  });

  it("should return a idleCDOS list with two items (DAI and FEI)", async () => {
    expect(await cards.getIdleCDOs()).to.have.lengthOf(2);
    expect(await cards.getIdleCDOs()).to.be.eql([idleCDO.address, idleCDOFEI.address]);
  });


  it("should allow to list tokens by owner", async () => {
    await mintAABuyer(D18(0.25), ONE_THOUSAND_TOKEN);
    await mintAABuyer(D18(0.3), ONE_THOUSAND_TOKEN);

    const balance = await cards.balanceOf(AABuyerAddr);
    expect(balance).to.be.equal(2);

    expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 0)).to.be.equal(1);
    expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 1)).to.be.equal(2);
  });

  it("should not able to get a balance of an inexistent card", async () => {
    await expect(cards.balance(1,0)).to.be.revertedWith("inexistent card");
  });

  it("should be able to get a balance of a combined card", async () => {
    await combineCDOs(AABuyer, EXPOSURE(0), ONE_THOUSAND_TOKEN, EXPOSURE(1), ONE_THOUSAND_TOKEN);

    const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
    expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);
    expect(balanceBB).to.be.equal(BN(0));

    const { 0: balanceAAFEI, 1: balanceBBFEI } = await cards.balance(1,1);
    expect(balanceAAFEI).to.be.equal(BN(0));
    expect(balanceBBFEI).to.be.equal(ONE_THOUSAND_TOKEN);

  });

  describe("when mint an idle cdo card", async () => {
    it("should deposit all the amount in AA if the risk exposure is 0%", async () => {
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0)));
      expect(pos.cardAddress).to.be.not.undefined;

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(ONE_THOUSAND_TOKEN);
    });

    it("should deposit all the amount in BB if the risk exposure is 100%", async () => {
      await mintAABuyer(EXPOSURE(1), ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(1)));
      expect(pos.cardAddress).to.be.not.undefined;

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(ONE_THOUSAND_TOKEN);
    });

    it("should deposit 50% in AA / 50% in BB of the amount if the risk exposure 50%", async () => {
      await mintAABuyer(EXPOSURE(0.5), ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.5)));
      expect(pos.cardAddress).to.be.not.undefined;

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(BN("500").mul(ONE_TOKEN(18)));

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(BN("500").mul(ONE_TOKEN(18)));
    });

    it("should deposit 75% in AA / 25% in BB of the amount if the risk exposure 25%", async () => {
      await mintAABuyer(EXPOSURE(0.25), ONE_THOUSAND_TOKEN);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.25)));
      expect(pos.cardAddress).to.be.not.undefined;
      expect(pos.idleCDOAddress).to.be.equal(idleCDO.address);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      const aaTrancheBal = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(BN("750").mul(ONE_TOKEN(18)));

      const bbTrancheBal = await balance("BB", idleCDO, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(BN("250").mul(ONE_TOKEN(18)));
    });

    it("should deposit 25% in AA / 75% in BB of the amount if the risk exposure 75% in IdleCDO FEI", async () => {

      await mintCDO(idleCDOFEI,EXPOSURE(0.75), ONE_THOUSAND_TOKEN, AABuyer);

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.75)));
      expect(pos.cardAddress).to.be.not.undefined;
      expect(pos.idleCDOAddress).to.be.equal(idleCDOFEI.address);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      const aaTrancheBal = await balance("AA", idleCDOFEI, pos.cardAddress);
      expect(aaTrancheBal).to.be.equal(BN("250").mul(ONE_TOKEN(18)));

      const bbTrancheBal = await balance("BB", idleCDOFEI, pos.cardAddress);
      expect(bbTrancheBal).to.be.equal(BN("750").mul(ONE_TOKEN(18)));
    });

    it("should revert the transaction if idleCDO selected is not listed", async () => {
      const notListedAddress = "0x1000000000000000000000000000000000000001";
      await expect(cards.connect(AABuyer).mint(notListedAddress, EXPOSURE(0.75), ONE_THOUSAND_TOKEN, ethers.constants.AddressZero, 0, 0)).to.be.revertedWith("IdleCDO address is not listed");
    });

    it("should revert the transaction if risk exposure is greater than 100%", async () => {
      await expect(mintAABuyer(EXPOSURE(1.000000001), ONE_THOUSAND_TOKEN)).to.be.revertedWith("% should be between 0 and 1");
    });
  });

  describe("when returns APRs", async () => {
    it("should return the AA tranche APR if exposure is 0%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const apr = await cards.getApr(idleCDO.address, EXPOSURE(0));
      expect(apr).to.be.equal(BN(4).mul(ONE_TOKEN(18)));
    });

    it("should return the BB tranche APR if exposure is 100%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const apr = await cards.getApr(idleCDO.address, EXPOSURE(1));
      expect(apr).to.be.equal(BN(16).mul(ONE_TOKEN(18)));
    });

    it("should return the avg AA/BB tranches APR if exposure is 50%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const apr = await cards.getApr(idleCDO.address, EXPOSURE(0.5));
      const expected = 4 * 0.5 + 16 * 0.5;
      expect(apr).to.be.equal(BN(expected).mul(ONE_TOKEN(18)));
    });

    it("should return the 0.25 APR BB and 0.75 APR AA tranche if exposure is 25%", async () => {
      // APR AA=4 BB=16
      await setAprs();

      const apr = await cards.getApr(idleCDO.address, EXPOSURE(0.25));
      const expected = 4 * 0.75 + 16 * 0.25;
      expect(apr).to.be.equal(BN(expected).mul(ONE_TOKEN(18)));
    });

    it("should return the 0.75 APR BB and 0.25 APR AA tranche if exposure is 75% in IdleCDO FEI", async () => {
      // APR AA=4 BB=16
      await setFEIAprs();

      const apr = await cards.getApr(idleCDOFEI.address, EXPOSURE(0.75));
      const expected = 4 * 0.25 + 16 * 0.75;
      expect(apr).to.be.equal(BN(expected).mul(ONE_TOKEN(18)));
    });
  });

  describe("when burn an idle cdo card", async () => {
    it("should withdraw all AA amount if card exposure is 0%", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0)));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      tx = await cards.connect(AABuyer).burn(1);
      await tx.wait();

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(0);
    });

    it("should burn the cdo card", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0)));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
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

      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0)));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      await expect(cards.connect(BBBuyer).burn(1)).to.be.revertedWith("burn of card that is not own");

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(ONE_THOUSAND_TOKEN);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);
    });

    it("should transfer to the owner all AA amount if card exposure is 0%", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0)));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
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

      await mintAABuyer(EXPOSURE(1), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(1)));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
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

      await mintAABuyer(EXPOSURE(0.25), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.25)));
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
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);
      // deposit in the lending protocol
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

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
      await mintAABuyer(EXPOSURE(0.25), ONE_THOUSAND_TOKEN);
      // deposit in the lending protocol
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      //burn
      const tokenIdCard = 2;
      tx = await cards.connect(AABuyer).burn(tokenIdCard);
      await tx.wait();

      //gain with fee: apr: 77.33% fee:10% = (750*32% + 250*213.33% )*0.9 = 1000*77.33% = 696
      //initialAmount - 1000 + 1696
      expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("696").mul(ONE_TOKEN(18))));
    });

    it("should withdraw and transfer all 25% BB + 75% AA (amount + period earnings) if exposure card is 25% in IdleCDO FEI", async () => {
      // APR AA=4 BB=16
      await idleTokenFEI.setFee(BN("0"));
      await idleTokenFEI.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);

      //mint
      await mintCDO(idleCDOFEI, EXPOSURE(0.25), ONE_THOUSAND_TOKEN, AABuyer);

      // deposit in the lending protocol
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      // update lending protocol price which is now 2
      await idleTokenFEI.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      //burn
      const tokenIdCard = 2;
      tx = await cards.connect(AABuyer).burn(tokenIdCard);
      await tx.wait();

      //gain with fee: apr: 77.33% fee:10% = (750*32% + 250*213.33% )*0.9 = 1000*77.33% = 696
      //initialAmount - 1000 + 1696
      expect(await underlyingFEI.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("696").mul(ONE_TOKEN(18))));
    });
  });

  describe("when combine idleCDOs", async () => {

    it("should only generate a card with IdleCdoDAI when is mint with 0 IdleCdoFEI amount ", async () => {
      await approveNFT(idleCDO, cards, AABuyerAddr, ONE_THOUSAND_TOKEN);
      await combineCDOs(AABuyer, EXPOSURE(0.25), ONE_THOUSAND_TOKEN, EXPOSURE(0.25), 0);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.25)));
      expect(pos.cardAddress).to.be.not.undefined;
      expect(pos.idleCDOAddress).to.be.equal(idleCDO.address);
    });

    it("should only generate a card with IdleCdoFEI when is mint with 0 IdleCdoDAI amount ", async () => {
      await approveNFT(idleCDOFEI, cards, AABuyerAddr, ONE_THOUSAND_TOKEN);
      await combineCDOs(AABuyer, EXPOSURE(0.25), 0,EXPOSURE(0.50), ONE_THOUSAND_TOKEN);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.50)));
      expect(pos.cardAddress).to.be.not.undefined;
      expect(pos.idleCDOAddress).to.be.equal(idleCDOFEI.address);
    });

    it("should revert minting card with 0 amount in DAI and FEI", async () => {
      await expect(combineCDOs(AABuyer, EXPOSURE(0.25), 0,EXPOSURE(0), 0)).to.be.revertedWith("cannot mint with no amount");
    });

    it("should generate a new NFT Idle CDO Card combining DAI and FEI", async () => {

      await approveNFT(idleCDO, cards, AABuyerAddr, ONE_THOUSAND_TOKEN);
      await approveNFT(idleCDOFEI, cards, AABuyerAddr, ONE_THOUSAND_TOKEN);
      
      await combineCDOs(AABuyer, EXPOSURE(0.25), ONE_THOUSAND_TOKEN,EXPOSURE(0.50), ONE_THOUSAND_TOKEN);

      blendTokenId =1;
      cardTokenIds = await cards.cardIndexes(blendTokenId);
      
      expect(cardTokenIds.length).to.be.equal(2);
      expect(cardTokenIds[0]).to.be.equal(0);
      expect(cardTokenIds[1]).to.be.equal(1);

      pos = await cards.card(blendTokenId,cardTokenIds[0]);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0.25)));
      expect(pos.cardAddress).to.be.not.undefined;
      expect(pos.idleCDOAddress).to.be.equal(idleCDO.address);
      
      pos2 = await cards.card(blendTokenId,cardTokenIds[1]);
      expect(pos2.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos2.exposure).to.be.equal(BN(EXPOSURE(0.50)));
      expect(pos2.cardAddress).to.be.not.undefined;
      expect(pos2.idleCDOAddress).to.be.equal(idleCDOFEI.address);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);
    });

    it("should the owner balance including all owned cards", async () => {
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, AABuyer);
      await combineCDOs(AABuyer,EXPOSURE(0.3), ONE_THOUSAND_TOKEN,EXPOSURE(0.7), ONE_THOUSAND_TOKEN);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(3);

      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      expect(await cards.balanceOf(BBBuyerAddr)).to.be.equal(1);
    });


    it("should be able to get tokenID based on the owner address", async () => {
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, AABuyer);
      expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 0)).to.be.equal(1);
      expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 1)).to.be.equal(2);

      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      expect(await cards.tokenOfOwnerByIndex(BBBuyerAddr, 0)).to.be.equal(3);
    });

    it("should be able to get the tokenId by index of any card", async () => {
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, AABuyer);
      await combineCDOs(AABuyer,EXPOSURE(0.3), ONE_THOUSAND_TOKEN,EXPOSURE(0.7), ONE_THOUSAND_TOKEN);
     
      expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 0)).to.be.equal(1);
      expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 1)).to.be.equal(2);
      expect(await cards.tokenOfOwnerByIndex(AABuyerAddr, 2)).to.be.equal(3);
    });

    it("should be able to get indexes of not combined cards", async () => {
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, AABuyer);

      let firstCard = await cards.cardIndexes(1);
      let secondCard = await cards.cardIndexes(2);

      expect(firstCard.length).to.be.equal(1);
      expect(firstCard[0]).to.be.equal(BN(0));

      expect(secondCard.length).to.be.equal(1);
      expect(secondCard[0]).to.be.equal(BN(1));
    });

    it("should be able to get indexes of combined cards", async () => {
      await combineCDOs(AABuyer, EXPOSURE(0.3), ONE_THOUSAND_TOKEN, EXPOSURE(0.7), ONE_THOUSAND_TOKEN);
      await combineCDOs(AABuyer, EXPOSURE(0.3), ONE_THOUSAND_TOKEN, EXPOSURE(0.7), ONE_THOUSAND_TOKEN);

      let firstCard = await cards.cardIndexes(1);
      let secondCard = await cards.cardIndexes(2);

      expect(firstCard.length).to.be.equal(2);
      expect(firstCard[0]).to.be.equal(BN(0));
      expect(firstCard[1]).to.be.equal(BN(1));

      expect(secondCard.length).to.be.equal(2);
      expect(secondCard[0]).to.be.equal(BN(2));
      expect(secondCard[1]).to.be.equal(BN(3));
    });

    it("should be able to burn combining DAI and FEI cards", async () => {
      // APR AA=4 BB=16
      await idleToken.setFee(BN("0"));
      await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      // APR AA=4 BB=16
      await idleTokenFEI.setFee(BN("0"));
      await idleTokenFEI.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);

      await combineCDOs(AABuyer, EXPOSURE(0), ONE_THOUSAND_TOKEN,EXPOSURE(0.25), ONE_THOUSAND_TOKEN);

      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      // update lending protocol price which is now 2
      await idleTokenFEI.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([false, true, false, false], [true], [BN("0")], [BN("0")], 0);

      blendTokenId = 3;
      tx = await cards.connect(AABuyer).burn(blendTokenId);
      await tx.wait();

      //gain with fee: apr: 26.66% fee:10% = 1000*0.2666*0.9 = 240
      //initialAmount - 1000 + 1240
      expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("240").mul(ONE_TOKEN(18))));
      //gain with fee: apr: 77.33% fee:10% = (750*32% + 250*213.33% )*0.9 = 1000*77.33% = 696
      //initialAmount - 1000 + 1696
      expect(await underlyingFEI.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("696").mul(ONE_TOKEN(18))));
    });

    it("should be able to burn a card with only a DAI position", async () => {
      // APR AA=4 BB=16
      await idleToken.setFee(BN("0"));
      await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      
      //mint
      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);
      // deposit in the lending protocol
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);
      
      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);
      
      //burn
      const tokenIdCard = 2;
      tx = await cards.connect(AABuyer).burn(tokenIdCard);
      await tx.wait();
      
      //gain with fee: apr: 26.66% fee:10% = 1000*0.2666*0.9 = 240
      //initialAmount - 1000 + 1240
      expect(await underlying.balanceOf(AABuyerAddr)).to.be.equal(initialAmount.add(BN("240").mul(ONE_TOKEN(18))));
    });

    it("should not burn a risk card if not the owner", async () => {
      let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());

      const buyerBalanceAfterMint = await underlyingContract.balanceOf(AABuyerAddr);

      await mintAABuyer(EXPOSURE(0), ONE_THOUSAND_TOKEN);

      const buyerBalanceBeforeMint = await underlyingContract.balanceOf(AABuyerAddr);
      expect(buyerBalanceBeforeMint).to.be.equal(buyerBalanceAfterMint.sub(ONE_THOUSAND_TOKEN));

      expect(await cards.ownerOf(1)).to.be.equal(AABuyerAddr);
      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);

      pos = await cards.card(1,0);
      expect(pos.amount).to.be.equal(ONE_THOUSAND_TOKEN);
      expect(pos.exposure).to.be.equal(BN(EXPOSURE(0)));
      expect(pos.cardAddress).to.be.not.undefined;

      const { 0: balanceAA, 1: balanceBB } = await cards.balance(1,0);
      expect(balanceAA).to.be.equal(ONE_THOUSAND_TOKEN);

      await expect(cards.connect(BBBuyer).burn(1)).to.be.revertedWith("burn of card that is not own");

      const aaTrancheBalAfterBurn = await balance("AA", idleCDO, pos.cardAddress);
      expect(aaTrancheBalAfterBurn).to.be.equal(ONE_THOUSAND_TOKEN);

      expect(await cards.balanceOf(AABuyerAddr)).to.be.equal(1);
    });

    it("should not burn a non existing risk card", async () => {
      await expect(cards.connect(AABuyer).burn(9)).to.be.revertedWith("ERC721: owner query for nonexistent token");
    });

    it("should not burn a combining DAI and FEI card if not the owner", async () => {
      // APR AA=4 BB=16
      await idleToken.setFee(BN("0"));
      await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mint(D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);
      // APR AA=4 BB=16
      await idleTokenFEI.setFee(BN("0"));
      await idleTokenFEI.setApr(BN("10").mul(ONE_TOKEN(18)));
      await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, BBBuyer);

      await combineCDOs(AABuyer, EXPOSURE(0), ONE_THOUSAND_TOKEN,EXPOSURE(0.25), ONE_THOUSAND_TOKEN);

      // update lending protocol price which is now 2
      await idleToken.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);

      // update lending protocol price which is now 2
      await idleTokenFEI.setTokenPriceWithFee(BN("2").mul(ONE_TOKEN(18)));
      // to update tranchePriceAA which will be 1.9
      await idleCDO.harvest([false, true, false, false], [true], [BN("0")], [BN("0")], 0);

      await expect(cards.connect(BBBuyer).burn(3)).to.be.revertedWith("burn of card that is not own");

    });

  });

});
