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

  // FEI APR AA=16 BB=4
  const setFEIAprs = async () => {
    await idleTokenFEI.setFee(BN("0"));
    await idleTokenFEI.setApr(BN("10").mul(ONE_TOKEN(18)));
    await mintCDO(idleCDOFEI, D18(0.5), ONE_THOUSAND_TOKEN, AABuyer);
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
    await mintCDO(idleCDO, exposure, _amount, signer);
  };

  const mintCDO = async (_idleCDO, exposure, _amount, signer) => {
    //approve
    await approveNFT(_idleCDO, cards, signer.address, _amount);
    //mint
    tx = await cards.connect(signer)["mint(address,uint256,uint256)"](_idleCDO.address, exposure, _amount);
    await tx.wait();
    //harvest
    await _idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);
  };

  const combineCDOs = async (signer,exposureDAI, amountDAI, exposureFEI, amountFEI) => {

    await approveNFT(idleCDO, cards, AABuyerAddr, ONE_THOUSAND_TOKEN);
    await approveNFT(idleCDOFEI, cards, AABuyerAddr, ONE_THOUSAND_TOKEN);
    
    tx = await cards.connect(signer)["mint(address,uint256,uint256,address,uint256,uint256)"](idleCDO.address, exposureDAI, amountDAI, idleCDOFEI.address,exposureFEI, amountFEI);
    await tx.wait();

    //harvest
    await idleCDO.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);
    await idleCDOFEI.harvest([true, true, false, false], [true], [BN("0")], [BN("0")], 0);
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

        //deploy FEI
        underlyingFEI = await MockERC20.deploy("FEI", "FEI");
        await underlyingFEI.deployed();

        // 10M to creator
        incentiveToken = await MockERC20.deploy("IDLE", "IDLE");
        await incentiveToken.deployed();
        incentiveTokens = [incentiveToken.address];
    
        idleToken = await MockIdleToken.deploy(underlying.address);
        await idleToken.deployed();
        idleToken2 = await MockIdleToken.deploy(underlying.address);
        await idleToken2.deployed();

        // FEI idle tokens
        idleTokenFEI = await MockIdleToken.deploy(underlyingFEI.address);
        await idleTokenFEI.deployed();
        idleToken2FEI = await MockIdleToken.deploy(underlyingFEI.address);
        await idleTokenFEI.deployed();

        strategy = await helpers.deployUpgradableContract("IdleStrategy", [idleToken.address, owner.address], owner);
        strategy2 = await helpers.deployUpgradableContract("IdleStrategy", [idleToken2.address, owner.address], owner);

        //FEI strategy
        strategyFEI = await helpers.deployUpgradableContract("IdleStrategy", [idleTokenFEI.address, owner.address], owner);
        strategy2FEI = await helpers.deployUpgradableContract("IdleStrategy", [idleToken2FEI.address, owner.address], owner);

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

        //FEI idle CDO
        idleCDOFEI = await helpers.deployUpgradableContract(
          "EnhancedIdleCDO",
          [
            BN("1000000").mul(ONE_TOKEN(18)), // limit
            underlyingFEI.address, //guard
            owner.address, // gov
            owner.address, //owner
            owner.address, //rebalancer
            strategyFEI.address,
            BN("20000"), // apr split: 20% interest to AA and 80% BB
            BN("50000"), // ideal value: 50% AA and 50% BB tranches
            incentiveTokens,
          ],
          owner
        );
    
        await idleCDO.setWethForTest(weth.address);
        await idleCDO.setUniRouterForTest(uniRouter.address);
    
        await idleCDOFEI.setWethForTest(weth.address);
        await idleCDOFEI.setUniRouterForTest(uniRouter.address);

        AA = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
        BB = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());
    
        AAFEI = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDOFEI.AATranche());
        BBFEI = await hre.ethers.getContractAt("IdleCDOTranche", await idleCDOFEI.BBTranche());
        
        const stakingRewardsParams = [
          incentiveTokens,
          owner.address, // owner / guardian
          idleCDO.address,
          owner.address, // recovery address
          10, // cooling period
        ];

        const stakingRewardsParamsFEI = [
          incentiveTokens,
          owner.address, // owner / guardian
          idleCDOFEI.address,
          owner.address, // recovery address
          10, // cooling period
        ];

        stakingRewardsAA = await helpers.deployUpgradableContract("IdleCDOTrancheRewards", [AA.address, ...stakingRewardsParams], owner);
        stakingRewardsBB = await helpers.deployUpgradableContract("IdleCDOTrancheRewards", [BB.address, ...stakingRewardsParams], owner);
        await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);
      
        stakingRewardsAAFEI = await helpers.deployUpgradableContract("IdleCDOTrancheRewards", [AAFEI.address, ...stakingRewardsParamsFEI], owner);
        stakingRewardsBBFEI = await helpers.deployUpgradableContract("IdleCDOTrancheRewards", [BBFEI.address, ...stakingRewardsParamsFEI], owner);
        await idleCDOFEI.setStakingRewards(stakingRewardsAAFEI.address, stakingRewardsBBFEI.address);

        await idleCDO.setUnlentPerc(BN("0"));
        await idleCDO.setIsStkAAVEActive(false);
    
        await idleCDOFEI.setUnlentPerc(BN("0"));
        await idleCDOFEI.setIsStkAAVEActive(false);

        // Params
        initialAmount = BN("100000").mul(ONE_TOKEN(18));
        // Fund wallets
        await helpers.fundWallets(underlying.address, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, BBBuyer2Addr, idleToken.address], owner.address, initialAmount);
        await helpers.fundWallets(underlyingFEI.address, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, BBBuyer2Addr, idleTokenFEI.address], owner.address, initialAmount);

        // set IdleToken mocked params
        await idleToken.setTokenPriceWithFee(BN(10 ** 18));
        // set IdleToken2 mocked params
        await idleToken2.setTokenPriceWithFee(BN(2 * 10 ** 18));

        // set IdleTokenFEI mocked params
        await idleTokenFEI.setTokenPriceWithFee(BN(10 ** 18));
        // set IdleToken2FEI mocked params
        await idleToken2FEI.setTokenPriceWithFee(BN(2 * 10 ** 18));        
  }

  async function idleCDOCardsTestDeploy(params) {

    await initialIdleContractsDeploy();
  
    // idle cdo cards deploy
    const IdleCDOCardManager = await hre.ethers.getContractFactory("IdleCDOCardManager");
    cards = await IdleCDOCardManager.deploy([idleCDO.address, idleCDOFEI.address]);
    await cards.deployed();
  
    //Configure DAI idleCDO
    //approve
    await approveNFT(idleCDO, cards, AABuyerAddr, D18("100000"));
    // APR AA=0 BB=10
    await idleToken.setFee(BN("0"));
    await idleToken.setApr(BN("10").mul(ONE_TOKEN(18)));

    //Configure FEI idleCDO
    //approve
    await approveNFT(idleCDOFEI, cards, AABuyerAddr, D18("100000"));
    // APR AA=0 BB=10
    await idleTokenFEI.setFee(BN("0"));
    await idleTokenFEI.setApr(BN("20").mul(ONE_TOKEN(18)));
  
    //await setAprs();
    console.log("=".repeat(80));
    console.log(`📤 Idle CDO Cards deployed at ${cards.address}`);
    console.log(`📤 Idle CDO DAI deployed at ${idleCDO.address} by owner ${owner.address}`);
    console.log("💵 DAI Underlying Token address:", await idleToken.token());
    console.log(`📤 Idle CDO FEI deployed at ${idleCDOFEI.address} by owner ${owner.address}`);
    console.log("💵 FEI Underlying Token address:", await idleTokenFEI.token());
    console.log("🔎 Buyer address:", AABuyerAddr);
    console.log("=".repeat(80));
    
  }
  
  module.exports = {
    setAprs,
    setFEIAprs,
    balance,
    approveNFT,
    mintAABuyer,
    mint,
    mintCDO,
    combineCDOs,
    initialIdleContractsDeploy,
    idleCDOCardsTestDeploy
  }