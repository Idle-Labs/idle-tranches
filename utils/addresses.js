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
  eagEUR: '0x64ad6d2472de5DDd3801fB4027C96c3ee7a7ee82',
  DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
  FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
  cDAI: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643',
  USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
  eUSDC: '0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716',
  eDAI: '0xe025E3ca2bE02316033184551D4d3Aa22024D9DC',
  eUSDT: '0x4d19F33948b99800B6113Ff3e83beC9b537C85d2',
  cUSDC: '0x39aa39c021dfbae8fac545936693ac917d5e7563',
  cpWIN_USDC: '0xCb288b6d30738db7E3998159d192615769794B5b',
  tfUSDC: '0xA991356d261fbaF194463aF6DF8f0464F8f1c742',
  tfUSDCMultifarm: '0xec6c3FD795D6e6f202825Ddb56E01b3c128b0b10',
  USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
  cUSDT: '0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9',
  IDLE: '0x875773784Af8135eA0ef43b5a374AaD105c5D39e',
  CVX: '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B',
  CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
  WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  WBTC: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
  ANGLE: '0x31429d1856ad1377a8a0079410b297e1a9e214c2',
  LDO: '0x5a98fcbea516cf06857215779fd812ca3bef1b32',
  PNT: '0x89ab32156e46f46d02ade3fecbe5fc4243b9aaed',
  CRV_3POOL: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
  CRV_STECRV: '0x06325440D014e39736583c165C2963BA99fAf14E',
  CRV_LUSD3CRV: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
  CRV_MIM3CRV: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
  CRV_FRAX3CRV: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
  CRV_ALUSD3CRV: '0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c',
  CRV_MUSD3CRV: '0x1AEf73d49Dedc4b1778d0706583995958Dc862e6',
  CRV_3EUR: '0xb9446c4Ef5EBE66268dA6700D26f96273DE3d571',
  CRV_PBTC: '0xC9467E453620f16b57a34a770C6bceBECe002587',
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
  feeReceiver: '0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814',
  oldFeeReceiver: '0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4',
  feeTreasury: '0x69a62C24F16d4914a48919613e8eE330641Bcb94',
  // end 10/2021
  // latestImplementation: '0x3cd51e62e14926dda0949ea3869d5fad0b9ab844',
  // 2/12/2021
  // latestImplementation: '0xb93450f818ae2ce89bc5d660049753883acbb883',
  // 19/1/2022
  // latestImplementation: '0x31bee1fb186fc3bbc8f7639206d675cf3dea2140',
  // 13/07/2022
  latestImplementation: '0xBeD6E1FF4363730a56dfDcd6689e5D958085299d',
  // 2/12/2021
  latestIdleStrategyImpl: '0xd04843ac2ae7cfb7fe9ff6ff43c808af7a030527',
  // 8/3/2022 ConvexStrategyMeta3Pool
  latestConvexStrategyImpl: '0x6042d559acf454f73d8c0319386e46f65ee77fd7',
  latestConvexStrategy3eurImpl: '0x8f889dc453750c91c921bd6fb9a33a8a579b1baa',
  cdoFactory: '0x3C9916BB9498f637e2Fa86C2028e26275Dc9A631',
  snxStakingRewards: '0x4A07723BB06BF9307E4E1998834832728e6cDb49',
  snxStakingRewardsLido: '0xd7c1b48877a7dfa7d51cf1144c89c0a3f134f935',
  minimalInitializableProxyFactory: '0x91baced76e3e327ba7850ef82a7a8251f6e43fb8',
  proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
  eulerMain: '0x27182842E098f60e3D576794A5bFFb0777E025d3',
  idleCDORegistry: '0x84fdee80f18957a041354e99c7eb407467d94d8e'
}

// Polygon
const polygonContracts = {
  // rewards
  QUICK: '0x831753dd7087cac61ab5644b308642cc1c33dc13',
  dQUICK: '0xf28164A485B0B2C90639E47b0f377b4a438a16B1',
  WMATIC: '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270',
  // wbtc
  WBTC: '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6',
  CXWBTC: '',
  CXBTC_WBTC_LP: '',
  CXBTC_WBTC_REWARDS: '',
  // weth
  WETH: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619',
  CXETH: '0xfe4546feFe124F30788c4Cc1BB9AA6907A7987F9',
  CXETH_WETH_LP: '0xda7cd765DF426fCA6FB5E1438c78581E4e66bFe7',
  CXETH_WETH_REWARDS: '0xD8F0af6c455e09c44d134399eD1DF151043840E6',
  // misc
  cdoFactory: '0xf12aCB52E784B9482bbe4ef1C5741352584bE4Ca',
  quickRouter: '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff',
  feeReceiver: '0x1d60E17723f8Ca1F76F09126242AcD37a278b514',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  treasuryMultisig: '0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6',
  devLeagueMultisig: '0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6',
  proxyAdmin: '0x44b6CDda5D030B29eEc58009F6f474082313C470',
}

exports.IdleTokens = {
  polygon: polygonContracts,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x0cac674ebD77bBD899f6079932768f6d59Da089A',
    AArewards: '0x0000000000000000000000000000000000000000',
    // old StakingRewards contract, now Gauge
    // AArewards: '0xd7C1b48877A7dFA7D51cf1144c89C0A3F134F935',
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
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
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x3bcba0afd36c9b350f46c570f89ab70817d122cb',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x060a53BCfdc0452F35eBd2196c6914e0152379A6',
    BBTranche: '0xd83246d2bCBC00e85E248A6e9AA35D0A1548968E'
  },
  cvxpbtccrv: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x0198792f2849397908C092b6B57654e1a57a4CDC',
    underlying: mainnetContracts.CRV_PBTC,
    cdoAddr: '0xf324Dca1Dc621FCF118690a9c6baE40fbD8f09b7',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x0198792f2849397908C092b6B57654e1a57a4CDC',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x4657B96D587c4d46666C244B40216BEeEA437D0d',
    BBTranche: '0x3872418402d1e967889aC609731fc9E11f438De5'
  },
  mstable: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x854b5b0f86bd1b53492736245a728e0a384252a2',
    underlying: mainnetContracts.mUSD,
    cdoAddr: '0x70320A388c6755Fc826bE0EF9f98bcb6bCCc6FeA',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x854b5b0f86bd1b53492736245a728e0a384252a2',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xfC558914b53BE1DfAd084fA5Da7f281F798227E7',
    BBTranche: '0x91fb938FEa02DFd5303ACeF5a8A2c0CaB62b94C7'
  },
  eulerusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: mainnetContracts.eUSDC,
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xf5a3d259bfe7288284bd41823ec5c8327a314054',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x5DaD2eEF80a8cdFD930aB8f0353cA13Bd48c4346',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x1e095cbF663491f15cC1bDb5919E701b27dDE90C',
    BBTranche: '0xe11679CDb4587FeE907d69e9eC4a7d3F0c2bcf3B'
  },
  eulerdai: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: mainnetContracts.eDAI,
    underlying: mainnetContracts.DAI,
    cdoAddr: '0x46c1f702a6aad1fd810216a5ff15aab1c62ca826',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0xc7f1b9c72b8230e470420a4b69af7c50781a3f44',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x852c4d2823E98930388b5cE1ed106310b942bD5a',
    BBTranche: '0x6629baA8C7c6a84290Bf9a885825E3540875219D'
  },
  eulerusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: mainnetContracts.eUSDT,
    underlying: mainnetContracts.USDT,
    cdoAddr: '0xD5469DF8CA36E7EaeDB35D428F28E13380eC8ede',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x3d1775dA27Dd9c6d936795Ac21b94CDeD8baBD69',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xE0f126236d2a5b13f26e72cBb1D1ff5f297dDa07',
    BBTranche: '0xb1EC065abF6783BCCe003B8d6B9f947129504854'
  },
  eulerageur: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: mainnetContracts.eagEUR,
    underlying: mainnetContracts.agEUR,
    cdoAddr: '0x2398Bc075fa62Ee88d7fAb6A18Cd30bFf869bDa4',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x8468B8Efe7eeA52978Ccfe3C0248Ca6F6895e166',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x624DfE05202b66d871B8b7C0e14AB29fc3a5120c',
    BBTranche: '0xcf5FD05F72cA777d71FB3e38F296AAD7cE735cB7'
  },
  cpwinusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x54ae90be2dee0a960953c724839541e75bb1f471',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xDBCEE5AE2E9DAf0F5d93473e08780C9f45DfEb93',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x54ae90be2dee0a960953c724839541e75bb1f471',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xb86264c21418aA75F7c337B1821CcB4Ff4d57673',
    BBTranche: '0x4D9d9AA17c3fcEA05F20a87fc1991A045561167d'
  },
  truefiusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x62B17c9083Db5941197E83BD385985B8878B58Fb',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x1f5A97fB665e295303D2F7215bA2160cc5313c8E',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x62B17c9083Db5941197E83BD385985B8878B58Fb',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x868bb78fb045576162B510ba33358C9f93e7959e',
    BBTranche: '0x6EdE2522347E6a5A0420F41f42e021246e97B540'
  },
};

const polygonCDOs = {
  quickcxethweth: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0xEc470753b56Ced3784ce29DB7C297f0C1b75fC87',
    underlying: polygonContracts.CXETH_WETH_LP,
    cdoAddr: '0xB144eE58679e15f1b25A5F6EfcEBDd0AB8c8BEF5',
    proxyAdmin: polygonContracts.proxyAdmin,
    strategy: '0xEc470753b56Ced3784ce29DB7C297f0C1b75fC87',
    AArewards: '0x466cFDfF869666941CdB89daa412c3CddC55D6c1',
    BBrewards: '0x727d9c331e9481167Dc61A9289C948da25bE825e',
    AATranche: '0x967b2fdEc06c0178709F1BFf56E0aA9367c3225c',
    BBTranche: '0x1aFf460F388E3822756F5697f05A7E2AEB8Db7ef'
  },
  // quickcxbtcwbtc: {
  //   decimals: 18,
  //   // strategyToken it's the strategy itself here
  //   strategyToken: '',
  //   underlying: polygonContracts.CXBTC_WBTC_LP,
  //   cdoAddr: '',
  //   proxyAdmin: polygonContracts.proxyAdmin,
  //   strategy: '',
  //   AArewards: '',
  //   BBrewards: '',
  //   AATranche: '',
  //   BBTranche: ''
  // },
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

  // euler
  eulerusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleEulerStrategy',
    strategyParams: [
      mainnetContracts.eUSDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      'owner', // owner address
    ],
    cdo: CDOs.eulerusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
  },
  eulerusdt: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    strategyName: 'IdleEulerStrategy',
    strategyParams: [
      mainnetContracts.eUSDT, // _strategyToken
      mainnetContracts.USDT, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      'owner', // owner address
    ],
    // cdo: CDOs.eulerusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdc.cdoAddr,
  },
  eulerdai: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleEulerStrategy',
    strategyParams: [
      mainnetContracts.eDAI, // _strategyToken
      mainnetContracts.DAI, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      'owner', // owner address
    ],
    cdo: CDOs.eulerdai,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdc.cdoAddr,
  },
  eulerageur: {
    decimals: 18,
    underlying: mainnetContracts.agEUR,
    strategyName: 'IdleEulerStrategy',
    strategyParams: [
      mainnetContracts.eagEUR, // _strategyToken
      mainnetContracts.agEUR, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      'owner', // owner address
    ],
    cdo: CDOs.eulerageur,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdc.cdoAddr,
  },
  // Clearpool
  cpwinusdc: { // wintermute pool
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleClearpoolStrategy',
    strategyParams: [
      mainnetContracts.cpWIN_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpwinusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdc.cdoAddr,
  },
  // Truefi
  truefiusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleTruefiStrategy',
    strategyParams: [
      mainnetContracts.tfUSDC, // _strategyToken
      mainnetContracts.tfUSDCMultifarm, // _underlyingToken
      'owner' // owner address
    ],
    cdo: CDOs.truefiusdc,
    cdoVariant: 'IdleCDOTruefiVariant',
    unlent: 0,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: '', // deploy new instance
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
      [
        [mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
        [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]]
      ], // rewards (token, router, path)
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
  cvxpbtccrv: {
    decimals: 18,
    underlying: mainnetContracts.CRV_PBTC,
    strategyName: 'ConvexStrategyMetaBTC',
    strategyParams: [
      77, // convexPoolId
      'owner', // owner address
      6400, // 24 hours harvested rewards release
      [mainnetContracts.WBTC, addr0, 2], // curveArgs (deposit, depositor, position)
      [
        [mainnetContracts.CVX, mainnetContracts.sushiRouter, [mainnetContracts.CVX, mainnetContracts.WETH]],
        [mainnetContracts.CRV, mainnetContracts.sushiRouter, [mainnetContracts.CRV, mainnetContracts.WETH]],
      ], // rewards (token, router, path)
      [mainnetContracts.sushiRouter, [mainnetContracts.WETH, mainnetContracts.WBTC]] // weth 2 deposit
    ],
    cdo: CDOs.cvxpbtccrv,
    ...baseCDOArgs,
  },
};

exports.deployTokensPolygon = {
  quickcxethweth: {
    decimals: 18,
    underlying: polygonContracts.CXETH_WETH_LP,
    strategyName: 'IdleQuickswap',
    strategyParams: [
      polygonContracts.CXETH_WETH_LP, // underlying
      polygonContracts.WETH, // baseToken of the LP
      polygonContracts.CXETH, // celsiusx tokenized ETH
      'owner', // owner address
      polygonContracts.CXETH_WETH_REWARDS, // stakingRewards
      polygonContracts.quickRouter, 
    ],
    incentiveTokens: [polygonContracts.dQUICK],
    proxyCdoAddress: polygonCDOs.quickcxethweth.cdoAddr,
    AAStaking: true,
    BBStaking: true,
    stkAAVEActive: false,
    limit: '0',
    AARatio: '10000', // 100000 is 100% to AA
    cdo: polygonCDOs.quickcxethweth,
  },
  // quickcxbtcwbtc: {
  //   decimals: 18,
  //   underlying: polygonContracts.CXBTC_WBTC_LP,
  //   strategyName: 'IdleQuickswap',
  //   strategyParams: [
  //     polygonContracts.CXBTC_WBTC_LP, // underlying
  //     polygonContracts.WBTC, // baseToken of the LP
  //     polygonContracts.CXBTC, // celsiusx tokenized BTC
  //     'owner', // owner address
  //     polygonContracts.CXBTC_WBTC_REWARDS, // stakingRewards
  //     polygonContracts.quickRouter,
  //   ],
  //   incentiveTokens: [polygonContracts.dQUICK],
  //   proxyCdoAddress: polygonCDOs.quickcxethweth.cdoAddr,
  //   AAStaking: true,
  //   BBStaking: true,
  //   stkAAVEActive: false,
  //   limit: '0',
  //   AARatio: '10000', // 100000 is 100% to AA
  //   // cdo: polygonCDOs.quickcxbtcwbtc,
  // }
};

exports.whale = '0xba12222222228d8ba445958a75a0704d566bf2c8'; // balancer
exports.whale1 = '0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE'; // binance
exports.whaleLDO = '0x09F82Ccd6baE2AeBe46bA7dd2cf08d87355ac430';
exports.addr0 = addr0;
exports.idleDeployer = '0xE5Dab8208c1F4cce15883348B72086dBace3e64B';
exports.timelock = '0xD6dABBc2b275114a2366555d6C481EF08FDC2556';
exports.CDOs = CDOs;
exports.polygonCDOs = polygonCDOs;
exports.mainnetContracts = mainnetContracts;