require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../scripts/helpers");
const addresses = require("../lib/addresses");

const BN = n => BigNumber.from(n);
const ONE_TOKEN = decimals => BigNumber.from('10').pow(BigNumber.from(decimals));
const mainnetContracts = addresses.IdleTokens.mainnet;
const ICurveRegistryAbi = require("../abi/ICurveRegistry.json");

/**
 * @name deploy
 * eg `npx hardhat deploy --cdoname idledai`
 */
task("deploy", "Deploy IdleCDO, IdleStrategy and Staking contract for rewards with default parameters")
  .addParam('cdoname')
  .setAction(async (args) => {
    // Run 'compile' task
    await run("compile");
    const deployToken = addresses.deployTokens[args.cdoname];

    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();

    if (deployToken.cdo && deployToken.cdo.cdoAddr && hre.network == 'mainnet') {
      console.log(`CDO Already deployed here ${deployToken.cdo.cdoAddr}`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);

    const incentiveTokens = [mainnetContracts.IDLE];
    const strategy = await helpers.deployUpgradableContract('IdleStrategy', [deployToken.strategyParams[0], creator], signer);
    const idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('500000').mul(ONE_TOKEN(deployToken.decimals)), // limit
        deployToken.underlying,
        mainnetContracts.treasuryMultisig, // recovery address
        creator, // guardian
        mainnetContracts.rebalancer,
        strategy.address,
        BN('10000'), // apr split: 10% interest to AA and 90% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens
      ],
      signer
    );
    await strategy.connect(signer).setWhitelistedCDO(idleCDO.address);
    const AAaddr = await idleCDO.AATranche();
    const BBaddr = await idleCDO.BBTranche();
    console.log(`AATranche: ${AAaddr}, BBTranche: ${BBaddr}`);

    const stakingCoolingPeriod = BN(1500);
    const stakingRewardsParams = [
      incentiveTokens,
      creator, // owner / guardian
      idleCDO.address,
      mainnetContracts.devLeagueMultisig, // recovery address
      stakingCoolingPeriod
    ];
    const stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AAaddr, ...stakingRewardsParams], signer
    );

    // Uncomment if staking rewards contract is present for junior holders too
    //
    // const stakingRewardsBB = await helpers.deployUpgradableContract(
    //   'IdleCDOTrancheRewards', [BBaddr, ...stakingRewardsParams], signer
    // );
    // await idleCDO.connect(signer).setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);

    await idleCDO.connect(signer).setStakingRewards(stakingRewardsAA.address, addresses.addr0);

    console.log(`stakingRewardsAA: ${await idleCDO.AAStaking()}, stakingRewardsBB: ${await idleCDO.BBStaking()}`);
    console.log(`staking reward contract set`);
    console.log();
    return {idleCDO, strategy, AAaddr, BBaddr};
  });

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
    const deployToken = addresses.deployTokens[args.cdoname];

    const contractAddress = deployToken.cdo.cdoAddr;
    if (!contractAddress) {
      console.log(`IdleCDO Must be deployed`);
      return;
    }
    await helpers.prompt("continue? [y/n]", true);
    const signer = await run('get-signer-or-fake');
    await helpers.upgradeContract(contractAddress, 'IdleCDO', signer);
    console.log(`IdleCDO upgraded`);
  });

/**
 * @name upgrade-cdo-multisig
 */
task("upgrade-cdo-multisig", "Upgrade IdleCDO instance with multisig")
  .addParam('cdoname')
  .setAction(async (args) => {
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName: 'IdleCDO',
      contractKey: 'cdoAddr',
      // initMethod: '_init',
      // initParams: []
    });
  });

/**
 * @name upgrade-rewards
 */
task("upgrade-rewards", "Upgrade IdleCDOTrancheRewards contract")
  .addParam('cdoname')
  .setAction(async (args) => {
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName: 'IdleCDOTrancheRewards',
      contractKey: 'AArewards'
    });
    await run("upgrade-with-multisig", {
      cdoname: args.cdoname,
      contractName: 'IdleCDOTrancheRewards',
      contractKey: 'BBrewards'
    });
  });

/**
 * @name upgrade-strategy
 */
task("upgrade-strategy", "Upgrade IdleCDO strategy")
  .addParam('cdoname')
  .setAction(async (args) => {
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const deployToken = (
      isMatic ?
        addresses.deployTokensPolygon :
        addresses.deployTokens
    )[args.cdoname];
    
    await run("upgrade-with-multisig", {
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
    const to = addresses.IdleTokens.mainnet.devLeagueMultisig;
    // ####

    console.log('NEW OWNER: ', to);
    const deployToken = addresses.deployTokens[args.cdoname];
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

    const AARewardsAddress = deployToken.cdo.AArewards;
    if (AARewardsAddress && AARewardsAddress !== addresses.addr0) {
      console.log('Transfer ownership of AARewards');
      let AARewards = await ethers.getContractAt("IdleCDOTrancheRewards", AARewardsAddress);
      await AARewards.connect(signer).transferOwnership(to);
      console.log('New Owner', await AARewards.owner());
    }

    const BBRewardsAddress = deployToken.cdo.BBrewards;
    if (BBRewardsAddress && BBRewardsAddress !== addresses.addr0) {
      console.log('Transfer ownership of BBRewards');
      let BBRewards = await ethers.getContractAt("IdleCDOTrancheRewards", BBRewardsAddress);
      await BBRewards.connect(signer).transferOwnership(to);
      console.log('New Owner', await BBRewards.owner());
    }

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
    const deployToken = addresses.deployTokens[args.cdoname];
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
    const deployToken = addresses.deployTokens[args.cdoname];
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

    const deployToken = addresses.deployTokens[args.cdoname];

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
 * @name deploy-reward-contract
 */
task("deploy-reward-contract", "Deploy a new StakingRewards contract instanct for senior tranches of an IdleCDO instance")
  .addParam('cdoname')
  .addParam('reward')
  .addOptionalParam('shouldTransfer')
  .setAction(async (args) => {
    const deployToken = addresses.deployTokens[args.cdoname];
    let cdo = await ethers.getContractAt("IdleCDO", deployToken.cdo.cdoAddr);
    const signer = await helpers.getSigner();
    const creator = await signer.getAddress();
    
    if (!deployToken.cdo.cdoAddr || !args.reward || !mainnetContracts.treasuryMultisig || !mainnetContracts.devLeagueMultisig) {
      console.log('Missing params');
      return;
    }

    const shouldTransfer = !!args.shouldTransfer;
    console.log('Should transfer rewards from reward distributor: ', shouldTransfer);

    const initParams = [
      // address _rewardsDistribution,
      // deployToken.cdo.cdoAddr,
      mainnetContracts.treasuryMultisig,
      // address _rewardsToken,
      args.reward,
      // address _stakingToken
      await cdo.AATranche(),
      // address owner
      mainnetContracts.devLeagueMultisig,
      // _shouldTransfer
      shouldTransfer
    ];

    let stakingRewardsInstance = mainnetContracts.snxStakingRewards;
    if (!stakingRewardsInstance) {
      let stakingRewards = await helpers.deployContract('StakingRewards', [], signer);
      await stakingRewards.connect(signer).initialize(...initParams);
      console.log('StakingRewards deployed and initialized at', stakingRewards.address);
      stakingRewardsInstance = stakingRewards.addresses;
      return;
    }

    const proxyFactory = await ethers.getContractAt("MinimalInitializableProxyFactory", mainnetContracts.minimalInitializableProxyFactory);
    let res = await proxyFactory.connect(signer).create(stakingRewardsInstance);
    res = await res.wait();
    const newCloneAddr = res.events[0].args.proxy;
    console.log('Staking rewards clone deployed at: ', newCloneAddr);

    const newClone = await ethers.getContractAt("StakingRewards", newCloneAddr);
    await newClone.connect(signer).initialize(...initParams);
    console.log('Staking rewards clone owner: ', await newClone.owner());

    if ((await newClone.owner()).toLowerCase() != mainnetContracts.devLeagueMultisig.toLowerCase()) {
      console.error('Something is wrong with the new clone, owner is wrong');
      return;
    }
    
    if (shouldTransfer) {
      console.log('Setting staking rewards on IdleCDO contract');
      // Upgrade reward contract with multisig
      const multisig = await run('get-multisig-or-fake');
      cdo = cdo.connect(multisig);
      // Only Senior (AA) tranches will get rewards
      await cdo.setStakingRewards(newCloneAddr, addresses.addr0);
      console.log('AA staking ', await cdo.AAStaking());
      console.log('BB staking ', await cdo.BBStaking());
    }
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
 * @name upgrade-with-multisig
 */
subtask("upgrade-with-multisig", "Get signer")
  .addParam('cdoname')
  .addParam('contractName')
  .addParam('contractKey')
  .addOptionalParam('initMethod')
  .addOptionalParam('initParams')
  .setAction(async (args) => {
    await run("compile");
    const isMatic = hre.network.name == 'matic' || hre.network.config.chainId == 137;
    const deployToken = (
      isMatic ?
        addresses.deployTokensPolygon :
        addresses.deployTokens
    )[args.cdoname];
    const contractName = args.contractName;

    console.log('To upgrade: ', contractName)
    console.log('deployToken', deployToken)

    const contractAddress = deployToken.cdo[args.contractKey];

    if (!contractAddress || !contractName) {
      console.log(`contractAddress and contractName must be defined`);
      return;
    }

    await helpers.prompt("continue? [y/n]", true);
    let signer = await run('get-signer-or-fake');
    // deploy implementation with any signer
    const newImpl = await helpers.prepareContractUpgrade(contractAddress, contractName, signer);
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
 * @name get-signer-or-fake
 */
subtask("get-signer-or-fake", "Get signer")
  .setAction(async (args) => {
    let signer;
    if (hre.network.name !== 'mainnet' && hre.network.name !== 'matic') {
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
    if (hre.network.name !== 'mainnet' && hre.network.name !== 'matic') {
      signer = await helpers.impersonateSigner(args.fakeAddress || addresses.IdleTokens.mainnet.devLeagueMultisig);
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
