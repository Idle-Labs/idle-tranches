const rl = require("readline");
const { BigNumber } = require("@ethersproject/bignumber");
const { time } = require("@openzeppelin/test-helpers");
const addresses = require("../lib/index");
const { HardwareSigner } = require("../lib/HardwareSigner");
const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));

module.exports = {
  getSigner: async () => {
    let [signer] = await ethers.getSigners();
    if (hre.network.name == 'mainnet') {
      signer = new HardwareSigner(ethers.provider, null, "m/44'/60'/0'/0/0");
    }
    const address = await signer.getAddress();
    console.log(`Deploying with ${address}, balance ${BN(await ethers.provider.getBalance(address)).div(ONE_TOKEN(18))} ETH`);
    console.log();
    return signer;
  },
  deployContract: async (contractName, params, signer) => {
    console.log(`Deploying ${contractName}`);
    const contractFactory = await ethers.getContractFactory(contractName, signer);
    let contract = await contractFactory.deploy(...params);
    await contract.deployed();
    let contractReceipt = await contract.deployTransaction.wait()
    console.log(`${contractName} created: ${contract.address} @tx: ${contractReceipt.transactionHash}`);
    console.log();
    return contract;
  },
  deployUpgradableContract: async (contractName, params, signer) => {
    console.log(`Deploying ${contractName}`);
    const contractFactory = await ethers.getContractFactory(contractName, signer);
    // do not use spread (...) operator here
    let contract = await hre.upgrades.deployProxy(contractFactory, params);
    await contract.deployed();
    let contractReceipt = await contract.deployTransaction.wait()
    console.log(`${contractName} created (proxy): ${contract.address} @tx: ${contractReceipt.transactionHash}`);
    console.log();
    return contract;
  },
  upgradeContract: async (address, contractName, params, signer) => {
    console.log(`Upgrading ${contractName}`);
    const contractFactory = await ethers.getContractFactory(contractName, signer);
    let contract = await hre.upgrades.upgradeProxy(address, contractFactory);
    // NOTE: Method + params cannot be passed for reinit on upgrades!
    // do not use spread (...) operator here
    // let contract = await upgrades.upgradeProxy(address, contractFactory, params);
    let contractReceipt = await contract.deployTransaction.wait()
    console.log(`${contractName} upgraded (proxy): ${contract.address} @tx: ${contractReceipt.transactionHash}`);
    console.log()
    return contract;
  },
  prompt: async question => {
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
      console.log("exiting...");
      process.exit(1);
    }
  },
  check: (a, b, message) => {
    a = a.toString();
    b = b.toString();
    let [icon, symbol] = a.toString() === b ? ["✔️", "==="] : ["🚨🚨🚨", "!=="];
    console.log(`${icon}  `, a, symbol, b, message ? message : "");
  },
  checkAproximate: (a, b, message) => { // check a is withing 5% of b
    a = BigNumber.from(a.toString())
    b = BigNumber.from(b.toString())

    let _check
    if (b.eq(BigNumber.from('0'))) {
        _check = a.eq(b)
    } else {
        _check = b.mul("95").lte(a.mul("100")) && a.mul("100").lte(b.mul("105"))
    }

    let [icon, symbol] = _check ? ["✔️", "~="] : ["🚨🚨🚨", "!~="];
    console.log(`${icon}  `, a.toString(), symbol, b.toString(), message ? message : "");
  },
  checkIncreased: (a, b, message) => {
    let [icon, symbol] = b.gt(a) ? ["✔️", "<"] : ["🚨🚨🚨", ">="];
    console.log(`${icon}  `, a.toString(), symbol, b.toString(), message ? message : "");
  },
  toETH: n => ethers.utils.parseEther(n.toString()),
  sudo: async (acc, contract = null, hardh) => {
    await hardh.network.provider.request({method: "hardhat_impersonateAccount", params: [acc]});
    const signer = await ethers.provider.getSigner(acc);
    if (contract) {
      contract = await contract.connect(signer);
    }
    return [contract, signer];
  },
  waitDays: async d => {
    await time.increase(time.duration.days(d));
  },
  resetFork: async (blockNumber, hardh) => {
    console.log('resetting fork')
    await hardh.network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
            blockNumber,
          }
        }
      ]
    });
  }
}
