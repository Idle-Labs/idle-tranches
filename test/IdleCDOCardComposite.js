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

describe("IdleCDOCardComposite", () => {
  beforeEach(async () => {
    const Bl3nd = await ethers.getContractFactory("IdleCDOCardComposite");
    bl3nd = await Bl3nd.deploy();
    [owner] = await ethers.getSigners();
  });

  it("should be deployed", async () => {    });

  it("should mint a new leaf token", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    expect(await bl3nd.balanceOf(owner.address)).to.equal(1);
  });

  it("should get content of a leaf token", async () => {

    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    [index] = await bl3nd.contentIndexes(1);
    expect(index).to.equal(1);
    
    expect(await bl3nd.content(index)).to.equal(1*2);
  });

  it("should combine two leaf tokens", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
    
    expect(await bl3nd.balanceOf(owner.address)).to.equal(2);
    
    tx = await bl3nd.combine(1, 2); //combine the two tokens
    expect(await bl3nd.balanceOf(owner.address)).to.equal(3);
  });

  it("should get content of combined token", async () => {

    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
    
    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();

    [first,second] = await bl3nd.contentIndexes(3);
    expect(await bl3nd.content(first)).to.equal(1*2);
    expect(await bl3nd.content(second)).to.equal(2*2);
  });

  it("should indexes be empty if leaf token does not exist", async () => {
    expect(await bl3nd.contentIndexes(1)).to.be.empty;
  });

  it("should combine a leafs and a combined tokens", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();
     
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(3, 2); //combine the two tokens
    await tx.wait();

    expect(await bl3nd.balanceOf(owner.address)).to.equal(5);
  });



  it("should get indexes of a leafs and a combined tokens", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();
     
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(4, 3); //combine the two tokens
    await tx.wait();

    [first,second,third] = await bl3nd.contentIndexes(5);
    expect(first).to.equal(4);
    expect(second).to.equal(1);
    expect(third).to.equal(2);

    expect(await bl3nd.content(first)).to.equal(4*2);
    expect(await bl3nd.content(second)).to.equal(1*2);
    expect(await bl3nd.content(third)).to.equal(2*2);
  });

});
