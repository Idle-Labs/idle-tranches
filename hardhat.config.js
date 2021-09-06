require('dotenv').config();
require('chai').should();
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-solhint");
// require('hardhat-abi-exporter');
// require('hardhat-contract-sizer');
require("hardhat-etherscan-abi");
require("solidity-coverage");

// Tasks
require("./tasks/helpers");
require("./tasks/tests");
require("./tasks/deploy");
require("./tasks/test-harvest");
require("./tasks/cdo-factory");

const BN = require("bignumber.js");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 25
          }
        }
      }
    ],
    overrides: {
      "contracts/IdleCDOTrancheRewards.sol": {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999
          }
        }
      },
      "contracts/IdleCDOTranche.sol": {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999
          }
        }
      },
      "contracts/IdleStrategy.sol": {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999
          }
        }
      }
    }
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      // forking: {
      //   url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      //   // blockNumber: 12554260, // DAI all in compound for `integration` task
      //   // blockNumber: 13055073 // both tranches have deposits and both staking contracts have staked tranches
      //   blockNumber: 13086034 // no stkAAVE in the contract (for test-harvest task)
      //   blockNumber: 13126332 // there are stkAAVE in the contract in cooldown
      // }
    },
    coverage: {
      url: "http://127.0.0.1:8545/",
      blockGasLimit: 15000000,
      allowUnlimitedContractSize: true,
    },
    local: {
      url: "http://127.0.0.1:8545/",
      timeout: 120000,
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      gasPrice: 'auto',
      gas: 'auto',
      gasMultiplier: 1.2,
      timeout: 1200000
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  abiExporter: {
    // path: './abis',
    // clear: true,
    flat: true,
    spacing: 2
  },
  contractSizer: {
    // alphaSort: true,
    // runOnCompile: true,
    // disambiguatePaths: false,
  }
};
