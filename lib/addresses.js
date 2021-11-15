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
  DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
  cDAI: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643',
  USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
  cUSDC: '0x39aa39c021dfbae8fac545936693ac917d5e7563',
  USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
  cUSDT: '0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9',
  IDLE: '0x875773784Af8135eA0ef43b5a374AaD105c5D39e',
  CVX: '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B',
  CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
  WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  CRV_3POOL: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
  CRV_STECRV: '0x06325440D014e39736583c165C2963BA99fAf14E',
  sushiRouter: '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F',
  stkAAVE: '0x4da27a545c0c5b758a6ba100e3a049001de870f5',
  COMP: '0xc00e94Cb662C3520282E6f5717214004A7f26888',
  FEI: '0x956f47f50a910163d8bf957cf5846d573e7f87ca',
  treasuryMultisig: "0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814",
  devLeagueMultisig: '0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  // NOTE: This is hardcoded in the contract too
  feeReceiver: '0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4',
  feeTreasury: '0x69a62C24F16d4914a48919613e8eE330641Bcb94',
  latestImplementation: '0x2d90df48c706874f1b9a02054273996fbf458964',
  cdoFactory: '0x3C9916BB9498f637e2Fa86C2028e26275Dc9A631',
}

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
    AATranche: '0x9cE3a740Df498646939BcBb213A66BBFa1440af6,',
    BBTranche: '0x2490D810BF6429264397Ba721A488b0C439aA745'
  }
};

exports.IdleTokens = {
  mainnet: mainnetContracts,
  local: mainnetContracts,
  kovan: {
    idleDAIBest: "0x295CA5bC5153698162dDbcE5dF50E436a58BA21e",
    idleUSDCBest: "0x0de23D3bc385a74E2196cfE827C8a640B8774B9f",
  },
};
exports.whale = '0xba12222222228d8ba445958a75a0704d566bf2c8'; // balancer
exports.whale1 = '0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE'; // binance
exports.addr0 = '0x0000000000000000000000000000000000000000';
exports.idleDeployer = '0xE5Dab8208c1F4cce15883348B72086dBace3e64B';
exports.timelock = '0xD6dABBc2b275114a2366555d6C481EF08FDC2556';
exports.CDOs = CDOs;
exports.deployTokens = {
  idledai: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    idleToken: mainnetContracts.idleDAIBest,
    cToken: mainnetContracts.cDAI,
    cdo: CDOs.idleDAI
  },
  idleusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    idleToken: mainnetContracts.idleUSDCBest,
    cToken: mainnetContracts.cUSDC
  },
  idleusdt: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    idleToken: mainnetContracts.idleUSDTBest,
    cToken: mainnetContracts.cUSDT
  },
  idlefei: {
    decimals: 18,
    underlying: mainnetContracts.FEI,
    idleToken: mainnetContracts.idleFEIBest,
    cdo: CDOs.idleFEI
  }
};
exports.deployConvex = {
  cvx3crv: {
    contractName: 'ConvexStrategy3Token',
    underlyingAddress: mainnetContracts.CRV_3POOL,
    strategyArgs :[
      9, // convexPoolId
      '', // owner address
      [mainnetContracts.DAI, mainnetContracts.addr0, 0], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]], 
       [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.DAI]] // weth 2 deposit
    ]
  },
  cvxstecrv: {
    contractName: 'ConvexStrategyETH',
    underlyingAddress: mainnetContracts.CRV_STECRV,
    strategyArgs: [
      25, // convexPoolId
      '', // owner address
      [mainnetContracts.WETH, mainnetContracts.addr0, 0], // curveArgs (deposit, depositor, position)
      [[mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
       [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]], // rewards (token, router, path)
      [mainnetContracts.addr0, []] // weth 2 deposit
    ]
  }
}
