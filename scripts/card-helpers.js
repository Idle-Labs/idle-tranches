/// TEST CARD HELPERS
require("hardhat/config");
const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");

const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = (n) => BigNumber.from(n.toString());
const D18 = (n) => hre.ethers.utils.parseUnits(n.toString(), 18);

const ONE_TOKEN = (n, decimals) => BigNumber.from("10").pow(BigNumber.from(n));
const ONE_THOUSAND_TOKEN = BN("1000").mul(ONE_TOKEN(18));


// APR AA=4 BB=16
const setAprs = async () => {
    await idleToken.setFee(BN("0"));
    await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
    await mintAABuyer(D18(0.5), ONE_THOUSAND_TOKEN);
  };
  
  const balance = async (type, idleCDO, addr) => {
    let AAContract = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
    let BBContract = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());
    const aaTrancheBal = BN(await (type == "AA" ? AAContract : BBContract).balanceOf(addr));
    return aaTrancheBal;
  };
  
  const approveNFT = async (idleCDO, contract, addr, amount) => {
    let underlyingContract = await hre.ethers.getContractAt("IERC20Detailed", await idleCDO.token());
    await helpers.sudoCall(addr, underlyingContract, "approve", [contract.address, amount]);
  };
  
  const mintAABuyer = async (exposure, _amount) => {
    await mint(exposure, _amount, AABuyer);
  };
  
  const mint = async (exposure, _amount, signer) => {
    //approve
    await approveNFT(idleCDO, cards, signer.address, _amount);
    //mint
    tx = await cards.connect(signer).mint(exposure, _amount);
    await tx.wait();
    //harvest
    await idleCDO.harvest(true, true, false, [true], [BN("0")], [BN("0")]);
  };
  
  const initialIdleContractsDeploy = async () => {
        // deploy contracts
        addr0 = addresses.addr0;
        signers = await hre.ethers.getSigners();
        owner = signers[0];
        AABuyer = signers[1];
        AABuyerAddr = AABuyer.address;
        BBBuyer = signers[2];
        BBBuyerAddr = BBBuyer.address;
        AABuyer2 = signers[3];
        AABuyer2Addr = AABuyer2.address;
        BBBuyer2 = signers[4];
        BBBuyer2Addr = BBBuyer2.address;
        Random = signers[5];
        RandomAddr = Random.address;
        Random2 = signers[6];
        Random2Addr = Random2.address;
    
        one = ONE_TOKEN(18);
        const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
        const MockIdleToken = await hre.ethers.getContractFactory("MockIdleToken");
        const MockUniRouter = await hre.ethers.getContractFactory("MockUniRouter");
    
        uniRouter = await MockUniRouter.deploy();
        await uniRouter.deployed();
    
        // 10M to creator
        weth = await MockERC20.deploy("WETH", "WETH");
        await weth.deployed();
        // 10M to creator
        underlying = await MockERC20.deploy("DAI", "DAI");
        await underlying.deployed();
        // 10M to creator
        incentiveToken = await MockERC20.deploy("IDLE", "IDLE");
        await incentiveToken.deployed();
        incentiveTokens = [incentiveToken.address];
    
        idleToken = await MockIdleToken.deploy(underlying.address);
        await idleToken.deployed();
        idleToken2 = await MockIdleToken.deploy(underlying.address);
        await idleToken2.deployed();
    
        strategy = await helpers.deployUpgradableContract("IdleStrategy", [idleToken.address, owner.address], owner);
        strategy2 = await helpers.deployUpgradableContract("IdleStrategy", [idleToken2.address, owner.address], owner);
        idleCDO = await helpers.deployUpgradableContract(
          "EnhancedIdleCDO",
          [
            BN("1000000").mul(ONE_TOKEN(18)), // limit
            underlying.address, //guard
            owner.address, // gov
            owner.address, //owner
            owner.address, //rebalancer
            strategy.address,
            BN("20000"), // apr split: 20% interest to AA and 80% BB
            BN("50000"), // ideal value: 50% AA and 50% BB tranches
            incentiveTokens,
          ],
          owner
        );
    
        await idleCDO.setWethForTest(weth.address);
        await idleCDO.setUniRouterForTest(uniRouter.address);
    
        AA = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
        BB = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());
    
        const stakingRewardsParams = [
          incentiveTokens,
          owner.address, // owner / guardian
          idleCDO.address,
          owner.address, // recovery address
          10, // cooling period
        ];
        stakingRewardsAA = await helpers.deployUpgradableContract("IdleCDOTrancheRewards", [AA.address, ...stakingRewardsParams], owner);
        stakingRewardsBB = await helpers.deployUpgradableContract("IdleCDOTrancheRewards", [BB.address, ...stakingRewardsParams], owner);
        await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);
    
        await idleCDO.setUnlentPerc(BN("0"));
        await idleCDO.setIsStkAAVEActive(false);
    
        // Params
        initialAmount = BN("100000").mul(ONE_TOKEN(18));
        // Fund wallets
        await helpers.fundWallets(underlying.address, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, BBBuyer2Addr, idleToken.address], owner.address, initialAmount);
    
        // set IdleToken mocked params
        await idleToken.setTokenPriceWithFee(BN(10 ** 18));
        // set IdleToken2 mocked params
        await idleToken2.setTokenPriceWithFee(BN(2 * 10 ** 18));
  }

  async function idleCDOCardsTestDeploy(params) {

    await initialIdleContractsDeploy();
  
    // idle cdo cards deploy
    const IdleCDOCards = await hre.ethers.getContractFactory("IdleCDOCards");
    cards = await IdleCDOCards.deploy(idleCDO.address);
    await cards.deployed();
  
    //approve
    await approveNFT(idleCDO, cards, AABuyerAddr, D18("100000"));
  
    // APR AA=0 BB=10
    await idleToken.setFee(BN("0"));
    await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));
  
    //await setAprs();
    console.log("=".repeat(80));
    console.log(`📤 Idle CDO deployed at ${idleCDO.address} by owner ${owner.address}`);
    console.log(`📤 Idle CDO Cards deployed at ${cards.address}`);
    console.log("🔎 Buyer address:", AABuyerAddr);
    console.log("💵 Token address:", await idleToken.token());
    console.log("=".repeat(80));
    
  }
  
  module.exports = {
    setAprs,
    balance,
    approveNFT,
    mintAABuyer,
    mint,
    initialIdleContractsDeploy,
    idleCDOCardsTestDeploy
  }