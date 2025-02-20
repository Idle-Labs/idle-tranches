require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../utils/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const polygonContracts = addresses.IdleTokens.polygon;
const polygonZKContracts = addresses.IdleTokens.polygonZK;
const optimismContracts = addresses.IdleTokens.optimism;
const arbitrumContracts = addresses.IdleTokens.arbitrum;
const ICurveRegistryAbi = require("../abi/ICurveRegistry.json")

const getNetworkContracts = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;

  if (isMatic) {
    return polygonContracts;
  } else if (isPolygonZK) {
    return polygonZKContracts;
  } else if (isOptimism) {
    return optimismContracts;
  } else if (isArbitrum) {
    return arbitrumContracts;
  }
  return mainnetContracts;
}

const getDeployTokens = (_hre) => {
  const isMatic = _hre.network.name == 'matic' || _hre.network.config.chainId == 137;
  const isPolygonZK = _hre.network.name == 'polygonzk' || _hre.network.config.chainId == 1101;
  const isOptimism = _hre.network.name == 'optimism' || _hre.network.config.chainId == 10;
  const isArbitrum = _hre.network.name == 'arbitrum' || _hre.network.config.chainId == 42161;

  if (isMatic) {
    return addresses.deployTokensPolygon;
  } else if (isPolygonZK) {
    return addresses.deployTokensPolygonZK;
  } else if (isOptimism) {
    return addresses.deployTokensOptimism;
  } else if (isArbitrum) {
    return addresses.deployTokensArbitrum;
  }
  return addresses.deployTokens;
}

/**
 * @name info
 */
task("info", "IdleCDO info")
  .addParam("cdo")
  .setAction(async (args) => {
    console.log(args.cdo);
    let idleCDO = await ethers.getContractAt("IdleCDO", args.cdo);
    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`AATranche: ${await idleCDO.AATranche()}, BBTranche: ${await idleCDO.BBTranche()}`);
    console.log(`IdleStrategy: ${await idleCDO.strategy()}`);
  });

/**
 * @name upgrade-cdo
 */
task("upgrade-cdo", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];

    const contractAddress = deployToken.cdo.cdoAddr;
    if (!contractAddress) {
      console.log(`IdleCDO Must be deployed`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');
    let contractName = 'IdleCDO';
    if (deployToken.cdoVariant) {
      contractName = deployToken.cdoVariant;
    }
    await helpers.upgradeContract(contractAddress, contractName, signer);
    console.log(`IdleCDO upgraded`);
  });

task("gen-calldata", 'Generate bytes calldata')
  .addParam('contract')
  .addParam('address')
  .addParam('method')
  .addParam('params')
  .setAction(async (args) => {
    const contract = await ethers.getContractAt(args.contract, args.address);
    const calldata = contract.interface.encodeFunctionData(args.method, [args.params]);
    console.log('calldata:', calldata);
  });

/**
 * @name upgrade-cdo-multisig
 */
task("upgrade-cdo-multisig", "Upgrade IdleCDO instance with multisig")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;

    let contractName = isPolygonZK ? 'IdleCDOPolygonZK' : 'IdleCDO';
    if (isOptimism) {
      contractName = 'IdleCDOOptimism';
    } else if (isArbitrum) {
      contractName = 'IdleCDOArbitrum';
    }
    if (deployToken.cdoVariant) {
      contractName = deployToken.cdoVariant;
    }
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName,
      contractKey: 'cdoAddr',
      // initMethod: '_init',
      // initParams: []
    });
  });

/**
 * @name upgrade-cdo-multisig-timelock
 */
task("upgrade-cdo-multisig-timelock", "Upgrade IdleCDO instance with multisig timelock module")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    const isOptimism = hre.network.name == 'optimism' || hre.network.config.chainId == 10;
    const isArbitrum = hre.network.name == 'arbitrum' || hre.network.config.chainId == 42161;

    let contractName = isPolygonZK ? 'IdleCDOPolygonZK' : 'IdleCDO';
    if (isOptimism) {
      contractName = 'IdleCDOOptimism';
    } else if (isArbitrum) {
      contractName = 'IdleCDOArbitrum';
    }
    if (deployToken.cdoVariant) {
      contractName = deployToken.cdoVariant;
    }
    await run("upgrade-with-multisig-timelock", {
      cdoname: args.cdoname,
      contractName,
      contractKey: 'cdoAddr',
      // initMethod: '_init',
      // initParams: []
    });
  });

/**
 * @name upgrade-strategy
 */
task("upgrade-strategy", "Upgrade IdleCDO strategy")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName: deployToken.strategyName,
      contractKey: 'strategy' // check eg CDOs.idleDAI.*
    });
  });

/**
 * @name upgrade-strategy-timelock
 */
task("upgrade-strategy-timelock", "Upgrade IdleCDO strategy")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    
    await run("upgrade-with-multisig-timelock", {
      cdoname: args.cdoname,
      contractName: deployToken.strategyName,
      contractKey: 'strategy' // check eg CDOs.idleDAI.*
    });
  });

/**
 * @name transfer-ownership-cdo
 */
task("transfer-ownership-cdo", "Transfer IdleCDO ownership")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");

    // #### Change this if needed (avoid passing it via cli)
    const to = getNetworkContracts(_hre).devLeagueMultisig;
    // ####

    console.log('NEW OWNER: ', to);
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    console.log('deployToken', deployToken)
    const proxyAdminAddress = deployToken.cdo.proxyAdmin;
    const contractAddress = deployToken.cdo.cdoAddr;
    const strategyAddress = deployToken.cdo.strategy;
    if (!contractAddress || !strategyAddress || !proxyAdminAddress || !to) {
      console.log(`IdleCDOAddress, to, strategyAddress and proxyAdminAddress Must be defined`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');

    console.log('Transfer ownership of IdleCDOStrategy');
    let strategy = await ethers.getContractAt("IdleStrategy", strategyAddress);
    await strategy.connect(signer).transferOwnership(to);
    console.log('New Owner', await strategy.owner());

    console.log('Transfer ownership of IdleCDO');
    let cdo = await ethers.getContractAt("IdleCDO", contractAddress);
    await cdo.connect(signer).transferOwnership(to);
    console.log('New Owner', await cdo.owner());

    let admin = await ethers.getContractAt("IProxyAdmin", proxyAdminAddress);
    const currProxyOwner = await admin.owner();
    if (currProxyOwner != to) {
      console.log('Transfer owner of proxyAdmin for all');
      await admin.connect(signer).transferOwnership(to);
      console.log('New Owner', await admin.owner());
    }
  });

/**
 * @name pause-cdo-multisig
 */
task("pause-cdo-multisig", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    console.log('deployToken', deployToken)
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    const multisig = await run('get-multisig-or-fake');
    await cdo.connect(multisig).pause();
    console.log('Is Paused ? ', await cdo.paused());
  });

/**
 * @name emergency-shutdown-cdo-multisig
 */
task("emergency-shutdown-cdo-multisig", "Upgrade IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    console.log('deployToken', deployToken)
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    const multisig = await run('get-multisig-or-fake');
    await cdo.connect(multisig).emergencyShutdown();
    console.log('Is Paused ? ', await cdo.paused());
    console.log('Allow AA withdraw ? ', await cdo.allowAAWithdraw());
    console.log('Allow BB withdraw ? ', await cdo.allowBBWithdraw());
  });

/**
 * @name test-convex-tranche
 */
task("test-convex-harvest", "Test harvest on convex tranche")
  .addParam('cdoname')
  .setAction(async (args) => {
    const signer = await run('get-multisig-or-fake', {fakeAddress: addresses.idleDeployer});
    const deployToken = addresses.deployTokens[args.cdoname];
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    let strategy = await ethers.getContractAt(deployToken.strategyName, deployToken.cdo.strategy);
    cdo = cdo.connect(signer);
    strategy = strategy.connect(signer);

    let bal = await helpers.getTokenBalance(await cdo.strategyToken(), cdo.address);
    console.log('StrategyTokens', BN(bal).toString());

    const newSigner = await helpers.getSigner();
    await helpers.fundAndDeposit('AA', cdo, newSigner.address, ONE_TOKEN(18));
    
    await run('increase-time-mine', {time: (60 * 60 * 24 * 3).toString()});
    await harvest(cdo, {isFirst: true, paramsType: ['uint256', 'uint256'], params: [1,0]});
    console.log('Apr: ', (await strategy.getApr()).toString());
  });

/**
 * @name change-rewards
 */
task("change-rewards", "Update rewards IdleCDO instance")
  .addParam('cdoname')
  .setAction(async (args) => {
    const multisig = await run('get-multisig-or-fake');

    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];

    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    cdo = cdo.connect(multisig);

    console.log('AA ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.AATranche)).toString());
    console.log('BB ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.BBTranche)).toString());

    // Only Senior (AA) tranches will get IDLE rewards
    await cdo.setStakingRewards(deployToken.cdo.AArewards, addresses.addr0);
    console.log('AA staking ', await cdo.AAStaking());
    console.log('BB staking ', await cdo.BBStaking());

    // Split interest received 10/90 (10% to AA)
    await cdo.setTrancheAPRSplitRatio(BN('10000'))
    console.log('APR split ratio ', (await cdo.trancheAPRSplitRatio()).toString());

    console.log('AA ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.AATranche)).toString());
    console.log('BB ideal apr', BN(await cdo.getIdealApr(deployToken.cdo.BBTranche)).toString());
  });

/**
 * @name find-convex-params
 * find params for a convex strategy (convexPoolId, depositPosition)
 */
task("find-convex-params", "Find depositPosition for depositToken of a convex pool of the given lpToken")
  .addParam('lpToken')
  .addParam('depositToken')
  .setAction(async (args) => {
    const lpToken = args.lpToken;
    const depositToken = args.depositToken;

    const crvReg = await hre.ethers.getContractAt(ICurveRegistryAbi, '0x90e00ace148ca3b23ac1bc8c240c2a7dd9c2d7f5');
    const poolAddr = await crvReg.get_pool_from_lp_token(lpToken);
    const poolName = await crvReg.get_pool_name(poolAddr);
    let coins = await crvReg.get_coins(poolAddr);
    let uCoins = await crvReg.get_underlying_coins(poolAddr);

    const curveWETHAddr = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
    // if a coin is equal to curveWETHAddr then replace the value with the real WETH address
    coins = coins.map(coin => (coin == curveWETHAddr ? mainnetContracts.WETH : coin).toLowerCase());
    uCoins = uCoins.map(coin => (coin == curveWETHAddr ? mainnetContracts.WETH : coin).toLowerCase());

    console.log({ poolName, poolAddr, lpToken, depositToken, coins, uCoins });

    const position = coins.indexOf(depositToken);
    const uPosition = uCoins.indexOf(depositToken);
    
    if (position >= 0) {
      console.log('deposit position: ', position);
    } else if (uPosition >= 0) {
      console.log('deposit position (underlying): ', uPosition);
    } else {
      console.log('deposit token not found in pool');
    }
  });

/**
* @name base58
*/
task("fetch-morpho-rewards-old")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    if (!deployToken.urds.length) {
      console.log("🛑 No URDs defined");
      return;
    }
    console.log('cdoAddr:', cdoAddr);
    console.log('urds:', deployToken.urds);

    for (let i = 0; i < deployToken.urds.length; i++) {
      const urd = deployToken.urds[i];
      console.log('urd:', urd);
      const urdContract = await ethers.getContractAt("IUniversalRewardsDistributor", urd);
      const ipfsHash = await urdContract.ipfsHash();
      // converts hash to base58
      const hash_base58 = ethers.utils.base58.encode(
        // 0x12 is the hash method (sha256), and 0x20 is the data size (32)
        Buffer.from("1220" + ipfsHash.slice(2), "hex")
      );
      const link = `https://dweb.link/ipfs/${hash_base58}`;
      console.log("Ipfs link:", link);
      // fetch json from link
      const response = await fetch(link);
      const json = await response.json();
      // find user reward
      const userRewards = json.rewards[cdoAddr];
      console.log('CDO rewards:', userRewards);
      console.log('---');
    }
  });

task("collect-morpho-rewards")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    console.log('cdoAddr:', cdoAddr);
    const cdoContract = await ethers.getContractAt("IdleCDO", cdoAddr);
    const strategyAddr = await cdoContract.strategy();
    const strategyContract = await ethers.getContractAt("MetaMorphoStrategy", strategyAddr);
    const currentRewards = await strategyContract.getRewardTokens();
    console.log('current rewards: ');
    for (let r = 0; r < currentRewards.length; r++) {
      const reward = currentRewards[r];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward} (${rewardSymbol})`);
    }
    console.log('-----------------');

    // fetch last distributions
    const response = await fetch(`https://rewards.morpho.org/v1/users/${cdoAddr}/distributions`);
    const json = await response.json();

    console.log('reward pages:', json.pagination.total_pages);
    if (json.pagination.totalPages > 1) {
      console.log('WARN: this script supports only 1 page of rewards and there are more!');
    }
    const rewards = json.data;
    const txs = [];
    for (let i = 0; i < rewards.length; i++) {
      const reward = rewards[i];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward.asset.address);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward.asset.address} (${rewardSymbol})`);
      console.log('distributor', reward.distributor.address);
      console.log('amount', reward.claimable);
      // console.log('proof', reward.proof);
      // console.log('txData', reward.tx_data);

      txs.push({
        to: reward.distributor.address,
        value: '0',
        data: reward.tx_data
      })
    }

    if (txs.length == 0) {
      return;
    }
    const signer = await run('get-signer-or-fake');
    await helpers.batchTxsEOA(txs.map(tx => ({ target: tx.to, callData: tx.data })), signer);

    // // do the same with multisig
    // const networkContracts = getNetworkContracts(hre);
    // await helpers.proposeBatchTxsMainnet(networkContracts.devLeagueMultisig, txs);
  });

task("collect-usual-rewards")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    const cdoContract = await ethers.getContractAt("IdleCDOUsualVariant", cdoAddr);
    const strategyAddr = await cdoContract.strategy();
    const strategyContract = await ethers.getContractAt("IdleUsualStrategy", strategyAddr);
    const currentRewards = await strategyContract.getRewardTokens();
    console.log('strategy:', strategyAddr);
    console.log('cdoAddr :', cdoAddr);
    console.log('current rewards: ');
    for (let r = 0; r < currentRewards.length; r++) {
      const reward = currentRewards[r];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward} (${rewardSymbol})`);
    }
    console.log('-----------------');

    const usualDistributor = await ethers.getContractAt("IUsualDistributor", '0x75cc0c0ddd2ccafe6ec415be686267588011e36a');
    const offChainDistrData = await usualDistributor.getOffChainDistributionData();
    const latestRoot = offChainDistrData.merkleRoot;
    console.log('latestRoot ', latestRoot);

    // fetch last distributions
    const response = await fetch(`https://app.usual.money/api/rewards/${strategyAddr}`);
    const rewards = await response.json();
    const claimed = await usualDistributor.getOffChainTokensClaimed(strategyAddr);
    const responseCDO = await fetch(`https://app.usual.money/api/rewards/${cdoAddr}`);
    const rewardsCDO = await responseCDO.json();
    const claimedCDO = await usualDistributor.getOffChainTokensClaimed(cdoAddr);

    const txs = [];
    // If first element root is equal to the latestRoot then we can claim
    // process strategy rewards
    if (rewards.length > 0 && rewards[0].merkleRoot == latestRoot) {
      const reward = rewards[0];
      console.log('amount Strategy', reward.value);
      console.log('receiver Strategy', strategyAddr);
      if (BN(claimed).eq(BN(reward.value))) {
        console.log('Already claimed strategy');
      } else {
        // console.log('proof', reward.merkleProof);
        const data = usualDistributor.interface.encodeFunctionData(
          'claimOffChainDistribution',
          [strategyAddr, reward.value, reward.merkleProof]
        );
        // console.log('data', data);
        txs.push({to: usualDistributor.address, value: '0', data});
      }
    } else {
      console.log('Nothing to claim for strategy');
    }

    // process cdo rewards
    if (rewardsCDO.length > 0 && rewardsCDO[0].merkleRoot == latestRoot) {
      const reward = rewardsCDO[0];
      console.log('amount CDO', reward.value);
      console.log('receiver CDO', cdoAddr);
      // console.log('proof', reward.merkleProof);
      if (BN(claimedCDO).eq(BN(reward.value))) {
        console.log('Already claimed CDO');
      } else {
        const data = usualDistributor.interface.encodeFunctionData(
          'claimOffChainDistribution',
          [cdoAddr, reward.value, reward.merkleProof]
        );
        // console.log('data', data);
        txs.push({to: usualDistributor.address, value: '0', data});
      }
    } else {
      console.log('Nothing to claim for CDO');
    }

    if (txs.length == 0) {
      console.log('No transactions to process.');
      return;
    }
    const signer = await run('get-signer-or-fake');
    await helpers.batchTxsEOA(txs.map(tx => ({ target: tx.to, callData: tx.data })), signer);
  });

task("fetch-morpho-rewards")
  .addParam('cdoname')
  .setAction(async function (args) {
    if (!args.cdoname) {
      console.log("🛑 cdoname and it's params must be defined");
      return;
    }
    // Get config params
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const cdoAddr = deployToken.cdo.cdoAddr;
    console.log('cdoAddr:', cdoAddr);
    const cdoContract = await ethers.getContractAt("IdleCDO", cdoAddr);
    const strategyAddr = await cdoContract.strategy();
    const strategyContract = await ethers.getContractAt("MetaMorphoStrategy", strategyAddr);
    const currentRewards = await strategyContract.getRewardTokens();
    console.log('current rewards: ');
    for (let r = 0; r < currentRewards.length; r++) {
      const reward = currentRewards[r];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward} (${rewardSymbol})`);
    }
    console.log('-----------------');

    // fetch last distributions
    const response = await fetch(`https://rewards.morpho.org/v1/users/${cdoAddr}/distributions`);
    const json = await response.json();

    console.log('reward pages:', json.pagination.total_pages);
    if (json.pagination.totalPages > 1) {
      console.log('WARN: this script supports only 1 page of rewards and there are more!');
    }
    const rewards = json.data;
    for (let i = 0; i < rewards.length; i++) {
      const reward = rewards[i];
      const rewardContract = await ethers.getContractAt("IERC20Detailed", reward.asset.address);
      const rewardSymbol = await rewardContract.symbol();
      console.log(`reward ${reward.asset.address} (${rewardSymbol})`);
      console.log('distributor', reward.distributor.address);
      console.log('amount', reward.claimable);
      console.log('proof', reward.proof);
    }
  });

/**
 * @name upgrade-with-multisig
 */
subtask("upgrade-with-multisig", "Upgrade contract with multisig")
  .addParam('cdoname')
  .addParam('contractName')
  .addParam('contractKey')
  .addOptionalParam('initMethod')
  .addOptionalParam('initParams')
  .setAction(async (args) => {
    await run("compile");
    const networkTokens = getDeployTokens(hre);
    const deployToken = networkTokens[args.cdoname];
    const contractName = args.contractName;

    const contractAddress = deployToken.cdo[args.contractKey];
    console.log(`To upgrade: ${contractName} @ ${contractAddress}`)
    console.log('deployToken', deployToken)

    if (!contractAddress || !contractName) {
      console.log(`contractAddress and contractName must be defined`);
      return;
    }

    await helpers.prompt("continue? [y/n]", true);
    let signer = await run('get-signer-or-fake');
    // deploy implementation with any signer
    let newImpl = await helpers.prepareContractUpgrade(contractAddress, contractName, signer);
    // to checksum address
    newImpl = ethers.utils.getAddress(newImpl);
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    if (isPolygonZK) {
      console.log('PolygonZK: continue with multisig UI');
      return;
    }
  
    signer = await run('get-multisig-or-fake');
    // Use multisig for calling upgrade or upgradeAndCall
    const proxyAdminAddress = deployToken.cdo.proxyAdmin;
    if (!newImpl || !proxyAdminAddress) {
      console.log(`New impl or proxyAdmin address are null`);
      return;
    }

    let admin = await ethers.getContractAt("IProxyAdmin", proxyAdminAddress);
    admin = admin.connect(signer);

    if (args.initMethod) {
      let contract = await ethers.getContractAt(contractName, contractAddress);
      const initMethodCall = contract.interface.encodeFunctionData(args.initMethod, args.initParams || []);
      await admin.upgradeAndCall(contractAddress, newImpl, initMethodCall);
    } else {
      await admin.upgrade(contractAddress, newImpl);
    }

    console.log(`${args.contractKey} (contract: ${contractName}) Upgraded, new impl ${newImpl}`);
  });

/**
 * @name upgrade-with-multisig-timelock
 */
subtask("upgrade-with-multisig-timelock", "Upgrade contract with multisig timelock module")
  .addParam('cdoname')
  .addParam('contractName')
  .addParam('contractKey')
  .addOptionalParam('initMethod')
  .addOptionalParam('initParams')
  .setAction(async (args) => {
    await run("compile");
    const networkTokens = getDeployTokens(hre);
    const networkContracts = getNetworkContracts(hre);
    const deployToken = networkTokens[args.cdoname];
    const contractName = args.contractName;

    const contractAddress = deployToken.cdo[args.contractKey];
    console.log(`To upgrade: ${contractName} @ ${contractAddress}`)
    console.log('deployToken', deployToken)

    if (!contractAddress || !contractName) {
      console.log(`contractAddress and contractName must be defined`);
      return;
    }

    await helpers.prompt("continue? [y/n]", true);
    let signer = await run('get-signer-or-fake');
    // deploy implementation with any signer
    let newImpl = await helpers.prepareContractUpgrade(contractAddress, contractName, signer);
    // to checksum address
    newImpl = ethers.utils.getAddress(newImpl);
    const isPolygonZK = hre.network.name == 'polygonzk' || hre.network.config.chainId == 1101;
    if (isPolygonZK) {
      console.log('PolygonZK: continue with multisig UI');
      return;
    }

    signer = await run('get-multisig-or-fake');

    // we need to get the timelock and proxyWithTimelock address or exit
    if (!networkContracts.timelock || !networkContracts.proxyAdminWithTimelock) {
      console.log('timelock or proxyAdminWithTimelock not defined');
      return;
    }
    
    let timelock = await ethers.getContractAt("Timelock", networkContracts.timelock);
    timelock = timelock.connect(signer);
    console.log('Timelock: ', timelock.address);

    let proxyAdminWithTimelock = await ethers.getContractAt("IProxyAdmin", deployToken.cdo.proxyAdmin);
    proxyAdminWithTimelock = proxyAdminWithTimelock.connect(signer);
    console.log('ProxyAdmin with timelock: ', proxyAdminWithTimelock.address);
    
    if (!newImpl) {
      console.log(`New impl address is null`);
      return;
    }

    console.log(`Upgrading ${contractName} (addr: ${contractAddress}) with new impl ${newImpl}`);
    const bytes0 = ethers.constants.HashZero;

    if (args.initMethod) {
      let contract = await ethers.getContractAt(contractName, contractAddress);
      const initMethodCall = contract.interface.encodeFunctionData(args.initMethod, args.initParams || []);

      await timelock.schedule(
        proxyAdminWithTimelock.address, // to
        0, // value
        proxyAdminWithTimelock.interface.encodeFunctionData(
          'upgradeAndCall', [contractAddress, newImpl, initMethodCall]
        ), // data
        bytes0, // predecessor (the id of a prev scehduled operation if dependent)
        bytes0, // salt
        await timelock.getMinDelay() // delay
      );
    } else {
      await timelock.schedule(
        proxyAdminWithTimelock.address,
        0,
        proxyAdminWithTimelock.interface.encodeFunctionData(
          'upgrade', [contractAddress, newImpl]
        ),
        bytes0,
        bytes0,
        await timelock.getMinDelay()
      );
    }

    console.log(`${args.contractKey} (contract: ${contractName}) Upgrade queued, new impl ${newImpl}`);
  });

/**
 * @name get-signer-or-fake
 */
subtask("get-signer-or-fake", "Get signer")
  .setAction(async (args) => {
    let signer;
    if (hre.network.name !== 'mainnet' && hre.network.name !== 'matic' && hre.network.name !== 'polygonzk' && hre.network.name !== 'optimism' && hre.network.name !== 'arbitrum') {
      signer = await helpers.impersonateSigner(args.fakeAddress || addresses.idleDeployer);
    } else {
      signer = await helpers.getSigner();
    }
    console.log('Using signer with address: ', await signer.getAddress());
    return signer;
  });

/**
 * @name get-multisig-or-fake
 */
subtask("get-multisig-or-fake", "Get multisig signer")
  .setAction(async (args) => {
    let signer;
    const networkContracts = getNetworkContracts(hre);
    if (hre.network.name !== 'mainnet' && hre.network.name !== 'matic' && hre.network.name !== 'polygonzk' && hre.network.name !== 'optimism' && hre.network.name !== 'arbitrum') {
      signer = await helpers.impersonateSigner(args.fakeAddress || networkContracts.treasuryMultisig);
    } else {
      signer = await helpers.getMultisigSigner();
    }
    console.log('Using signer with address: ', await signer.getAddress());
    return signer;
  });

const harvest = async (cdo, { isFirst, params, paramsType, static, flags } = {isFirst: false, params: [], paramsType: [], static: false, flags: []}) => {
  // encode params for redeemRewards: uint256[], bool[], uint256, uint256
  if (!params || !params.length) {
    params = [
      [1, 1],
      [false, false],
      1,
      1
    ];
    paramsType = ['uint256[]', 'bool[]', 'uint256', 'uint256'];
  }
  const extraData = helpers.encodeParams(paramsType, params);

  if (static) {
    return await helpers.sudoStaticCall(mainnetContracts.rebalancer, cdo, 'harvest', [
      flags.length ? flags : [isFirst, isFirst, isFirst, isFirst], 
      [], [], [],
      extraData
    ]);
  }

  const res = await helpers.sudoCall(mainnetContracts.rebalancer, cdo, 'harvest', [
    flags.length ? flags : [isFirst, isFirst, isFirst, isFirst], 
    [], [], [],
    extraData
  ]);
  
  console.log('Harvest Gas: ', res[2].cumulativeGasUsed.toString());
};

const waitBlocks = async (n) => {
  console.log(`mining ${n} blocks...`);
  for (var i = 0; i < n; i++) {
    await ethers.provider.send("evm_mine");
  };
}
