require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('@openzeppelin/hardhat-upgrades');
require('chai').should();
require('dotenv').config();
require("./tasks/hardhat.helpers");
const BN = require("bignumber.js");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000
          }
        }
      }
    ],
  },
  networks: {
    hardhat: {
      // forking: {
      //   url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      //   // blockNumber: 12310055,
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
      url: `https://kovan.infura.io/v3/${process.env.IDLE_INFURA_KEY}`,
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.IDLE_INFURA_KEY}`,
      gasPrice: 'auto',
      gas: 'auto'
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  }
};
