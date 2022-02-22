const addr0 = '0x0000000000000000000000000000000000000000';
const mainnetContracts = {
  idleDAIBest:  "0x3fE7940616e5Bc47b0775a0dccf6237893353bB4",
  idleUSDCBest: "0x5274891bEC421B39D23760c04A6755eCB444797C",
  idleUSDTBest: "0xF34842d05A1c888Ca02769A633DF37177415C2f8",
  idleSUSDBest: "0xf52cdcd458bf455aed77751743180ec4a595fd3f",
  idleTUSDBest: "0xc278041fDD8249FE4c1Aad1193876857EEa3D68c",
  idleWBTCBest: "0x8C81121B15197fA0eEaEE1DC75533419DcfD3151",
  idleWETHBest: "0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80",
  idleRAIBest: "0x5C960a3DCC01BE8a0f49c02A8ceBCAcf5D07fABe",
  idleFEIBest: "0xb2d5CB72A621493fe83C6885E4A776279be595bC",
  idleDAIRisk:  "0xa14eA0E11121e6E951E87c66AFe460A00BCD6A16",
  idleUSDCRisk: "0x3391bc034f2935ef0e1e41619445f998b2680d35",
  idleUSDTRisk: "0x28fAc5334C9f7262b3A3Fe707e250E01053e07b5",
  agEUR: '0x1a7e4e63778b4f12a199c062f3efdd288afcbce8',
  DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
  FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
  cDAI: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643',
  USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
  cUSDC: '0x39aa39c021dfbae8fac545936693ac917d5e7563',
  USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
  cUSDT: '0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9',
  IDLE: '0x875773784Af8135eA0ef43b5a374AaD105c5D39e',
  CVX: '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B',
  CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
  WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  ANGLE: '0x31429d1856ad1377a8a0079410b297e1a9e214c2',
  LDO: '0x5a98fcbea516cf06857215779fd812ca3bef1b32',
  CRV_3POOL: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
  CRV_STECRV: '0x06325440D014e39736583c165C2963BA99fAf14E',
  CRV_LUSD3CRV: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
  CRV_MIM3CRV: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
  CRV_FRAX3CRV: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
  CRV_ALUSD3CRV: '0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c',
  CRV_MUSD3CRV: '0x1AEf73d49Dedc4b1778d0706583995958Dc862e6',
  CRV_3EUR: '0xb9446c4Ef5EBE66268dA6700D26f96273DE3d571',
  uniRouter: '0x7a250d5630b4cf539739df2c5dacb4c659f2488d',
  sushiRouter: '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F',
  stkAAVE: '0x4da27a545c0c5b758a6ba100e3a049001de870f5',
  COMP: '0xc00e94Cb662C3520282E6f5717214004A7f26888',
  LDO: '0x5a98fcbea516cf06857215779fd812ca3bef1b32',
  stETH: '0xae7ab96520de3a18e5e111b5eaab095312d7fe84',
  wstETH: '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0',
  mUSD: '0xe2f2a5C287993345a840Db3B0845fbC70f5935a5',
  imUSD: '0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19',
  mUSDVault: '0x78BefCa7de27d07DC6e71da295Cc2946681A6c7B',
  MTA: '0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2',
  univ2Router: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
  treasuryMultisig: "0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814",
  devLeagueMultisig: '0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b',
  deployer: '0xE5Dab8208c1F4cce15883348B72086dBace3e64B',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  // NOTE: This is hardcoded in the contract too
  feeReceiver: '0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4',
  feeTreasury: '0x69a62C24F16d4914a48919613e8eE330641Bcb94',
  // end 10/2021
  // latestImplementation: '0x3cd51e62e14926dda0949ea3869d5fad0b9ab844',
  // 2/12/2021
  // latestImplementation: '0xb93450f818ae2ce89bc5d660049753883acbb883',
  // 19/1/2022
  latestImplementation: '0x31bee1fb186fc3bbc8f7639206d675cf3dea2140',
  // 2/12/2021
  latestIdleStrategyImpl: '0xd04843ac2ae7cfb7fe9ff6ff43c808af7a030527',
  // 8/2/2022 ConvexStrategy3Token
  latestConvexStrategyImpl: '0x81dBe9fF361C0422B86d929a91B48b79DA041a70',
  cdoFactory: '0x3C9916BB9498f637e2Fa86C2028e26275Dc9A631',
  snxStakingRewards: '0xd7c1b48877a7dfa7d51cf1144c89c0a3f134f935',
  minimalInitializableProxyFactory: '0x91baced76e3e327ba7850ef82a7a8251f6e43fb8'
}

exports.IdleTokens = {
  mainnet: mainnetContracts,
  local: mainnetContracts,
  kovan: {
    idleDAIBest: "0x295CA5bC5153698162dDbcE5dF50E436a58BA21e",
    idleUSDCBest: "0x0de23D3bc385a74E2196cfE827C8a640B8774B9f",
  },
};

// Deployed CDOs with relative addresses
const CDOs = {
  idleDAI: {
    decimals: 18,
    strategyToken: mainnetContracts.idleDAIBest,
    underlying: mainnetContracts.DAI,
    cdoAddr: '0xd0DbcD556cA22d3f3c142e9a3220053FD7a247BC',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x48a48c6694168093A3dEE02E9e8AC5a14169a652',
    AArewards: '0x9c3bC87693c65E740d8B2d5F0820E04A61D8375B',
    // BBrewards: '0x4473bc90118b18be890af42d793b5252c4dc382d',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xE9ada97bDB86d827ecbaACCa63eBcD8201D8b12E',
    BBTranche: '0x730348a54bA58F64295154F0662A08Cbde1225c2'
  },
  idleFEI: {
    decimals: 18,
    strategyToken: mainnetContracts.idleFEIBest,
    underlying: mainnetContracts.FEI,
    cdoAddr: '0x77648a2661687ef3b05214d824503f6717311596',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x73A44027bDAF5D71296d2C73cfb13e561c76a916',
    AArewards: '0x8fcD21253AaA7E228531291cC6f644d13B3cF0Ba',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x9cE3a740Df498646939BcBb213A66BBFa1440af6',
    BBTranche: '0x2490D810BF6429264397Ba721A488b0C439aA745'
  },
  lido: {
    decimals: 18,
    strategyToken: mainnetContracts.wstETH,
    underlying: mainnetContracts.stETH,
    cdoAddr: '0x34dcd573c5de4672c8248cd12a99f875ca112ad8',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x0cac674ebD77bBD899f6079932768f6d59Da089A',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x2688fc68c4eac90d9e5e1b94776cf14eade8d877',
    BBTranche: '0x3a52fa30c33caf05faee0f9c5dfe5fd5fe8b3978'
  },
  cvxfrax3crv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0xbc1707d16541108b7035e52e1daeb27ca4b6b79f',
    underlying: mainnetContracts.CRV_FRAX3CRV,
    cdoAddr: '0x4ccaf1392a17203edab55a1f2af3079a8ac513e7',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0xbc1707d16541108b7035e52e1daeb27ca4b6b79f',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x15794da4dcf34e674c18bbfaf4a67ff6189690f5',
    BBTranche: '0x18cf59480d8c16856701f66028444546b7041307'
  },
  cvxmim3crv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x35168324dC1981aDDc3bC915788e200BeDF77865',
    underlying: mainnetContracts.CRV_MIM3CRV,
    cdoAddr: '0x151e89e117728ac6c93aae94c621358b0ebd1866',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x35168324dC1981aDDc3bC915788e200BeDF77865',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xFC96989b3Df087C96C806318436B16e44c697102',
    BBTranche: '0x5346217536852CD30A5266647ccBB6f73449Cbd1'
  },
  cvxalusd3crv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0xdb7306ddba67dd9d5af08204e314f4de6c29e20d',
    underlying: mainnetContracts.CRV_ALUSD3CRV,
    cdoAddr: '0x008c589c471fd0a13ac2b9338b69f5f7a1a843e1',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0xdb7306ddba67dd9d5af08204e314f4de6c29e20d',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x790E38D85a364DD03F682f5EcdC88f8FF7299908',
    BBTranche: '0xa0E8C9088afb3Fa0F40eCDf8B551071C34AA1aa4'
  },
  cvxmusd3crv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x271ce5ded4ccbd28833bddf8a8093517299920f0',
    underlying: mainnetContracts.CRV_MUSD3CRV,
    cdoAddr: '0x16d88C635e1B439D8678e7BAc689ac60376fBfA6',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x271ce5ded4ccbd28833bddf8a8093517299920f0',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x4585F56B06D098D4EDBFc5e438b8897105991c6A',
    BBTranche: '0xFb08404617B6afab0b19f6cEb2Ef9E07058D043C'
  },
  cvx3eurCrv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x4ae60bc9a3efc160ae2eba70947a9b47ad2b9094',
    underlying: mainnetContracts.CRV_3EUR,
    cdoAddr: '0x858F5A3a5C767F8965cF7b77C51FD178C4A92F05',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x4ae60bc9a3efc160ae2eba70947a9b47ad2b9094',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x158e04225777BBEa34D2762b5Df9eBD695C158D2',
    BBTranche: '0x3061C652b49Ae901BBeCF622624cc9f633d01bbd'
  },
  cvxstecrv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x3bcba0afd36c9b350f46c570f89ab70817d122cb',
    underlying: mainnetContracts.CRV_STECRV,
    cdoAddr: '0x7ecfc031758190eb1cb303d8238d553b1d4bc8ef',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x3bcba0afd36c9b350f46c570f89ab70817d122cb',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x060a53BCfdc0452F35eBd2196c6914e0152379A6',
    BBTranche: '0xd83246d2bCBC00e85E248A6e9AA35D0A1548968E'
  },
  mstable: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x854b5b0f86bd1b53492736245a728e0a384252a2',
    underlying: mainnetContracts.mUSD,
    cdoAddr: '0x70320A388c6755Fc826bE0EF9f98bcb6bCCc6FeA',
    proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
    strategy: '0x854b5b0f86bd1b53492736245a728e0a384252a2',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xfC558914b53BE1DfAd084fA5Da7f281F798227E7',
    BBTranche: '0x91fb938FEa02DFd5303ACeF5a8A2c0CaB62b94C7'
  },
};

const baseCDOArgs = {
  incentiveTokens: [],
  proxyCdoAddress: CDOs.idleDAI.cdoAddr,
  AAStaking: false,
  BBStaking: false,
  stkAAVEActive: false,
  limit: '0',
  AARatio: '10000' // 100000 is 100% to AA
}

// CDOs with full params defined
exports.deployTokens = {
  // Idle 
  idledai: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleStrategy',
    strategyParams: [
      mainnetContracts.idleDAIBest,
      'owner'
    ],
    incentiveTokens: [mainnetContracts.IDLE],
    proxyCdoAddress: CDOs.idleDAI.cdoAddr,
    AAStaking: true,
    BBStaking: false,
    stkAAVEActive: true,
    limit: '0',
    AARatio: '10000', // 100000 is 100% to AA
    cToken: mainnetContracts.cDAI,
    cdo: CDOs.idleDAI
  },
  idlefei: {
    decimals: 18,
    underlying: mainnetContracts.FEI,
    strategyName: 'IdleStrategy',
    strategyParams: [
      mainnetContracts.idleFEIBest,
      'owner'
    ],
    incentiveTokens: [mainnetContracts.IDLE],
    proxyCdoAddress: CDOs.idleDAI.cdoAddr,
    AAStaking: false,
    BBStaking: false,
    stkAAVEActive: false,
    limit: '0',
    AARatio: '10000', // 100000 is 100% to AA
    cdo: CDOs.idleFEI
  },
  idleusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleStrategy',
    strategyParams: [
      mainnetContracts.idleUSDCBest,
      'owner'
    ],
    incentiveTokens: [mainnetContracts.IDLE],
    proxyCdoAddress: CDOs.idleDAI.cdoAddr,
    AAStaking: true,
    BBStaking: false,
    stkAAVEActive: true,
    limit: '0',
    AARatio: '10000', // 100000 is 100% to AA
    cToken: mainnetContracts.cUSDC
  },
  idleusdt: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    strategyName: 'IdleStrategy',
    strategyParams: [
      mainnetContracts.idleUSDTBest,
      'owner'
    ],
    incentiveTokens: [mainnetContracts.IDLE],
    proxyCdoAddress: CDOs.idleDAI.cdoAddr,
    AAStaking: true,
    BBStaking: false,
    stkAAVEActive: true,
    limit: '0',
    AARatio: '10000', // 100000 is 100% to AA
    cToken: mainnetContracts.cUSDT
  },

  // Lido 
  lido: {
    decimals: 18,
    underlying: mainnetContracts.stETH,
    strategyName: 'IdleLidoStrategy',
    strategyParams: [
      mainnetContracts.wstETH, // strategy token
      mainnetContracts.stETH, // underlying
      // mainnetContracts.deployer, // owner is set in the task
      'owner'
    ],
    cdo: CDOs.lido,
    ...baseCDOArgs
  },
  
  // mstable
  mstable: {
    decimals: 18,
    underlying: mainnetContracts.mUSD,
    strategyName: 'IdleMStableStrategy',
    strategyParams: [
      mainnetContracts.imUSD, // strategy token
      mainnetContracts.mUSD, // underlying
      mainnetContracts.mUSDVault, // vault
      mainnetContracts.univ2Router, // uni router
      [mainnetContracts.MTA, mainnetContracts.WETH, mainnetContracts.mUSD], // routerPath
      'owner', // owner address
    ],
    cdo: CDOs.mstable,
    ...baseCDOArgs
  },

  // Convex
  //
  // convexPoolId: can be found in the subgraph here 
  // https://thegraph.com/hosted-service/subgraph/convex-community/curve-pools
  // Example query for 3crv (it's lpToken is 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490)
  // ```
  // {
  //   platforms(first: 1) {
  //     curvePools(where: { lpToken: "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490" }) {
  //       id
  //     }
  //   }
  // }
  
  // depositPosition: 
  // - for strategy like `ConvexStrategyMeta3Pool` (cvxlusd3crv, cvxmim3crv, ...) can be found by looking at 
  // Curve registry https://etherscan.io/address/0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5
  // with the `get_underlying_coins` method passing the curve lpToken and find the `deposit` token index

  cvx3crv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_3POOL,
    strategyName: 'ConvexStrategy3Token',
    strategyParams: [
      9, // convexPoolId
      'owner', // owner address
      1500, // 6 hours harvested rewards release
      [mainnetContracts.DAI, addr0, 0], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
      [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ],
    ...baseCDOArgs
  },
  cvxlusd3crv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_LUSD3CRV,
    strategyName: 'ConvexStrategyMeta3Pool',
    strategyParams: [
      33, // convexPoolId
      'owner', // owner address
      1500, // 6 hours harvested rewards release
      [mainnetContracts.DAI, addr0, 1], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
      [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ],
    ...baseCDOArgs
  },
  cvxmim3crv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_MIM3CRV,
    strategyName: 'ConvexStrategyMeta3Pool',
    strategyParams: [
      40, // convexPoolId
      'owner', // owner address
      1500, // 6 hours harvested rewards release
      [mainnetContracts.DAI, addr0, 1], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
      [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ],
    cdo: CDOs.cvxmim3crv,
    ...baseCDOArgs
  },
  cvxfrax3crv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_FRAX3CRV,
    strategyName: 'ConvexStrategyMeta3Pool',
    strategyParams: [
      32, // convexPoolId
      'owner', // owner address
      1500, // 6 hours harvested rewards release
      [mainnetContracts.DAI, addr0, 1], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
      [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ],
    cdo: CDOs.cvxfrax3crv,
    ...baseCDOArgs
  },
  cvxalusd3crv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_ALUSD3CRV,
    strategyName: 'ConvexStrategyMeta3Pool',
    strategyParams: [
      36, // convexPoolId
      'owner', // owner address
      6400, // 24 hours harvested rewards release
      [mainnetContracts.DAI, addr0, 1], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
      [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ],
    cdo: CDOs.cvxalusd3crv,
    ...baseCDOArgs
  },
  cvxmusd3crv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_MUSD3CRV,
    strategyName: 'ConvexStrategyMUSD',
    strategyParams: [
      14, // convexPoolId
      'owner', // owner address
      6400, // 24 hours harvested rewards release
      [mainnetContracts.DAI, addr0, 1], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
      [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ],
    cdo: CDOs.cvxmusd3crv,
    ...baseCDOArgs
  },
  cvx3eurCrv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_3EUR,
    strategyName: 'ConvexStrategyPlainPool3Token',
    strategyParams: [
      60, // convexPoolId
      'owner', // owner address
      6400, // 6 hours harvested rewards release
      [mainnetContracts.agEUR, addr0, 0], // curveArgs (deposit, depositor, position)
      [
        [mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
        [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]],
        [mainnetContracts.ANGLE, mainnetContracts.sushiRouter, [mainnetContracts.ANGLE, mainnetContracts.WETH]]
      ], // rewards (token, router, path)
      [mainnetContracts.uniRouter, [mainnetContracts.WETH, mainnetContracts.FEI, mainnetContracts.agEUR]] // weth 2 deposit
    ],
    cdo: CDOs.cvx3eurCrv,
    ...baseCDOArgs
  },
  cvxstecrv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_STECRV,
    strategyName: 'ConvexStrategyETH',
    strategyParams: [
      25, // convexPoolId
      'owner', // owner address
      6400, // 24 hours harvested rewards release
      [mainnetContracts.WETH, addr0, 0], // curveArgs (deposit, depositor, position)
      [
        [mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
        [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]],
        [mainnetContracts.LDO, mainnetContracts.sushiRouter, [mainnetContracts.LDO, mainnetContracts.WETH]],
      ], // rewards (token, router, path)
      [addr0, []] // weth 2 deposit
    ],
    cdo: CDOs.cvxstecrv,
    ...baseCDOArgs
  },
};

exports.whale = '0xba12222222228d8ba445958a75a0704d566bf2c8'; // balancer
exports.whale1 = '0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE'; // binance
exports.whaleLDO = '0x09F82Ccd6baE2AeBe46bA7dd2cf08d87355ac430';
exports.addr0 = addr0;
exports.idleDeployer = '0xE5Dab8208c1F4cce15883348B72086dBace3e64B';
exports.timelock = '0xD6dABBc2b275114a2366555d6C481EF08FDC2556';
exports.CDOs = CDOs;
exports.mainnetContracts = mainnetContracts;