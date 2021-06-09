require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;

const DAI = {
  decimals: 18,
  underlying: mainnetContracts.DAI,
  idleToken: mainnetContracts.idleDAIBest,
  cToken: mainnetContracts.cDAI
};
const USDC = {
  decimals: 6,
  underlying: mainnetContracts.USDC,
  idleToken: mainnetContracts.idleUSDCBest,
  cToken: mainnetContracts.cUSDC
};

const testToken = USDC;

/**
 * @name deploy
 */
task("deploy", "Deploy IdleCDO and IdleStrategy with default parameters")
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    await helpers.prompt("continue? [y/n]", true);
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [testToken.idleToken, creator], signer);
    const idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('5000000').mul(ONE_TOKEN(testToken.decimals)), // limit
        testToken.underlying,
        mainnetContracts.devLeagueMultisig,
        creator, // guardian
        mainnetContracts.rebalancer,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000') // ideal value: 50% AA and 50% BB tranches
      ],
      signer
    );

    const AAaddr = await idleCDO.AATranche();
    const BBaddr = await idleCDO.BBTranche();
    console.log(`AATranche: ${AAaddr}, BBTranche: ${BBaddr}`);
    console.log();
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

/**
 * @name print-info
 */
task("print-info")
  .addOptionalParam('cdo')
  .setAction(async ({cdo}) => {
    let idleCDO;
    let AAaddr;
    let BBaddr;
    let strategy;
    if (cdo) {
      idleCDO = await ethers.getContractAt("IdleCDO", cdo);
      AAaddr = await idleCDO.AATranche();
      BBaddr = await idleCDO.BBTranche();
      strategy = await ethers.getContractAt("IIdleCDOStrategy", await idleCDO.strategy());
    } else {
      // Run 'deploy' task
      const res = await run("deploy");
      idleCDO = res.idleCDO;
      AAaddr = res.AAaddr;
      BBaddr = res.BBaddr;
      strategy = res.strategy;
    }

    let idleToken = await ethers.getContractAt("IIdleToken", await strategy.strategyToken());
    const rewardTokens = await idleCDO.getRewards();

    const [
      lastStrategyPrice,
      strategyPrice,
      tranchePriceAA,
      tranchePriceBB,
      lastTranchePriceAA,
      lastTranchePriceBB,
      strategyAPR,
      getAprAA,
      getAprBB,
      getIdealAprAA,
      getIdealAprBB,
      contractVal,
      getCurrentAARatio,
    ] = await Promise.all([
      // Check prices
      idleCDO.lastStrategyPrice(),
      idleCDO.strategyPrice(),
      idleCDO.tranchePrice(AAaddr),
      idleCDO.tranchePrice(BBaddr),
      idleCDO.lastTranchePrice(AAaddr),
      idleCDO.lastTranchePrice(BBaddr),
      // Aprs
      idleCDO.strategyAPR(),
      idleCDO.getApr(AAaddr),
      idleCDO.getApr(BBaddr),
      idleCDO.getIdealApr(AAaddr),
      idleCDO.getIdealApr(BBaddr),
      // Values
      idleCDO.getContractValue(),
      idleCDO.getCurrentAARatio()
    ]);

    // const rewards = await Promise.all(rewardTokens.map(async r => {
    //   const underlyingContract = await ethers.getContractAt("IERC20Detailed", r);
    //   return {
    //     rewardToken: r,
    //     balance: await underlyingContract.balanceOf(idleCDO.address)
    //   }
    // }));
    // const rewardsStrategy = await Promise.all(rewardTokens.map(async r => {
    //   const underlyingContract = await ethers.getContractAt("IERC20Detailed", r);
    //   return {
    //     rewardToken: r,
    //     balance: await underlyingContract.balanceOf(strategy.address)
    //   }
    // }));

    console.log('📄 Info 📄');
    console.log(`#### Prices (strategyPrice ${BN(strategyPrice)}, (Last: ${BN(lastStrategyPrice)})) ####`);
    console.log(`tranchePriceAA ${BN(tranchePriceAA)}, (Last: ${BN(lastTranchePriceAA)})`);
    console.log(`tranchePriceBB ${BN(tranchePriceBB)}, (Last: ${BN(lastTranchePriceBB)})`);
    console.log(`#### Aprs (strategyAPR ${BN(strategyAPR)}) ####`);
    console.log(`getAprAA ${BN(getAprAA)}, (Ideal: ${BN(getIdealAprAA)})`);
    console.log(`getAprBB ${BN(getAprBB)}, (Ideal: ${BN(getIdealAprBB)})`);
    console.log('#### Other values ####');
    console.log('Underlying val', BN(contractVal).toString());
    console.log('getCurrentAARatio', BN(getCurrentAARatio).toString());
    // for (var i = 0; i < rewards.length; i++) {
    //   const r = rewards[i];
    //   console.log(`Balance of ${r.rewardToken}: ${r.balance}`);
    // }
    // for (var i = 0; i < rewardsStrategy.length; i++) {
    //   const r = rewardsStrategy[i];
    //   console.log(`Strategy Balance of ${r.rewardToken}: ${r.balance}`);
    // }
    console.log();

    return {idleCDO, AAaddr, BBaddr, strategy, idleToken};
  });

task("print-balance")
  .addOptionalParam('address')
  .setAction(async (args) => {
    let COMPBal = await helpers.callContract(mainnetContracts.COMP, 'balanceOf', [args.address]);
    let IDLEBal = await helpers.callContract(mainnetContracts.IDLE, 'balanceOf', [args.address]);
    let underlyingContract = await ethers.getContractAt("IERC20Detailed", testToken.underlying);
    let underlyingBalance = await underlyingContract.balanceOf(args.address);
    console.log('COMPBal', COMPBal.toString());
    console.log('IDLEBal', IDLEBal.toString());
    console.log('underlyingBalance', underlyingBalance.toString());
});

/**
 * @name buy
 */
task("buy")
  .setAction(async (args) => {
    let {idleCDO, AAaddr, BBaddr, idleToken, strategy} = await run("print-info");

    console.log('### Setup');
    // Get signers
    let [creator, AAbuyer, BBbuyer, AAbuyer2] = await ethers.getSigners();
    // Get contracts
    const underlying = await idleCDO.token();
    let cTokenContract = await ethers.getContractAt("IERC20Detailed", testToken.cToken);
    let underlyingContract = await ethers.getContractAt("IERC20Detailed", underlying);
    let AAContract = await ethers.getContractAt("IdleCDOTranche", AAaddr);
    let BBContract = await ethers.getContractAt("IdleCDOTranche", BBaddr);
    // Get utils
    const oneToken = await helpers.oneToken(underlying);
    const creatorAddr = await creator.getAddress();
    const AABuyerAddr = await AAbuyer.getAddress();
    const AABuyer2Addr = await AAbuyer2.getAddress();
    const BBBuyerAddr = await BBbuyer.getAddress();
    // enrich idleCDO contract (do NOT reassign the object like below)
    // idleCDO = {...idleCDO, AAContract, BBContract, underlyingContract};
    idleCDO.idleToken = idleToken;
    idleCDO.AAContract = AAContract;
    idleCDO.BBContract = BBContract;
    idleCDO.underlyingContract = underlyingContract;
    // Params
    const amount = BN('100000').mul(oneToken);
    // Fund wallets
    await helpers.fundWallets(underlying, [AABuyerAddr, BBBuyerAddr, AABuyer2Addr, creatorAddr], addresses.whale, amount);

    console.log('### Buying tranches');
    // Buy AA tranche with `amount` underlying
    const aaTrancheBal = await deposit('AA', idleCDO, AABuyerAddr, amount);
    // Buy BB tranche with `amount` underlying
    await deposit('BB', idleCDO, BBBuyerAddr, amount.div(BN('2')));
    // Do an harvest to do a real deposit in Idle
    // no gov tokens collected now because it's the first deposit
    await rebalanceFull(idleCDO, creatorAddr, true);
    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa2TrancheBal = await deposit('AA', idleCDO, AABuyer2Addr, amount);
    // amount bought should be less than the one of AABuyerAddr because price increased
    await helpers.checkIncreased(aa2TrancheBal, aaTrancheBal, 'AA1 bal is greater than the newly minted bal after harvest');

    let feeReceiverBBBal = await idleCDO.BBContract.balanceOf(mainnetContracts.feeReceiver);
    // tranchePriceAA and tranchePriceBB have been updated right before the deposit
    // some gov token (IDLE but not COMP because it has been sold) should be present in the contract after the rebalance
    await rebalanceFull(idleCDO, creatorAddr);
    // feeReceiver should have received some BB tranches as fees
    let feeReceiverBBBalAfter = await idleCDO.BBContract.balanceOf(mainnetContracts.feeReceiver);
    await helpers.checkIncreased(feeReceiverBBBal, feeReceiverBBBalAfter, 'Fee receiver got some BB tranches');

    // First user withdraw
    await withdraw('AA', idleCDO, AABuyerAddr, amount);
    feeReceiverBBBal = await idleCDO.BBContract.balanceOf(mainnetContracts.feeReceiver);
    await rebalanceFull(idleCDO, creatorAddr);
    // Check that fee receiver got fees (in BB tranche tokens)
    feeReceiverBBBalAfter = await idleCDO.BBContract.balanceOf(mainnetContracts.feeReceiver);
    await helpers.checkIncreased(feeReceiverBBBal, feeReceiverBBBalAfter, 'Fee receiver got some BB tranches');

    await withdraw('BB', idleCDO, BBBuyerAddr, amount.div(BN('2')));
    await rebalanceFull(idleCDO, creatorAddr);

    await withdraw('AA', idleCDO, AABuyer2Addr, amount);
    let feeReceiverAABal = await idleCDO.AAContract.balanceOf(mainnetContracts.feeReceiver);
    await rebalanceFull(idleCDO, creatorAddr);
    // Check that fee receiver got fees (in AA tranche tokens)
    let feeReceiverAABalAfter = await idleCDO.AAContract.balanceOf(mainnetContracts.feeReceiver);
    await helpers.checkIncreased(feeReceiverAABal, feeReceiverAABalAfter, 'Fee receiver got some AA tranches');

    await run("print-balance", {address: idleCDO.address});
    idleTokenBal = await idleToken.balanceOf(idleCDO.address);
    console.log('idleTokenBal', idleTokenBal.toString());

    feeReceiverBBBalAfter = await idleCDO.BBContract.balanceOf(mainnetContracts.feeReceiver);
    console.log('feeReceiverBBBalAfter', feeReceiverBBBalAfter.toString());
    feeReceiverAABalAfter = await idleCDO.AAContract.balanceOf(mainnetContracts.feeReceiver);
    console.log('feeReceiverAABalAfter', feeReceiverAABalAfter.toString());

    return {idleCDO};
  });

const rebalanceFull = async (idleCDO, address, skipRedeem = false) => {
  await run("print-info", {cdo: idleCDO.address});
  console.log('🚧 Waiting some time + 🚜 Harvesting');
  await run("mine-multiple", {blocks: '500'});
  const rewardTokens = await idleCDO.getRewards();
  await helpers.sudoCall(address, idleCDO, 'harvest', [skipRedeem, rewardTokens.map(r => false), rewardTokens.map(r => BN('0'))]);
  await helpers.sudoCall(address, idleCDO.idleToken, 'rebalance', []);


  await run("mine-multiple", {blocks: '500'});
  // Poking cToken contract to accrue interest and let strategyPrice increase.
  // (be sure to have a pinned block with allocation in compound)
  await helpers.callContract(testToken.cToken, 'accrueInterest', [], address);
  console.log('🚧 After some time...');
  await run("print-info", {cdo: idleCDO.address});
}

const deposit = async (type, idleCDO, addr, amount) => {
  console.log(`🟩 Deposit ${type}, addr: ${addr}, amount: ${amount}`);
  await helpers.sudoCall(addr, idleCDO.underlyingContract, 'approve', [idleCDO.address, amount]);
  await helpers.sudoCall(addr, idleCDO, type == 'AA' ? 'depositAA' : 'depositBB', [amount]);
  const aaTrancheBal = BN(await (type == 'AA' ? idleCDO.AAContract : idleCDO.BBContract).balanceOf(addr));
  console.log(`🚩 ${type}Balance: `, aaTrancheBal.toString());
  return aaTrancheBal;
}

const withdraw = async (type, idleCDO, addr, initialAmount) => {
  const isAA = type == 'AA';
  const trancheBal = await (isAA ? idleCDO.AAContract : idleCDO.BBContract).balanceOf(addr);
  const balBefore = BN(await idleCDO.underlyingContract.balanceOf(addr));
  await helpers.sudoCall(addr, idleCDO, isAA ? 'withdrawAA' : 'withdrawBB', [trancheBal]);
  const balAfter = BN(await idleCDO.underlyingContract.balanceOf(addr));
  const gain = balAfter.sub(balBefore).sub(initialAmount);
  console.log(`🚩 Withdraw ${type}, addr: ${addr}, Underlying bal after: ${balAfter}, gain: ${gain}`);
  return balAfter;
}
