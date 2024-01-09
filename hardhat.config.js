require("@nomicfoundation/hardhat-foundry");
require('dotenv').config();
require('chai').should();
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-solhint");
// require('hardhat-abi-exporter');
// require('hardhat-contract-sizer');
require("hardhat-etherscan-abi");
// require('hardhat-docgen');
require("solidity-coverage");

// Tasks
require("./tasks/cdo-factory");
require("./tasks/chain-utils");
require("./tasks/tranches-utils");
require("./tasks/deploy-by");

const BN = require("bignumber.js");
const mainContactRuns = 170;
const overrideConfig = {
  version: "0.8.10",
  settings: {
    optimizer: {
      enabled: true,
      runs: mainContactRuns
    }
  }
};
const minimalSizeConfig = {
  version: "0.8.10",
  settings: {
    optimizer: {
      enabled: true,
      runs: 50
    }
  }
};
const highRunConfig = {
  version: "0.8.10",
  settings: {
    optimizer: {
      enabled: true,
      runs: 10000
    }
  }
};

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999
          }
        }
      }
    ],
    overrides: {
      "contracts/IdleCDO.sol": overrideConfig,
      "contracts/IdleCDOInstadappLiteVariant.sol": overrideConfig,
      "contracts/IdleCDOAmpohorVariant.sol": overrideConfig,
      "contracts/polygon-zk/IdleCDOPolygonZK.sol": overrideConfig,
      "contracts/optimism/IdleCDOOptimism.sol": overrideConfig,
      "contracts/IdleCDOTruefiVariant.sol": minimalSizeConfig,
      "contracts/IdleCDOLeveregedEulerVariant.sol": minimalSizeConfig,
      "contracts/IdleCDOPoLidoVariant.sol": minimalSizeConfig,
      "contracts/strategies/euler/IdleLeveragedEulerStrategy.sol": highRunConfig,
      "contracts/polygon/IdleCDOPolygon.sol": overrideConfig,
      "contracts/utils/IdleBuddyCompAavePYT.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 8000
          }
        }
      },
    }
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      // forking: {
      //   // url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      //   // url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      //   // url:`https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      //   // url: `https://polygonzkevm-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_ZK_KEY}`,
      //   url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_OPTIMISM_KEY}`,
      //   // blockNumber: 12554260, // DAI all in compound for `integration` task
      //   // blockNumber: 13055073 // both tranches have deposits and both staking contracts have staked tranches
      //   // blockNumber: 13086034 // no stkAAVE in the contract (for test-harvest task)
      //   // blockNumber: 13126332 // there are stkAAVE in the contract in cooldown
      //   // blockNumber: 13261760 // pre transfer ownership
      //   // blockNumber: 13666020 // convex/lido integration tests
      //   // blockNumber: 13728440 // idleFEI upgraded
      //   // blockNumber: 13739407 // idleDAI upgraded
      //   // blockNumber: 13776718 // lido deploy
      //   // blockNumber: 13810230 // convex deploy
      //   // blockNumber: 14075568 // StakingRewards deploy
      //   // blockNumber: 14164982 // upgrade convex strategy
      //   // blockNumber: 14184625 //  deploy tranche battle winners + mstable completed
      //   // blockNumber: 14204103 //  deploy tranche battle winners + mstable completed
      //   // blockNumber: 14217710 //  upgrade mstable tranche
      //   // blockNumber: 14141000 // harvest strategy
      //   // blockNumber: 14705834 // euler strategy
      //   // blockNumber: 14748963 // pbtc test
      //   // blockNumber: 14931960 // euler strategy update
      //   // blockNumber: 14956557 // eulerdai eulerusdt with AYS
      //   // blockNumber: 28479157 // polygon
      //   // blockNumber: 15133116, // clearpool strategy
      //   // blockNumber: 15435009, // euler lev usdc strategy
      //   // blockNumber: 15576018, // euler lev usdc strat upgrade
      //   // blockNumber: 15617063, // stMatic strategy
      //   // blockNumber: 15718298, // cpfol dai strategy
      //   // blockNumber: 15831007, // ribbon strategies
      //   // blockNumber: 15889000, // by on juniors deploy
      //   // blockNumber: 15890900, // by on juniors initialize
      //   // blockNumber: 15924713, // cpfolusd + rwinusd deploy
      //   // blockNumber: 16246541, // eUSDCStaking PYT deploy
      //   // blockNumber: 16375540, // eUSDTStaking + eWETHStaking PYT deploy
      //   // blockNumber: 16419858, // Morpho maUSDC
      //   // blockNumber: 16976228, // Euler staking DAI
      //   // optimism
      //   blockNumber: 110447750, // cpporusdc
      //   // polygonzk
      //   // blockNumber: 2724050, // cpfasusdt
      // },
      // chainId: 1101 // polygonzk
      // chainId: 137 // polygon
      // chainId: 10 // optimism
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
      gasMultiplier: 1.1,
      timeout: 1200000
    },
    matic: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      gasPrice: 'auto',
      gas: 'auto',
      timeout: 1200000,
      chainId: 137
    },
    polygonzk: {
      url: `https://zkevm-rpc.com`,
      // url: `https://polygon-zkevm.blockpi.network/v1/rpc/public`
      // url: `https://polygonzkevm-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_ZK_KEY}`,
      gasPrice: 'auto',
      gas: 'auto',
      gasMultiplier: 1.1,
      timeout: 1200000,
      chainId: 1101
    },
    optimism: {
      url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_OPTIMISM_KEY}`,
      gasPrice: 'auto',
      gas: 'auto',
      gasMultiplier: 1.1,
      timeout: 1200000,
      chainId: 10
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY,
      polygon: process.env.POLYGON_ETHERSCAN_API_KEY,
      polygonzk: process.env.POLYGON_ZK_ETHERSCAN_API_KEY,
      optimisticEthereum: process.env.OPTIMISM_ETHERSCAN_API_KEY
    },
    customChains: [
      {
        network: "polygonzk",
        chainId: 1101,
        urls: {
          apiURL: "https://api-zkevm.polygonscan.com/api",
          browserURL: "https://zkevm.polygonscan.com"
        }
      }
    ]
  },
  abiExporter: {
    // path: './abis',
    // clear: true,
    flat: true,
    spacing: 2
  },
  docgen: {
    path: './docs',
    clear: true,
    runOnCompile: false,
    only: [
      '^contracts/IdleCDO.sol',
    ]
  },
  contractSizer: {
    // alphaSort: true,
    // runOnCompile: true,
    // disambiguatePaths: false,
  },
  mocha: {
    timeout: 1000000
  }
};