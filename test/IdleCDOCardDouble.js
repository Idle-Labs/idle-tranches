require("hardhat/config");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");
const { initialIdleContractsDeploy,  mint, approveNFT } = require("../scripts/card-helpers");
const { isBigNumberish } = require("@ethersproject/bignumber/lib/bignumber");

const BN = (n) => BigNumber.from(n.toString()); // BigNumber
const D18 = (n) => ethers.utils.parseUnits(n.toString(), 18); // 18 decimals

const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n)); // 1 token
const ONE_THOUSAND_TOKEN = BN("1000").mul(ONE_TOKEN(18)); // 1000 tokens

describe("IdleCDOCardDouble", () => {
  beforeEach(async () => {
    const Bl3nd = await ethers.getContractFactory("IdleCDOCardDouble");
    bl3nd = await Bl3nd.deploy();
    [owner,notOwner] = await ethers.getSigners();
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
    expect(await bl3nd.balanceOf(owner.address)).to.equal(1);
    expect(await bl3nd.balanceOf(bl3nd.address)).to.equal(2);
    
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

  it("should be revert if combine a leafs and a combined tokens", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();
     
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    await expect(bl3nd.combine(3, 2)).to.be.revertedWith("Only leafs can be combined");
    await expect(bl3nd.combine(1, 3)).to.be.revertedWith("Only leafs can be combined");
    await expect(bl3nd.combine(3, 3)).to.be.revertedWith("Only leafs can be combined");
 
  })

  it("should be revert if combine two leaf before combined", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();

    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
   
    await expect(bl3nd.combine(1, 2)).to.be.revertedWith("Leafs were already combined");
    await expect(bl3nd.combine(1, 4)).to.be.revertedWith("Leafs were already combined");
    await expect(bl3nd.combine(4, 2)).to.be.revertedWith("Leafs were already combined");
  });

  it("should be reverted if any of two leaf tokens does not exist", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    await expect(bl3nd.combine(1, 2)).to.be.revertedWith("There are inexistent leafs");
    await expect(bl3nd.combine(2, 1)).to.be.revertedWith("There are inexistent leafs");
  
  });

  it("should be reverted trying to combined the same leaf", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
    await expect(bl3nd.combine(1, 1)).to.be.revertedWith("Can't combine same leafs");
  });


  it("should be revert if not owner of leaf token", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.connect(notOwner).mint(); //mint a new token left: ;
    await tx.wait(); //wait for the tx to be mined
     
    tx = await bl3nd.connect(notOwner).mint(); //mint a new token left: ;
    await tx.wait(); //wait for the tx to be mined

    await expect(bl3nd.combine(3, 2)).to.be.revertedWith("Only owner can combine leafs");
    await expect(bl3nd.combine(1, 3)).to.be.revertedWith("Only owner can combine leafs");
    await expect(bl3nd.combine(2, 1)).to.be.revertedWith("Only owner can combine leafs");
 
  })
  it("should uncombine a combined token", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();

    tx = await bl3nd.uncombine(3); //combine the two tokens
    await tx.wait();

    expect(await bl3nd.balanceOf(owner.address)).to.equal(2);
    expect(await bl3nd.balanceOf(bl3nd.address)).to.equal(0);
    await expect(bl3nd.ownerOf(3)).to.be.revertedWith("ERC721: owner query for nonexistent token");
  });

  it("should combine a ancombined tokens", async () => {
    tx = await bl3nd.mint(); //mint a new token left //1
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left //2
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens //3
    await tx.wait();

    tx = await bl3nd.mint(); //mint a new token left //4
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.mint(); //mint a new token left //5
    await tx.wait(); //wait for the tx to be mined
    
    tx = await bl3nd.uncombine(3); //combine the two tokens 
    await tx.wait();

    tx = await bl3nd.combine(1, 2); //combine the two tokens  //6
    await tx.wait();
    expect(await bl3nd.balanceOf(owner.address)).to.equal(3);
    expect(await bl3nd.balanceOf(bl3nd.address)).to.equal(2);

    tx = await bl3nd.uncombine(6); //combine the two tokens
    await tx.wait();
    tx = await bl3nd.combine(1, 4); //combine the two tokens //7
    await tx.wait();
    expect(await bl3nd.balanceOf(owner.address)).to.equal(3);
    expect(await bl3nd.balanceOf(bl3nd.address)).to.equal(2);

    tx = await bl3nd.uncombine(7); //combine the two tokens
    await tx.wait();
    tx = await bl3nd.combine(5, 2); //combine the two tokens
    await tx.wait();
    expect(await bl3nd.balanceOf(owner.address)).to.equal(3);
    expect(await bl3nd.balanceOf(bl3nd.address)).to.equal(2);

  });

  it("should revert uncombine if not owner of the combined token", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined

    tx = await bl3nd.combine(1, 2); //combine the two tokens
    await tx.wait();

    await expect(bl3nd.connect(notOwner).uncombine(3)).to.be.revertedWith("Only owner can uncombine combined leafs");
  });


  it("should revert uncombine if not a combined token", async () => {
    tx = await bl3nd.mint(); //mint a new token left
    await tx.wait(); //wait for the tx to be mined
 
    await expect(bl3nd.uncombine(1)).to.be.revertedWith("Can not uncombine a non-combined token");
  });

  it("should revert uncombine if is an inexistent token", async () => {
    await expect(bl3nd.uncombine(1)).to.be.revertedWith("The token does not exist");
  });


});
