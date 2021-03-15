const hre = require("hardhat");
const { IdleTokens } = require("../lib");
const { ethers, upgrades } = require("hardhat");
const BN = require("bignumber.js");

// config
const CHAIN_ID = 1;
const network = "mainnet";

const addresses = {
  bittrex: "0xfbb1b73c4f0bda4f67dca266ce6ef42f520fbb98",
  wbtc: "0xd1669ac6044269b59fa12c5822439f609ca54f41",
  governance: '0xD6dABBc2b275114a2366555d6C481EF08FDC2556',
  idleUSDCBest: '0x5274891bEC421B39D23760c04A6755eCB444797C',
  rebalancer: '0xb3c8e5534f0063545cbbb7ce86854bf42db8872b'
}

const check = (a, b, message) => {
  let [icon, symbol] = a === b ? ["✔️", "==="] : ["🚨🚨🚨", "!=="];
  console.log(`${icon}  `, a, symbol, b, message ? message : "");
}

const toBN = (v) => new BN(v.toString());

const start = async ({ idleTokenAddress, holder }) => {
  console.log('starting...');
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [holder]
  });

  const IdleToken = await ethers.getContractAt('IIdleTokenV3_1', idleTokenAddress);
  const underlyingAddress = await IdleToken.token();
  const underlying = await ethers.getContractAt('IERC20Detailed', underlyingAddress);
  const decimals = toBN(await underlying.decimals()).toNumber();

  const ONE_UNDERLYING_UNIT = toBN(10 ** decimals);
  const ONE_IDLE_UNIT = toBN(10 ** 18);

  const toUnderlyingUnit = (v) => toBN(v).div(ONE_UNDERLYING_UNIT);
  const fromUnderlyingUnit = (v) => toBN(v).times(ONE_UNDERLYING_UNIT);
  const toIdleUnit = (v) => toBN(v).div(ONE_IDLE_UNIT);
  const fromIdleUnit = (v) => toBN(v).times(ONE_IDLE_UNIT);

  console.log("using holder", holder);
  console.log("using idle token " , (await IdleToken.name()), "-", idleTokenAddress);
  console.log("using underlying token", (await underlying.name()), "-", underlyingAddress);
  console.log("holder balance", toUnderlyingUnit(await underlying.balanceOf(holder)).toString());
  console.log(`underlying token decimals ${decimals}`);

  // deploy
  const idleCDOStrategy = await ethers.getContractFactory("IdleStrategy");
  const idleCDOStrategyInstance = await idleCDOStrategy.deploy(idleTokenAddress, addresses.governance);
  console.log("IdleStrategy deployed at", idleCDOStrategyInstance.address);

  const factory = await ethers.getContractFactory("IdleCDO");
  const idleCDOInstance = await upgrades.deployProxy(factory, [
    fromUnderlyingUnit('100000'), // _limit,
    fromUnderlyingUnit('10000'), // _userLimit,
    underlyingAddress, // _guardedToken,
    addresses.governance, //_governanceFund,
    addresses.rebalancer, // _rebalancer,
    idleCDOStrategyInstance.address,
    toBN('10000') // AA share of interest (100000 = 100%)
  ]);

  await idleCDOInstance.deployed();
  console.log("IdleCDO proxy deployed at", idleCDOInstance.address);
  const AATrancheInstance = await ethers.getContractFactory("IdleCDOTranche", await idleCDOInstance.AATranche());
  const BBTrancheInstance = await ethers.getContractFactory("IdleCDOTranche", await idleCDOInstance.BBTranche());

  console.log("AATrancheInstance deployed at", AATrancheInstance.address);
  console.log("BBTrancheInstance deployed at", BBTrancheInstance.address);
  console.log("##############################################");

  const logStuff = async (accountIndex, account) => {
    const table = {
      AA: {
        accountBalance: (await AATrancheInstance.balanceOf(account)).toString(),
        priceMint: toIdleUnit(await idleCDOInstance.tranchePrice(AATrancheInstance.address, false)).toString(),
        priceRedeem: toIdleUnit(await idleCDOInstance.tranchePrice(AATrancheInstance.address, true)),
        trancheApr: toIdleUnit(await idleCDOInstance.getApr(AATrancheInstance.address)).toString(),
        idealApr: toIdleUnit(await idleCDOInstance.getIdealApr(AATrancheInstance.address)).toString(),
        ratio: (await idleCDOInstance.getAARatio()).toString()
      },
      BB: {
        accountBalance: (await BBTrancheInstance.balanceOf(account)).toString(),
        priceMint: toIdleUnit(await idleCDOInstance.tranchePrice(BBTrancheInstance.address, false)).toString(),
        priceRedeem: toIdleUnit(await idleCDOInstance.tranchePrice(BBTrancheInstance.address, true)),
        trancheApr: toIdleUnit(await idleCDOInstance.getApr(BBTrancheInstance.address)).toString(),
        idealApr: toIdleUnit(await idleCDOInstance.getIdealApr(BBTrancheInstance.address)).toString(),
        ratio: (await idleCDOInstance.getBBRatio()).toString()
      }
    };
    console.table(table);
    console.table({
      contractUnderlyingBalance: toUnderlyingUnit(await underlying.balanceOf(idleCDOInstance.address)).toString(),
      contractIdleTokenBalance: toIdleUnit(await IdleToken.balanceOf(idleCDOInstance.address)).toString()
    });

    // console.log(`account ${accountIndex} bal of AA tranches`, (await AATrancheInstance.balanceOf(account)).toString());
    // console.log(`account ${accountIndex} bal of BB tranches`, (await BBTrancheInstance.balanceOf(account)).toString());
    // console.log("contract underlying balance", toUnderlyingUnit(await underlying.balanceOf(idleCDOInstance.address)).toString());
    // console.log("contract idle token balance", toIdleUnit(await IdleToken.balanceOf(idleCDOInstance.address)).toString());
    // console.log("AA tranche price mint", toIdleUnit(await idleCDOInstance.tranchePrice(AATrancheInstance.address, false)).toString());
    // console.log("AA tranche price mint", toIdleUnit(await idleCDOInstance.tranchePrice(AATrancheInstance.address, false)).toString());
    // console.log("BB tranche price redeem", toIdleUnit(await idleCDOInstance.tranchePrice(BBTrancheInstance.address, true)).toString());
    // console.log("BB tranche price redeem", toIdleUnit(await idleCDOInstance.tranchePrice(BBTrancheInstance.address, true)).toString());
    // console.log("AA tranche apr", toIdleUnit(await idleCDOInstance.getApr(AATrancheInstance.address)).toString());
    // console.log("BB tranche apr", toIdleUnit(await idleCDOInstance.getApr(BBTrancheInstance.address)).toString());
    // console.log("Ideal AA apr", toIdleUnit(await idleCDOInstance.getIdealApr(AATrancheInstance.address)).toString());
    // console.log("Ideal BB apr", toIdleUnit(await idleCDOInstance.getIdealApr(BBTrancheInstance.address)).toString());
    // console.log("Curr AA ratio", (await idleCDOInstance.getAARatio()).toString());
  };

  const deposit = async (accountIndex, amountInUnit, AATranche) => {
    const amount = fromUnderlyingUnit(amountInUnit).toString();
    const account = accounts[accountIndex];
    console.log(`⬇️  deposit of ${amountInUnit} (${(amount)}) from ${accountIndex} (${account})`)
    console.log("calling transfer");
    await underlying.transfer(account, amount, { from: holder });
    console.log("calling approve");
    await underlying.approve(idleCDOInstance.address, amount, { from: account });
    console.log("calling deposit");
    if (AATranche) {
      await idleCDOInstance.depositAA(amount, { from: account });
    } else {
      await idleCDOInstance.depositBB(amount, { from: account });
    }

    await logStuff(accountIndex, account);
  }

  await deposit(0, 10, true); // true == AA tranche the one with low apr
  await deposit(1, 30, false);
  await deposit(2, 60, false);

  // await advanceBlocks(2);

  await idleCDOInstance.withdraw(0, { from: accounts[0] });
  await idleCDOInstance.withdraw(0, { from: accounts[1] });
  await idleCDOInstance.withdraw(0, { from: accounts[2] });

  check(toIdleUnit(await IdleToken.balanceOf(accounts[0])).toString(), toBN("10").times(ONE_IDLE_UNIT).div(priceExecute).div(ONE_IDLE_UNIT).toString());
  check(toIdleUnit(await IdleToken.balanceOf(accounts[1])).toString(), toBN("30").times(ONE_IDLE_UNIT).div(priceExecute).div(ONE_IDLE_UNIT).toString());
  check(toIdleUnit(await IdleToken.balanceOf(accounts[2])).toString(), toBN("150").times(ONE_IDLE_UNIT).div(priceExecute).div(ONE_IDLE_UNIT).toString());
}

const main = async () => {
  await start({idleTokenAddress: addresses.idleUSDCBest, holder: addresses.bittrex});
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
