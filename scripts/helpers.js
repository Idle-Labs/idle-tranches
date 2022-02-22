const rl = require("readline");
const { BigNumber } = require("@ethersproject/bignumber");
const { time } = require("@openzeppelin/test-helpers");
const addresses = require("../lib/addresses");
const { LedgerSigner } = require("@ethersproject/hardware-wallets");
const { SafeEthersSigner, SafeService } = require("@gnosis.pm/safe-ethers-adapters");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));

const log = (...arguments) => {
  if (hre.network.config.chainId == '31337' && !hre.network.config.forking) {
    return;
  }
  console.log(...arguments);
}

const advanceNBlock = async (n) => {
  let startingBlock = await time.latestBlock();
  await time.increase(15 * Math.round(n));
  let endBlock = startingBlock.addn(n);
  await time.advanceBlockTo(endBlock);
}

const impersonateSigner = async (acc) => {
  await hre.ethers.provider.send("hardhat_impersonateAccount", [acc]);
  await hre.ethers.provider.send("hardhat_setBalance", [acc, "0xffffffffffffffff"]);
  return await hre.ethers.getSigner(acc);
}
const getMultisigSigner = async (skipLog) => {
  const ledgerSigner = new LedgerSigner(ethers.provider, undefined, "m/44'/60'/0'/0/0");
  const service = new SafeService('https://safe-transaction.gnosis.io/');
  const signer = await SafeEthersSigner.create(
    addresses.IdleTokens.mainnet.devLeagueMultisig, ledgerSigner, service, ethers.provider
  );
  const address = await signer.getAddress();
  if (!skipLog) {
    log(`Deploying with ${address}`);
    log();
  }
  return signer;
};
const getSigner = async (acc) => {
  let signer;
  if (acc) {
    // impersonate
    signer = await impersonateSigner(acc);
  } else {
    // get first signer
    [signer] = await hre.ethers.getSigners();
  }
  // In mainnet overwrite signer to be the ledger signer
  if (hre.network.name == 'mainnet') {
    signer = new LedgerSigner(ethers.provider, undefined, "m/44'/60'/0'/0/0");
  }
  const address = await signer.getAddress();
  // log(`Deploying with ${address}, balance ${BN(await ethers.provider.getBalance(address)).div(ONE_TOKEN(18))} ETH`);
  // log();
  return signer;
};
const callContract = async (address, method, params, from = null) => {
  // log(`Call contract ${address}, method: ${method} with params ${params}`);
  let contract = await ethers.getVerifiedContractAt(address);
  if (from) {
    [contract] = await sudo(from, contract);
  }

  const res = await contract[method](...params);
  return res;
};
const deployContract = async (contractName, params, signer) => {
  log(`Deploying ${contractName}`);
  const contractFactory = await ethers.getContractFactory(contractName, signer);
  let contract = await contractFactory.deploy(...params);
  await contract.deployed();
  let contractReceipt = await contract.deployTransaction.wait()
  log(`📤 ${contractName} created: ${contract.address} @tx: ${contractReceipt.transactionHash} ((gas ${contractReceipt.cumulativeGasUsed.toString()}))`);
  log();
  return contract;
};
const deployUpgradableContract = async (contractName, params, signer) => {
  log(`Deploying ${contractName}`);
  const contractFactory = await ethers.getContractFactory(contractName, signer);
  // do not use spread (...) operator here
  let contract = await hre.upgrades.deployProxy(contractFactory, params);
  await contract.deployed();
  let contractReceipt = await contract.deployTransaction.wait()
  log(`📤 ${contractName} created (proxy): ${contract.address} @tx: ${contractReceipt.transactionHash}, (gas ${contractReceipt.cumulativeGasUsed.toString()})`);
  return contract;
};
const upgradeContract = async (address, contractName, signer) => {
  log(`Upgrading ${contractName}`);
  const contractFactory = await ethers.getContractFactory(contractName, signer);
  let contract = await hre.upgrades.upgradeProxy(address, contractFactory);
  // NOTE: Method + params cannot be passed for reinit on upgrades!
  // do not use spread (...) operator here
  // let contract = await upgrades.upgradeProxy(address, contractFactory, params);
  let contractReceipt = await contract.deployTransaction.wait();
  console.log(contractReceipt);
  log(`📤 ${contractName} upgraded (proxy): ${contract.address} @tx: ${contractReceipt.transactionHash} (gas ${contractReceipt.cumulativeGasUsed.toString()})`);
  return contract;
};
const prepareContractUpgrade = async (address, contractName, signer) => {
  log(`Upgrading ${contractName}`);
  const contractFactory = await ethers.getContractFactory(contractName, signer);
  let impl = await hre.upgrades.prepareUpgrade(address, contractFactory);
  log(`📤 ${contractName} new implementation deployed: ${impl}`);
  return impl;
};
const fundWallets = async (underlying, to, from, amount) => {
  await hre.network.provider.send("hardhat_setBalance", [from, "0xffffffffffffffff"])

  let underlyingContract = await ethers.getContractAt("IERC20Detailed", underlying);
  const decimals = await underlyingContract.decimals();
  [underlyingContract] = await sudo(from, underlyingContract);
  for (var i = 0; i < to.length; i++) {
    await underlyingContract.transfer(to[i], amount);
    const newBal = await underlyingContract.balanceOf(to[i]);
    log(`💵 [FUND] (+ ${amount.div(ONE_TOKEN(decimals))}) to: ${to[i]}, New Balance: ${BN(newBal).div(ONE_TOKEN(decimals))}`);
  }
};
const oneToken = async addr => {
  let underlyingContract = await ethers.getContractAt("IERC20Detailed", addr);
  const decimals = await underlyingContract.decimals();
  return BigNumber.from('10').pow(BigNumber.from(decimals));
}
const prompt = async (question, onlyMainnet = true) => {
  if (onlyMainnet && hre.network.name != 'mainnet') {
    return;
  }

  const r = rl.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
  });

  let answer = await new Promise((resolve, error) => {
    r.question(question, answer => {
      r.close();
      resolve(answer);
    });
  });

  if (answer !== "y" && answer !== "yes") {
    log("exiting...");
    process.exit(1);
  }
};
const check = (a, b, message) => {
  a = a.toString();
  b = b.toString();
  let [icon, symbol] = a.toString() === b ? ["✔️", "==="] : ["🚨🚨🚨", "!=="];
  log(`${icon}  `, a, symbol, b, message ? message : "");
};
const checkAproximate = (a, b, message) => { // check a is withing 5% of b
  a = BigNumber.from(a.toString())
  b = BigNumber.from(b.toString())

  let _check
  if (b.eq(BigNumber.from('0'))) {
    _check = a.eq(b)
  } else {
    _check = b.mul("95").lte(a.mul("100")) && a.mul("100").lte(b.mul("105"))
  }

  let [icon, symbol] = _check ? ["✔️", "~="] : ["🚨🚨🚨", "!~="];
  log(`${icon}  `, a.toString(), symbol, b.toString(), message ? message : "");
};
const checkIncreased = (a, b, message) => {
  let [icon, symbol] = b.gt(a) ? ["✔️", "<"] : ["🚨🚨🚨", ">="];
  log(`${icon}  `, a.toString(), symbol, b.toString(), message ? message : "");
};
const toETH = n => ethers.utils.parseEther(n.toString());
const sudo = async (acc, contract = null) => {
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [acc] });
  const signer = await ethers.provider.getSigner(acc);
  if (contract) {
    contract = await contract.connect(signer);
  }
  return [contract, signer];
};
const sudoCall = async (acc, contract, method, params) => {
  const [contractImpersonated, signer] = await sudo(acc, contract);
  await hre.ethers.provider.send("hardhat_setBalance", [acc, "0xffffffffffffffff"]);
  const res = await contractImpersonated[method](...params);
  const receipt = await res.wait();
  // console.log('⛽ used: ', receipt.gasUsed.toString());
  return [contractImpersonated, signer, receipt]
};
const sudoStaticCall = async (acc, contract, method, params) => {
  const [contractImpersonated, signer] = await sudo(acc, contract);
  return await contractImpersonated.callStatic[method](...params);
};
const waitDays = async d => {
  await time.increase(time.duration.days(d));
};
const resetFork = async (blockNumber) => {
  await hre.network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${hre.env('ALCHEMY_API_KEY')}`,
          blockNumber,
        }
      }
    ]
  });
};

const deposit = async (type, idleCDO, addr, amount) => {
  log(`🟩 Deposit ${type}, addr: ${addr}, amount: ${amount}`);
  let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());
  let AAContract = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
  let BBContract = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());

  await sudoCall(addr, underlyingContract, 'approve', [idleCDO.address, amount]);
  await sudoCall(addr, idleCDO, type == 'AA' ? 'depositAA' : 'depositBB', [amount]);
  const aaTrancheBal = BN(await (type == 'AA' ? AAContract : BBContract).balanceOf(addr));
  log(`🚩 ${type}Balance: `, aaTrancheBal.toString());
  return aaTrancheBal;
}

const fundAndDeposit = async (type, idleCDO, user, amount) => {
  const underlyingAddr = await idleCDO.token();
  await fundAccount(underlyingAddr, user, amount);
  const underlying = await ethers.getContractAt('IERC20Detailed', underlyingAddr);
  console.log('balance ', (await underlying.balanceOf(user)).toString())
  return deposit(type, idleCDO, user, amount);
}

// fund a random address with tokens
// from https://blog.euler.finance/brute-force-storage-layout-discovery-in-erc20-contracts-with-hardhat-7ff9342143ed
const fundAccount = async (tokenAddress, accountToSet, amount) => {
  const encode = (types, values) => ethers.utils.defaultAbiCoder.encode(types, values);
  const probeA = encode(['uint'], [1]);
  const probeB = encode(['uint'], [2]);
  const token = await ethers.getContractAt('IERC20Detailed', tokenAddress);
  const account = addresses.addr0;
  let balanceSlot;

  for (let i = 0; i < 100; i++) {
    let probedSlot = ethers.utils.keccak256(
      encode(['address', 'uint'], [account, i])
    );
    // remove padding for JSON RPC
    while (probedSlot.startsWith('0x0'))
      probedSlot = '0x' + probedSlot.slice(3);
    const prev = await network.provider.send(
      'eth_getStorageAt',
      [tokenAddress, probedSlot, 'latest']
    );
    // make sure the probe will change the slot value
    const probe = prev === probeA ? probeB : probeA;

    await network.provider.send("hardhat_setStorageAt", [
      tokenAddress,
      probedSlot,
      probe
    ]);

    const balance = await token.balanceOf(account);
    // reset to previous value
    await network.provider.send("hardhat_setStorageAt", [
      tokenAddress,
      probedSlot,
      prev
    ]);

    if (balance.eq(ethers.BigNumber.from(probe))) {
      balanceSlot = i;
      break;
    }
  }

  if (!balanceSlot) {
    throw 'Balances slot not found!';
  }
  
  // Replaced this:
  //   let valueSlot = encode(['address', 'uint'], [accountToSet, balanceSlot]).replace(/0x0+/, "0x");
  // with (following https://github.com/element-fi/elf-frontend-testnet/blob/c929e4a1385e49e3728611e3db73f02a7ed35595/src/scripts/manipulateTokenBalances.ts#L113)
  let valueSlot = ethers.utils.solidityKeccak256(['uint256', 'uint256'], [accountToSet, balanceSlot]);
  let encodedAmount = encode(['uint'], [amount]);
  await network.provider.send('hardhat_setStorageAt', [
    tokenAddress, valueSlot, encodedAmount
  ]);
}

const depositAndStake = async (type, idleCDO, addr, amount) => {
  const trancheBal = await deposit(type, idleCDO, addr, amount);
  const stakingRewardsAddr = await idleCDO[type == 'AA' ? 'AAStaking' : 'BBStaking']();
  let staked = 0;
  if (stakingRewardsAddr && stakingRewardsAddr != addresses.addr0) {
    log(`🟩 Stake ${type}, addr: ${addr}, trancheBal: ${trancheBal}`);
    const stakingRewards = await ethers.getContractAt("IdleCDOTrancheRewards", stakingRewardsAddr);
    const trancheAddr = await idleCDO[type == 'AA' ? 'AATranche' : 'BBTranche']()
    const tranche = await ethers.getContractAt("IdleCDOTranche", trancheAddr);
    await sudoCall(addr, tranche, 'approve', [stakingRewardsAddr, amount]);
    await sudoCall(addr, stakingRewards, 'stake', [trancheBal]);
    staked = await stakingRewards.usersStakes(addr);
  }
  return [trancheBal, BN(staked)];
}

const withdrawAndUnstakeWithGain = async (type, idleCDO, addr, initialAmount) => {
  const stakingRewardsAddr = await idleCDO[type == 'AA' ? 'AAStaking' : 'BBStaking']();
  const stakingRewards = await ethers.getContractAt("IdleCDOTrancheRewards", stakingRewardsAddr);
  const staked = await stakingRewards.usersStakes(addr);
  log(`🟩 Staked ${type}, addr: ${addr}, amount: ${staked}`);
  await sudoCall(addr, stakingRewards, 'unstake', [staked]);
  // const trancheBal = BN(await (type == 'AA' ? AAContract : BBContract).balanceOf(addr));
  return await withdrawWithGain(type, idleCDO, addr, initialAmount);
}

const withdrawWithGain = async (type, idleCDO, addr, initialAmount) => {
  let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());
  let AAContract = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
  let BBContract = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());
  const isAA = type == 'AA';
  const trancheBal = await (isAA ? AAContract : BBContract).balanceOf(addr);
  const balBefore = BN(await underlyingContract.balanceOf(addr));
  await sudoCall(addr, idleCDO, isAA ? 'withdrawAA' : 'withdrawBB', [trancheBal]);
  const balAfter = BN(await underlyingContract.balanceOf(addr));
  const gain = balAfter.sub(balBefore).sub(initialAmount);
  log(`🚩 Withdraw ${type}, addr: ${addr}, Underlying bal after: ${balAfter}, gain: ${gain}`);
  checkIncreased(BN('0'), gain, 'Gain should always be > 0 if redeeming after waiting at least 1 harvest');
  return balAfter;
}

const withdraw = async (type, idleCDO, addr, amount) => {
  let underlyingContract = await ethers.getContractAt("IERC20Detailed", await idleCDO.token());
  let AAContract = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
  let BBContract = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());
  const isAA = type == 'AA';
  const balBefore = BN(await underlyingContract.balanceOf(addr));
  await sudoCall(addr, idleCDO, isAA ? 'withdrawAA' : 'withdrawBB', [amount]);
  const balAfter = BN(await underlyingContract.balanceOf(addr));
  const gain = balAfter.sub(balBefore);
  log(`🚩 Withdraw ${type}, addr: ${addr}, Underlying bal after: ${balAfter}, gain: ${gain}`);
  return balAfter;
}

const getBalance = async (tokenContract, address) => {
  return BN(await tokenContract.balanceOf(address));
}
const getTokenBalance = async (tokenAddress, address) => {
  const contract = await ethers.getContractAt("IERC20Detailed", tokenAddress);
  return BN(await contract.balanceOf(address));
}
const checkBalance = async (tokenContract, address, balance) => {
  const bal = await getBalance(tokenContract, address);
  check(bal, balance, `Requested bal ${bal} is equal to the provided one ${balance}`);
}

const isEmptyString = (s) => {
  if (s === undefined || s === null) {
    return true;
  }

  return s.toString().trim() == "";
}

// paramsType: array of params types eg ['address', 'uint256']
// params: array of params eg [to, amount]
const encodeParams = (paramsType, params) => {
  const abiCoder = new hre.ethers.utils.AbiCoder();
  return abiCoder.encode(paramsType, params);
}

// method: string eg "transfer(address,uint256)"
// methodName: string eg "transfer"
// params: array of params eg [to, amount]
const encodeFunctionCall = (method, methodName, params) => {
  let iface = new ethers.utils.Interface([`function ${method}`]);
  return iface.encodeFunctionData(methodName, params)
}

module.exports = {
  advanceNBlock,
  impersonateSigner,
  getMultisigSigner,
  getSigner,
  callContract,
  deployContract,
  deployUpgradableContract,
  upgradeContract,
  prepareContractUpgrade,
  fundWallets,
  prompt,
  check,
  checkAproximate,
  checkIncreased,
  toETH,
  sudo,
  sudoCall,
  sudoStaticCall,
  waitDays,
  resetFork,
  oneToken,
  deposit,
  fundAndDeposit,
  fundAccount,
  withdraw,
  withdrawWithGain,
  getBalance,
  getTokenBalance,
  checkBalance,
  isEmptyString,
  log,
  encodeFunctionCall,
  encodeParams,
  depositAndStake,
  withdrawAndUnstakeWithGain,
}
