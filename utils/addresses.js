const ethers = require('ethers');

const addr0 = '0x0000000000000000000000000000000000000000';
const mainnetContracts = {
  idleDAIBest: "0x3fE7940616e5Bc47b0775a0dccf6237893353bB4",
  idleUSDCBest: "0x5274891bEC421B39D23760c04A6755eCB444797C",
  idleUSDTBest: "0xF34842d05A1c888Ca02769A633DF37177415C2f8",
  idleSUSDBest: "0xf52cdcd458bf455aed77751743180ec4a595fd3f",
  idleTUSDBest: "0xc278041fDD8249FE4c1Aad1193876857EEa3D68c",
  idleWBTCBest: "0x8C81121B15197fA0eEaEE1DC75533419DcfD3151",
  idleWETHBest: "0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80",
  idleRAIBest: "0x5C960a3DCC01BE8a0f49c02A8ceBCAcf5D07fABe",
  idleFEIBest: "0xb2d5CB72A621493fe83C6885E4A776279be595bC",
  idleDAIRisk: "0xa14eA0E11121e6E951E87c66AFe460A00BCD6A16",
  idleUSDCRisk: "0x3391bc034f2935ef0e1e41619445f998b2680d35",
  idleUSDTRisk: "0x28fAc5334C9f7262b3A3Fe707e250E01053e07b5",
  agEUR: '0x1a7e4e63778b4f12a199c062f3efdd288afcbce8',
  eagEUR: '0x64ad6d2472de5DDd3801fB4027C96c3ee7a7ee82',
  DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
  FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
  cDAI: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643',
  USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
  aDAI: '0x028171bCA77440897B824Ca71D1c56caC55b68A3',
  aUSDC: '0xbcca60bb61934080951369a648fb03df4f96263c',
  dUSDCEul: '0x84721A3dB22EB852233AEAE74f9bC8477F8bcc42',
  SWISE: '0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2',
  BTRFLY: '0xc55126051b22ebb829d00368f4b12bde432de5da',
  // ethena
  SUSDe: '0x9D39A5DE30e57443BfF2A8307A4256c8797A3497',
  USDe: '0x4c9EDD5852cd905f086C759E8383e09bff1E68B3',
  // morpho, check https://github.com/morpho-dao/morpho-tokenized-vaults#morpho-aave-v2-ethereum
  maUSDC: '0xa5269a8e31b93ff27b887b56720a25f844db0529',
  maUSDT: '0xafe7131a57e44f832cb2de78ade38cad644aac2f',
  maDAI: '0x36f8d0d0573ae92326827c4a82fe4ce4c244cab6',
  maWETH: '0x490bbbc2485e99989ba39b34802fafa58e26aba4',
  MORPHO: '0x9994E35Db50125E0DF82e4c2dde62496CE330999',
  mmSnippets: '0xDfd98F2FaB869B18aD4322B2c7B1227c576402c6',
  // mmSnippets: '0x7a928e2a07e093fb83db52e63dfb93c2f5ff42ff',
  MORPHO_BLUE: '0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb',
  mmWETHbbWETH: '0x38989BBA00BDF8181F4082995b3DEAe96163aC5D',
  mmWETHre7WETH: '0x78fc2c2ed1a4cdb5402365934ae5648adad094d0',
  mmUSDCsteakUSDC: '0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB',
  // gearbox
  GEAR: '0xBa3335588D9403515223F109EdC4eB7269a9Ab5D',
  dWETH: '0xda0002859B2d05F66a753d8241fCDE8623f26F4f',
  sdWETH: '0x0418fEB7d0B25C411EB77cD654305d29FcbFf685',
  dUSDC: '0xda00000035fef4082F78dEF6A8903bee419FbF8E',
  sdUSDC: '0x9ef444a6d7F4A5adcd68FD5329aA5240C90E14d2',
  // euler
  eWETH: '0x1b808F49ADD4b8C6b5117d9681cF7312Fcf0dC1D',
  eUSDC: '0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716',
  eDAI: '0xe025E3ca2bE02316033184551D4d3Aa22024D9DC',
  eUSDT: '0x4d19F33948b99800B6113Ff3e83beC9b537C85d2',
  eUSDCStaking: '0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570',
  eUSDTStaking: '0x7882F919e3acCa984babd70529100F937d90F860',
  eWETHStaking: '0x229443bf7F1297192394B7127427DB172a5bDe9E',
  // clearpool / ribbon
  cUSDC: '0x39aa39c021dfbae8fac545936693ac917d5e7563',
  CPOOL: '0x66761Fa41377003622aEE3c7675Fc7b5c1C2FaC5',
  RBN: '0x6123B0049F904d730dB3C36a31167D9d4121fA6B',
  cpWIN_USDC: '0xCb288b6d30738db7E3998159d192615769794B5b',
  cpFOL_USDC: '0xe3D20A721522874D32548B4097d1afc6f024e45b',
  cpPOR_USDC: '0x4a90c14335e81829d7cb0002605f555b8a784106',
  cpFAS_USDT: '0x1A1d778776542c2efEd161bA1fbCfe6e09Ba99Fb',
  cpFAS_USDC: '0xa75dd592826fa9c679ec03beefb1777ba1a373a0',
  cpWINC_USDC: '0xa0749f550a336b031f63bd095062204e1a56055b',
  rWIN_USDC: '0x0aea75705be8281f4c24c3e954d1f8b1d0f8044c',
  rFOL_USDC: '0x3CD0ecf1552D135b8Da61c7f44cEFE93485c616d',
  // truefi
  tfUSDC: '0xA991356d261fbaF194463aF6DF8f0464F8f1c742',
  tfUSDCMultifarm: '0xec6c3FD795D6e6f202825Ddb56E01b3c128b0b10',
  // usual 
  USD0pp: '0x35D8949372D46B7a3D5A56006AE77B215fc69bC0',
  USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
  cWETH: '0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5',
  aWETH: '0x030bA81f1c18d280636F32af80b9AAd02Cf0854e',
  cUSDT: '0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9',
  aUSDT: '0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811',
  IDLE: '0x875773784Af8135eA0ef43b5a374AaD105c5D39e',
  CVX: '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B',
  CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
  WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  WBTC: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
  ANGLE: '0x31429d1856ad1377a8a0079410b297e1a9e214c2',
  LDO: '0x5a98fcbea516cf06857215779fd812ca3bef1b32',
  MATIC: '0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0',
  stMATIC: '0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599',
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
  instaETHv2: '0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78',
  amprWSTETH: '0x2791EB5807D69Fe10C02eED6B4DC12baC0701744',
  amprUSDC: '0x3b022EdECD65b63288704a6fa33A8B9185b5096b',
  mUSD: '0xe2f2a5C287993345a840Db3B0845fbC70f5935a5',
  imUSD: '0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19',
  mUSDVault: '0x78BefCa7de27d07DC6e71da295Cc2946681A6c7B',
  MTA: '0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2',
  EUL: '0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b',
  univ2Router: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
  univ3Router: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
  treasuryMultisig: "0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814",
  devLeagueMultisig: '0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b',
  pauserMultisig: '0xBaeCba470C229984b75BC860EFe8e97AE082Bb9f',
  hypernativeModule: '0xa08b4aee0eef2203e4b9fc8f54e848ca6ba78bf5',
  deployer: '0xE5Dab8208c1F4cce15883348B72086dBace3e64B',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  // NOTE: This is hardcoded in the contract too
  feeReceiver: '0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814',
  oldFeeReceiver: '0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4',
  feeTreasury: '0x69a62C24F16d4914a48919613e8eE330641Bcb94',
  delegateStakingRewards: '0x747E819B878956FB6E5eB936A6415a5D037fF388',
  // end 10/2021
  // latestImplementation: '0x3cd51e62e14926dda0949ea3869d5fad0b9ab844',
  // 2/12/2021
  // latestImplementation: '0xb93450f818ae2ce89bc5d660049753883acbb883',
  // 19/1/2022
  // latestImplementation: '0x31bee1fb186fc3bbc8f7639206d675cf3dea2140',
  // 13/07/2022
  // latestImplementation: '0xBeD6E1FF4363730a56dfDcd6689e5D958085299d',
  // 18/10/2022 Polido variant with univ3
  latestImplementationPolido: '0x6df196928ace3c98b12ff0769b3164753e5099aa',
  // 18/10/2022 Generic with univ3
  // latestImplementation: '0xAD6Cc71ef6bA82FFAd9Adf40220d035669EACB58',
  // 22/03/2024 Generic with AA fully liquid (with skipDefaultCheck = true)
  latestImplementation: '0x1EA9aE797972ad9fc52C55105D184d8B059BB716',
  // 2/12/2021
  latestIdleStrategyImpl: '0xd04843ac2ae7cfb7fe9ff6ff43c808af7a030527',
  // 8/3/2022 ConvexStrategyMeta3Pool
  latestConvexStrategyImpl: '0x6042d559acf454f73d8c0319386e46f65ee77fd7',
  // 2022
  idleTokenImpl: '0x1247b148062179cd6156f68d9a1019f671f955c1',
  // 1/3/2023
  idleTokenSingleRedeemImpl: '0xbdbc6d788d8090d3b72c6d5a1f763d5b56eeb907',
  latestConvexStrategy3eurImpl: '0x8f889dc453750c91c921bd6fb9a33a8a579b1baa',
  cdoFactory: '0x3C9916BB9498f637e2Fa86C2028e26275Dc9A631',
  creditVaultFactory: '0x59AaBdAD8FdABd227cc71543B128765F93906626',
  snxStakingRewards: '0x4A07723BB06BF9307E4E1998834832728e6cDb49',
  snxStakingRewardsLido: '0xd7c1b48877a7dfa7d51cf1144c89c0a3f134f935',
  minimalInitializableProxyFactory: '0x91baced76e3e327ba7850ef82a7a8251f6e43fb8',
  proxyAdmin: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
  // same as proxyAdmin which now has a timelock
  proxyAdminWithTimelock: '0x9438904ABC7d8944A6E2A89671fEf51C629af351',
  eulerMain: '0x27182842E098f60e3D576794A5bFFb0777E025d3',
  eulerDistributor: '0xd524E29E3BAF5BB085403Ca5665301E94387A7e2',
  idleCDORegistry: '0x84fdee80f18957a041354e99c7eb407467d94d8e',
  trancheErc4626Wrapper: '0xB286a43F3EfF9059117f58EE2472d1c902416810',
  trancheErc4626WrapperUSDT: '0xcf96f4b91c6d424fb34aa9a33855b5c8ed1fe66d',
  trancheErc4626WrapperBalancerVariant: '0x6bf9ea02daab6b4b3b71cce20a84088a71bf723a',
  idleTokenErc4626Wrapper: '0x658a190730be0afb1ea39295f7ffee6d44aaefa7',
  idleTokenErc4626WrapperUSDT: '0x544897a3b944fdeb1f94a0ed973ea31a80ae18e1',
  cloneableFeeRebateMerkleDistributor: '0x69369507aa7a44156cc297448ab57e3c15d26485',
  timelock: '0xDa86e15d0Cda3A05Db930b248d7a2f775e575A44',
  keyringWhitelist: '0x6a6A91c7c7C05f9f6B8bC9F6e5eA231e460450e3',
  sealSafeHarbor: '0xeca050F53ee4eCBc039DD07CB4FB785641521707',
  cdoImplWriteOff: '0x9F3A307B61b152128f416806e737E990fF8B62de',
  strategyImplWriteOff: '0xc499925d7991FF8204967Ac58455293f2Db3855A',
}

// Polygon
const polygonContracts = {
  // rewards
  QUICK: '0x831753dd7087cac61ab5644b308642cc1c33dc13',
  dQUICK: '0xf28164A485B0B2C90639E47b0f377b4a438a16B1',
  WMATIC: '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270',
  // wbtc
  WBTC: '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6',
  // weth
  WETH: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619',
  CXETH: '0xfe4546feFe124F30788c4Cc1BB9AA6907A7987F9',
  CXETH_WETH_LP: '0xda7cd765DF426fCA6FB5E1438c78581E4e66bFe7',
  CXETH_WETH_REWARDS: '0xD8F0af6c455e09c44d134399eD1DF151043840E6',
  // misc
  cdoFactory: '0xf12aCB52E784B9482bbe4ef1C5741352584bE4Ca',
  quickRouter: '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff',
  feeReceiver: '0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  deployer: '0xE5Dab8208c1F4cce15883348B72086dBace3e64B',
  treasuryMultisig: '0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6',
  devLeagueMultisig: '0x61A944Ca131Ab78B23c8449e0A2eF935981D5cF6',
  proxyAdmin: '0x44b6CDda5D030B29eEc58009F6f474082313C470',
  // Same as proxyAdmin
  proxyAdminWithTimelock: '0x44b6CDda5D030B29eEc58009F6f474082313C470',
  timelock: '0x45f4fb4D0CCC439bB7B85Ba63064958ab7e31EE4',
  keyring: '0x88e097c960ad0239b4eec6e8c5b4f74f898efda3',
  keyringWhitelist: '0x168dc532aa8071003daa1a8094d938511f412e2b',
  // This is an instance of HypernativeBatchPauser
  pauserMultisig: '0x1B0f494EF778907336bD7E631607db2C8019BF76',
  // This is generated in hypernative dashboard
  hypernativePauserEOA: '0x8c3d89334811e607fe488d1a3ac393a8a8445b32',
  USDT: '0xc2132d05d31c914a87c6611c10748aeb04b58e8f',
}

const polygonZKContracts = {
  // deployer: '0xe8833ca9D4592d0A4dAf1A6ad4e2212742D76175',
  deployer: '0xE5Dab8208c1F4cce15883348B72086dBace3e64B',
  cdoFactory: '0xba43DE746840eD16eE53D26af0675d8E6c24FE38',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  feeReceiver: '0x13854835c508FC79C3E5C5Abf7afa54b4CcC1Fdf',
  treasuryMultisig: '0x13854835c508FC79C3E5C5Abf7afa54b4CcC1Fdf',
  devLeagueMultisig: '0x13854835c508FC79C3E5C5Abf7afa54b4CcC1Fdf',
  proxyAdmin: '0x8aA1379e46A8C1e9B7BB2160254813316b5F35B8',
  trancheErc4626Wrapper: '0x0ac74Fe6f3C9123254418EEfcE37E4f7271a2b72',

  MATIC: '0xa2036f0538221a77A3937F1379699f44945018d0',
  WETH: '0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9',
  USDT: '0x1E4a5963aBFD975d8c9021ce480b42188849D41d',
  cpPOR_USDT: '0x6beb2006a2c8b2dc90d924b8b19be084bc5a5eba',
  USDC: '0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035',
  cpFAS_USDC: '0xfa42f010aac1acbb10018c7bf1588446e7e11bfb',

  // same as trancheErc4626Wrapper blueprint
  AA_4626_cpporusdt: '0x0ac74fe6f3c9123254418eefce37e4f7271a2b72',
  AA_4626_cpfasusdc: '0xFbc63d309F915AA62517A6b4e845502CEcf946cf',
}

const optimismContracts = {
  deployer: '0xE5Dab8208c1F4cce15883348B72086dBace3e64B',
  cdoFactory: '0x8aA1379e46A8C1e9B7BB2160254813316b5F35B8',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  feeReceiver: '0xFDbB4d606C199F091143BD604C85c191a526fbd0',
  treasuryMultisig: '0xFDbB4d606C199F091143BD604C85c191a526fbd0',
  devLeagueMultisig: '0xFDbB4d606C199F091143BD604C85c191a526fbd0',
  proxyAdmin: '0xB5D4D8d9122Bf252B65DAbb64AaD68346405443C',
  proxyAdminWithTimelock: '0x73B4F354fD8d37fDB7CF13390D366E959E1E2BDf',
  timelock: '0xa3a3741c48298e21EEbE5A59bEAF6f89DC0E0c4c',
  // This is an instance of HypernativeBatchPauser
  pauserMultisig: '0x290C4dC2402CD77643aF42Ba926A15Aba4d3508b',
  // This is generated in hypernative dashboard
  hypernativePauserEOA: '0x8c3d89334811e607fe488d1a3ac393a8a8445b32',
  keyringWhitelist: '0x685bc814f9ee40fa7bd35588ac6a9e882a2345f3',

  OP: '0x4200000000000000000000000000000000000042',
  WETH: '0x4200000000000000000000000000000000000006',
  USDT: '0x94b008aA00579c1307B0EF2c499aD98a8ce58e58',
  cpPOR_USDC: '0x5eabfc05b51ff2ef32ac8960e30f4a35963143e2',
  USDCe: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
  USDC: '0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85',
  cpFAS_USDT: '0x87181362ba304fec7e5a82ad2b7b503d7ad62639',
  cpPOR_USDT: '0x462c4b2e69a59ff886980f36300c168234b63464',
  cpWINC_USDC: '0x463a9fb7320834b7f8a5c4713434257c8971b9a8',
  cpWINC_USDC_V2: '0xa3aad4020f9c2e336c6bc0461948c94447a335f5',
  cpBAS_USDT: '0xe6be721CCC9552D79bDC0d9CC3638606C3bDaDB5',
}

const arbitrumContracts = {
  deployer: '0xE5Dab8208c1F4cce15883348B72086dBace3e64B',
  cdoFactory: '0xe5441efbda7a3613597eb8e2c42ae4c837ea2149',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  feeReceiver: '0xF40d482D7fc94C30b256Dc7E722033bae68EcF90',
  treasuryMultisig: '0xF40d482D7fc94C30b256Dc7E722033bae68EcF90',
  devLeagueMultisig: '0xF40d482D7fc94C30b256Dc7E722033bae68EcF90',
  proxyAdmin: '0x2A6F03A198d245dAF1fdB330D1D50bCC607Eecab',
  // Same as proxyAdmin
  proxyAdminWithTimelock: '0x2A6F03A198d245dAF1fdB330D1D50bCC607Eecab',
  timelock: '0xB988641E8D493B5BfF65e63819975b6B33477057',
  keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
  keyringWhitelist: '0x98EBa5c607b61aE90Fc29CaD92Ad38A7391f8490',

  // This is an instance of HypernativeBatchPauser
  pauserMultisig: '0x59CDF902b6A964CD5dB04d28f12b774bFB876Be9',
  // This is generated in hypernative dashboard
  hypernativePauserEOA: '0x8c3d89334811e607fe488d1a3ac393a8a8445b32',

  ARB: '0x912CE59144191C1204E64559FE8253a0e49E6548',
  WETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
  tfWIN_USDC: '0xA909a4AA2A6DB0C1A3617A5Cf763ae0d780E5C64',
  USDC: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
  USDT: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
}

exports.IdleTokens = {
  polygon: polygonContracts,
  polygonzk: polygonZKContracts,
  mainnet: mainnetContracts,
  optimism: optimismContracts,
  arbitrum: arbitrumContracts,
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
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
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
  // This should be killed as it's not compatible with latest
  // version of IdleCDO
  // eullevusdc: {
  //   decimals: 6,
  //   // strategyToken it's the strategy itself here
  //   strategyToken: '0xee5ec95ce2c8700a2d152db3249fa13b163f0073',
  //   underlying: mainnetContracts.USDC,
  //   cdoAddr: '0xcb2bd49d4b7874e6597dedfaa3e7b4e01831c5af',
  //   proxyAdmin: mainnetContracts.proxyAdmin,
  //   strategy: '0xee5ec95ce2c8700a2d152db3249fa13b163f0073',
  //   AArewards: '0x0000000000000000000000000000000000000000',
  //   BBrewards: '0x0000000000000000000000000000000000000000',
  //   AATranche: '0x9F94fa97cC2d48315015040708D12aB855283164',
  //   BBTranche: '0x617648B846512E2F49dC21Bf27e4505C285E6977'
  // },
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
  eulerusdcstaking: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x0FE4Fc1301aFe4aFE8C3ac288c3E13cDaCe71b04',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xf615a552c000B114DdAa09636BBF4205De49333c',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x0FE4Fc1301aFe4aFE8C3ac288c3E13cDaCe71b04',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x1AF0294524093BFdF5DA5135853dC2fC678C12f7',
    BBTranche: '0x271db794317B44827EfE81DeC6193fFc277050F6'
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
  eulerdaistaking: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x62aa57dd00c3d77f984379892c857bef58fc7722',
    underlying: mainnetContracts.DAI,
    cdoAddr: '0x264E1552Ee99f57a7D9E1bD1130a478266870C39',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x62aa57dd00c3d77f984379892c857bef58fc7722',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x62Eb6a8c7A555eae3e0B17D42CA9A3299af2787E',
    BBTranche: '0x56263BDE26b72b3e3D26d8e03399a275Aa8Bbfb2'
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
  eulerusdtstaking: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xaf141907c3185bee2d451b5a72b89232b0340652',
    underlying: mainnetContracts.USDT,
    cdoAddr: '0x860B1d25903DbDFFEC579d30012dA268aEB0d621',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0xaf141907c3185bee2d451b5a72b89232b0340652',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6796FCd41e4fb26855Bb9BDD7Cad41128Da1Fd59',
    BBTranche: '0x00B80FCCA0fE4fDc3940295AA213738435B0f94e'
  },
  eulerwethstaking: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x2D29c277Ac61376Fb011DCAFCe03EA3C9485f4c2',
    underlying: mainnetContracts.WETH,
    cdoAddr: '0xec964d06cD71a68531fC9D083a142C48441F391C',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x2D29c277Ac61376Fb011DCAFCe03EA3C9485f4c2',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x2B7Da260F101Fb259710c0a4f2EfEf59f41C0810',
    BBTranche: '0x2e80225f383F858E8737199D3496c5Cf827670a5'
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
  cpfoldai: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0xFcA6b0573034BaAca576ea2Ef675032fB8dF6Cec',
    underlying: mainnetContracts.DAI,
    cdoAddr: '0xDcE26B2c78609b983cF91cCcD43E238353653b0E',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0xFcA6b0573034BaAca576ea2Ef675032fB8dF6Cec',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x1692F6574a6758ADfbD12544e209146dD4510BD7',
    BBTranche: '0xCb980b5A4f5BdB81d0B4b97A9eDe64578ba9D48A'
  },
  cpfolusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x84B2dEaF87A398F25ec5833000F72B6a4906b5AC',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xDBd47989647Aa73f4A88B51f2B5Ff4054De1276a',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x84B2dEaF87A398F25ec5833000F72B6a4906b5AC',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xa0154A44C1C45bD007743FA622fd0Da4f6d67D57',
    BBTranche: '0x7a625a2882C9Fc8DF1463d5E538a3F39B5DBD073'
  },
  cpporusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x931c080c7ed6b3c6988576654e5d56753dc92181',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x1329E8DB9Ed7a44726572D44729427F132Fa290D',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x931c080c7ed6b3c6988576654e5d56753dc92181',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x9CAcd44cfDf22731bc99FaCf3531C809d56BD4A2',
    BBTranche: '0xf85Fd280B301c0A6232d515001dA8B6c8503D714'
  },
  cppordai: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x3687c0F8760371fc1BD1c7bc28695c388CdEd5a0',
    underlying: mainnetContracts.DAI,
    cdoAddr: '0x5dcA0B3Ed7594A6613c1A2acd367d56E1f74F92D',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x3687c0F8760371fc1BD1c7bc28695c388CdEd5a0',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x43eD68703006add5F99ce36b5182392362369C1c',
    BBTranche: '0x38D36353D07CfB92650822D9c31fB4AdA1c73D6E'
  },
  cpfasusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xc8e2Fad99061407e947485c846bd05Eae9DE1991',
    underlying: mainnetContracts.USDT,
    cdoAddr: '0xc4574C60a455655864aB80fa7638561A756C5E61',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0xc8e2Fad99061407e947485c846bd05Eae9DE1991',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x0a6f2449C09769950cFb76f905Ad11c341541f70',
    BBTranche: '0x3Eb6318b8D9f362a0e1D99F6032eDB1C4c602500'
  },
  cpfasusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x16F6bE72882B24527F94c7BCCabF77B62608083b',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xE7C6A4525492395d65e736C3593aC933F33ee46e',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x16F6bE72882B24527F94c7BCCabF77B62608083b',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xdcA1daE87f5c733c84e0593984967ed756579BeE',
    BBTranche: '0xbcC845bB731632eBE8Ac0BfAcdE056170aaaaa06'
  },
  cpwincusdc: { // wincent
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xB9c8d0A004772000eE199c4348f1933AcbFDC1bB',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xd12f9248dEb1D972AA16022B399ee1662d51aD22',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0xB9c8d0A004772000eE199c4348f1933AcbFDC1bB',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x00b51Fc6384A120Eac68bEA38b889Ea92524ab93',
    BBTranche: '0xe6De3A77B4e71356F4E5e52fd695EAD5E5DBcd27'
  },
  // cpfasdai: {
  //   decimals: 18,
  //   // strategyToken it's the strategy itself here
  //   strategyToken: '',
  //   underlying: mainnetContracts.DAI,
  //   cdoAddr: '',
  //   proxyAdmin: mainnetContracts.proxyAdmin,
  //   strategy: '',
  //   AArewards: '0x0000000000000000000000000000000000000000',
  //   BBrewards: '0x0000000000000000000000000000000000000000',
  //   AATranche: '',
  //   BBTranche: ''
  // },
  rfolusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x25e7337037817DD9Bddd0334Ca1591f370518893',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x4bC5E595d2e0536Ea989a7a9741e9EB5c3CAea33',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x25e7337037817DD9Bddd0334Ca1591f370518893',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x5f45A578491A23AC5AEE218e2D405347a0FaFa8E',
    BBTranche: '0x982E46e81E99fbBa3Fb8Af031A7ee8dF9041bb0C'
  },
  rwindai: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x94BcFfc172Af69132BbCE7DF52D567e5ce651dcd',
    underlying: mainnetContracts.DAI,
    cdoAddr: '0xc8c64CC8c15D9aa1F4dD40933f3eF742A7c62478',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x94BcFfc172Af69132BbCE7DF52D567e5ce651dcd',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xd54E5C263298E60A5030Ce2C8ACa7981EaAaED4A',
    BBTranche: '0xD3E4C5C37Ba3185410550B836557B8FA51d5EA3b'
  },
  rwinusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x73f3fb86cb579eeea9d482df2e91b6770a42fd6a',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xf6B692CC9A5421E4C66D32511d65F94c64fbD043',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x73f3fb86cb579eeea9d482df2e91b6770a42fd6a',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x3e041C9980Bc03011cc30491d0c4ccD53602F89B',
    BBTranche: '0x65237B6Fc6E62B05B62f1EbE53eDAadcCd1684Ad'
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
  stmatic: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: mainnetContracts.stMATIC,
    underlying: mainnetContracts.MATIC,
    cdoAddr: '0xF87ec7e1Ee467d7d78862089B92dd40497cBa5B8',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x6110deC9faC2A721c0EEe64B769A7E4cCcf4aa81',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xAEf4FCC4E5F2dc270760063446d4116D24704Ad1',
    BBTranche: '0x077212c69A66261CF7bD1fd3b5C5db7CfFA948Ee'
  },
  morphoaaveusdc: {
    decimals: 6,
    strategyToken: mainnetContracts.maUSDC,
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x9C13Ff045C0a994AF765585970A5818E1dB580F8',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x6c14a1a28dd6dae5734fd960bac0b89a6b401cfd',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x376B2dCF9eBd3067BB89eb6D1020FbE604092212',
    BBTranche: '0x86a40De6d77331788Ba24a85221fb8DBFcBC9bF0'
  },
  morphoaavedai: {
    decimals: 18,
    strategyToken: mainnetContracts.maDAI,
    underlying: mainnetContracts.DAI,
    cdoAddr: '0xDB82dDcb7e2E4ac3d13eBD1516CBfDb7b7CE0ffc',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x9182A7C9D9858d54816baC7e3C049B26d3fc56bB',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x69d87d0056256e3df7Be9b4c8D6429B4b8207C5E',
    BBTranche: '0xB098AF638aF0c4Fa3edb1A24f807E9c22dA0fE73'
  },
  morphoaaveusdt: {
    decimals: 6,
    strategyToken: mainnetContracts.maUSDT,
    underlying: mainnetContracts.USDT,
    cdoAddr: '0x440ceAd9C0A0f4ddA1C81b892BeDc9284Fc190dd',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x57E142278E93d721F3eBD52EC5D2D28484862f32',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x745e005a5dF03bDE0e55be811350acD6316894E1',
    BBTranche: '0xF0C177229Ae1cd41BF48dF6241fae3e6A14A6967'
  },
  morphoaaveweth: {
    decimals: 18,
    strategyToken: mainnetContracts.maWETH,
    underlying: mainnetContracts.WETH,
    cdoAddr: '0xb3F717a5064D2CBE1b8999Fdfd3F8f3DA98339a6',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x9708B5398382EE064A8E718972670351F1c2c860',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6c0c8708e2FD507B7057762739cb04cF01b98d7b',
    BBTranche: '0xd69c52E6AF3aE708EE4b3d3e7C0C5b4CF4d6244B'
  },
  // instastethv2: {
  //   decimals: 18,
  //   strategyToken: mainnetContracts.instaETHv2,
  //   underlying: mainnetContracts.stETH,
  //   cdoAddr: '0xf52834404A51f5af1CDbeEdaA95B60c8B2187ba0',
  //   proxyAdmin: mainnetContracts.proxyAdmin,
  //   strategy: '0xBE0DACE8d62a14D2D872b20462B4725Cc50a1ff6',
  //   AArewards: '0x0000000000000000000000000000000000000000',
  //   BBrewards: '0x0000000000000000000000000000000000000000',
  //   AATranche: '0xbb26dD53dD37f2dC4b91E93C947d6b8683b85279',
  //   BBTranche: '0xC136E01f74FB0DAEfA29f0AAc9c250EF069e684d'
  // },
  instastethv2: {
    decimals: 18,
    strategyToken: mainnetContracts.instaETHv2,
    underlying: mainnetContracts.stETH,
    cdoAddr: '0x8E0A8A5c1e5B3ac0670Ea5a613bB15724D51Fc37',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x00d39058943B4A6F01cb3386A7f44b84ab482c8B',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xdf17c739b666B259DA3416d01f0310a6e429f592',
    BBTranche: '0x990b3aF34dDB502715E1070CE6778d8eB3c8Ea82'
  },
  mmwethbbweth: {
    decimals: 18,
    strategyToken: mainnetContracts.mmWETHbbWETH,
    underlying: mainnetContracts.WETH,
    cdoAddr: '0x260D1E0CB6CC9E34Ea18CE39bAB879d450Cdd706',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x0186e34DE71987303B4eD4a027Ed939a1178A73B',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x10036C2E5C441Cdef24A30134b6dF5ebf116205e',
    BBTranche: '0x3331B21Abb39190a0426ca54D68F9E3E953Eec8e'
  },
  mmusdcsteakusdc: {
    decimals: 6,
    strategyToken: mainnetContracts.mmUSDCsteakUSDC,
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x87E53bE99975DA318056af5c4933469a6B513768',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x937C5122d6fbaddBd74a41E73B9dB6dEb66d515d',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x2B0E31B8EE653D2077db86dea3ACf3F34ae9d5D2',
    BBTranche: '0x7b713B1Cb6EaFD4061064581579ffCCf7DF21545'
  },
  mmwethre7weth: {
    decimals: 18,
    strategyToken: mainnetContracts.mmWETHre7WETH,
    underlying: mainnetContracts.WETH,
    cdoAddr: '0xA8d747Ef758469e05CF505D708b2514a1aB9Cc08',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x4BFD21eBcf0819E8c5A74346517f9Db849208Ac2',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x454bB3cb427B21e1c052A080e21A57753cd6969e',
    BBTranche: '0x20aa3CD83044D2903181f7eF5c2B498a017d1C4A'
  },
  mmwethre7wethfarm: {
    decimals: 18,
    strategyToken: mainnetContracts.mmWETHre7WETH,
    underlying: mainnetContracts.WETH,
    cdoAddr: '0xD071EA5D2575E155E4e9c2234968D1E11B8a920E',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x0f050055b162fEAcA563Ff36fE905c930361dA57',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xb9d321B26095195610707597Aab416925C598aab',
    BBTranche: '0xf529f10Fe24367d3A123Faf0E9D5F6D80980b46f'
  },
  amphorwsteth: {
    decimals: 18,
    strategyToken: mainnetContracts.amprWSTETH,
    underlying: mainnetContracts.wstETH,
    cdoAddr: '0x9e0c5ee5e4B187Cf18B23745FCF2b6aE66a9B52f',
    proxyAdmin: mainnetContracts.proxyAdmin,
    strategy: '0x35df8a95b348dd87167ed00b3421ba15d95ac1c8',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x28D8a22c6689aC1e2DDC43Ca6F85c520457351C1',
    BBTranche: '0xEfC4f43737Fd336fa8A8254454Ced1e421804b16'
  },
  ethenasusde: {
    decimals: 18,
    strategyToken: mainnetContracts.SUSDe,
    underlying: mainnetContracts.USDe,
    cdoAddr: '0x1EB1b47D0d8BCD9D761f52D26FCD90bBa225344C',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x73a99d5383ab115a24b4e3f6def02f7dd0e57b16',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xF3188697Bd35Df73E4293d04A07ebAAf1FfC4018',
    BBTranche: '0xb8d0BE502A8F12Cc5213733285b430A43d07349D'
  },
  gearboxweth: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0xeE4043b3E4fDf830a557Aa78604E16a599701dFA',
    underlying: mainnetContracts.WETH,
    cdoAddr: '0xbc48967C34d129a2ef25DD4dc693Cc7364d02eb9',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0xeE4043b3E4fDf830a557Aa78604E16a599701dFA',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x0f09A04AD551Dd941b589625BD2360FC962FF9f7',
    BBTranche: '0x1223ddeEe77F8F379ea7a49e7650Ff1Ec1e2dE8a'
  },
  gearboxusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x29c794B9a70752c41D65EBcCEF1c1eE697387510',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xdd4D030A4337CE492B55bc5169F6A9568242C0Bc',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x29c794B9a70752c41D65EBcCEF1c1eE697387510',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x450C055a00226F1Eba09E8D9627034565b7C4C8A',
    BBTranche: '0x2a84A042DB06222C486BcB815E961f26599D0dF6'
  },
  creditfasanarausdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xC35D078092872Ec1f2ae82bcd6f0b6b89F0850de',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xf6223C567F21E33e859ED7A045773526E9E3c2D5',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0xC35D078092872Ec1f2ae82bcd6f0b6b89F0850de',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x45054c6753b4Bce40C5d54418DabC20b070F85bE',
    BBTranche: '0xed9cD82076160Bbc5F734D596a039Baf616D44c4',
    queue: '0x0b4F695B05902efc14344d19ED1d0B0E061C8A3E',

    // Euler info:
    eulerGovernor: '0xF02Faf7CFEe786111eaE6747a0c344b48C1eD5E5',
    eulerOracleRouter: '0xBD52853DB7205B57ca99745E91CB77A7BA43708d',
    eulerOracleIdle: '0xfc15ec9c88ca6fe3edd96465e7c4092e57427c62',
    eulerOracleUSD: '0xc9775fb90053119Ac99C67f5536dbC02dFd28b2a',
    eulerIRM: '0x5ceb1A6B4a16e8113665e1f3296fec5586F882Fe',
    // tranche token vault
    eulerVaultTranche: '0xd820C8129a853a04dC7e42C64aE62509f531eE5A',
    // USDC token vault
    eulerVaultUSDC: '0x166d8b62e1748d04edf39d0078f1fe4aa01d475e',

    // Morpho info:
    morphoOracle: '0xd0c30f4e6b3fcf1a9c59ae286e1cd9ecd98eddb9',
    morphoMarketId: '0x060f95069f9cee9d77263f1f9e5295481584cefd97aa7b2fc9e55444d617fd1a'
  },
  creditbastionusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x06975bB418EFFB0029fe278A6fA15B92bb97496F',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x4462eD748B8F7985A4aC6b538Dfc105Fce2dD165',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x06975bB418EFFB0029fe278A6fA15B92bb97496F',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xC49b4ECc14aa31Ef0AD077EdcF53faB4201b724c',
    BBTranche: '0x5B20BddA9457464e156917De7194d17f7f823735',
  },
  creditadaptivefrontierusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xa30bE796FB2BAbF9228359E86A041c14e29f86Fc',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x14B8E918848349D1e71e806a52c13D4e0d3246E0',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0xa30bE796FB2BAbF9228359E86A041c14e29f86Fc',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xae7913c672c7F1f76C2a1a0Ac4de97d082681234',
    BBTranche: '0xff80E0DE1CC54B110632Da8A3296E52590cb2374',
    queue: '0x5eCF8bF9eae51c2FF47FAc8808252FaCd8e36797'
  },
  creditfalconxusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x17E9Ab2992dfecBe779a06A92a6cDB9fE6aEeEf3',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x17E9Ab2992dfecBe779a06A92a6cDB9fE6aEeEf3',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xC26A6Fa2C37b38E549a4a1807543801Db684f99C',
    BBTranche: '0xacbb25b7DD30B6B2F7131865Dc1023622de3b3D6',
    queue: '0x5cC24f44cCAa80DD2c079156753fc1e908F495DC',
    writeoff: '0xf3d8671e662c000AD03d860398932F0644611BDc',

    // Morpho info:
    morphoOracle: '0x52eA2C12734B5bB61e1edf52Bb0f01D9206493Fc',
    morphoMarketId: '0xfc12e6c22618e8dedee4935f13d553271576505bb779667b86f983a90f064e99'
  },
  creditgauntlettestusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x6b3d00FCc1c0fc1e5c45faCe6227F0B7EeBaa285',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x77fc193Fe76EBd897c6e5e29375F4258Bcd61888',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x6b3d00FCc1c0fc1e5c45faCe6227F0B7EeBaa285',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x99e05CDBeAC5D91150935C59FF8e9ba9945d6884',
    BBTranche: '0xA45304708D76fF93aC5168Eb4bBd5d8a534370a4',
    queue: '0x2F0E03cba0Aa6b5490a80FF904328154Af33CB00'
  },
  creditroxusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x3Fc0265E92EeafED0cCd9F8621764Ce0981882cE',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x9cF358aff79DeA96070A85F00c0AC79569970Ec3',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x3Fc0265E92EeafED0cCd9F8621764Ce0981882cE',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xEC6a70F62a83418c7fb238182eD2865F80491a8B',
    BBTranche: '0x53026B3aDb9956Dd4D4C381E1544C998c38D140D',
    queue: '0xBC6cffAFC8F98d7DF780cE05fA55e14781C1C14D',

    morphoOracle: '0x4bAff53CEEb99640447864A1605966D02fDFB661'
  },
  creditflowdeskusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '',
    underlying: mainnetContracts.USDC,
    cdoAddr: '',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '',
    BBTranche: '',
    queue: ''
  },
  creditabraxasusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x93e8Dd7fD35C7C5FbA3Ab2f7a25a6B162fd06E66',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xc222D62345400C0a673222c4F8CF42aA7a83BFAF',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x93e8Dd7fD35C7C5FbA3Ab2f7a25a6B162fd06E66',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6A9daCd6185Acae4Db87cB794D5c8c551fEDe184',
    BBTranche: '0x625fa7f7127181a55ca62e9A247374e6a8845151',
    queue: '0x75a878869F6920C5bB815205cD08F85480791A19'
  },
  creditabraxasv2usdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xE7E13F902Ea13e6EaAa4ed9A2DE5898436D12cbF',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x0Ad21c3Ac4ffE7C1Ed2b1B717cd051DeD365fa32',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0xE7E13F902Ea13e6EaAa4ed9A2DE5898436D12cbF',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6dbDEeF7a188bEaFFC2c57006e5D8edAf0C0e9e6',
    BBTranche: '0xAeC53e87B91bcCB5350244a3b932d89B28De1ea3',
    queue: '0xeBa43518e4fddA8D82Ad711DA3b27717779DBdF7'
  },
  creditpsalionusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x45F427Fe0dCdE43A8D814FE68DC4112805d60b3A',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0x5613A49D10Fed6B7Fa3a6f9b0C3524D8537Da2cF',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x45F427Fe0dCdE43A8D814FE68DC4112805d60b3A',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x20dbc261dc6d190898e974e4aa63f33e73ed01fb',
    BBTranche: '0x54eef41402784a98ed66f66ebb7d21b27bb4278d',
  },
  creditcarpathianweth: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x935976C45a4d5d0Dd1B7a1aBe7241050fE5DD5eb',
    underlying: mainnetContracts.WETH,
    cdoAddr: '0xdb6cAe7c1365219cf3d8D3728e96309CDDDe27F9',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x935976C45a4d5d0Dd1B7a1aBe7241050fE5DD5eb',
    AATranche: '0x1388c0d942B7565637b8F9A06E8063c9e505c7c4',
    BBTranche: '0x7F97740d7253ed0AA765b195b247C3d0Af0Bd502',
    queue: '0x070b87c221aF6Cd77D0052b27a62Ac9D71f021d2'
  },
  creditl1testusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x86d82BE0AFE6438ad1f2DBbb817c348C57718a85',
    underlying: mainnetContracts.USDC,
    cdoAddr: '0xF2cCB7A32cdF7f4350A4194465FC482875f899a8',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x86d82BE0AFE6438ad1f2DBbb817c348C57718a85',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x61a9D031E2C89b48C883ffF46a87Ea37DB16FbC7',
    BBTranche: '0x32F28ebbEB58676153485C74aac609E209b73BeD',
  },
  usualusd0pptest: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x775D6F71Ac19fC9b9618eF42808987E4e5475408',
    underlying: mainnetContracts.USD0pp,
    cdoAddr: '0x7c31fDCa14368E0DA2DA7E518687012287bB90B1',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x775D6F71Ac19fC9b9618eF42808987E4e5475408',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x3A34157DF5F07fF757B599716F41E8DC7829b090',
    BBTranche: '0x228d530C7b3570E5eb7c7D049bFEC45D28e611Fa'
  },
  usualusd0pp: {
    decimals: 18,
    // strategyToken it's the strategy itself here
    strategyToken: '0x1D659F4357e30De73eD2Dc02Ed4e34bCa262dCC8',
    underlying: mainnetContracts.USD0pp,
    cdoAddr: '0x67e04c90877FC63334d420e75f54d7ce1C8bCe01',
    proxyAdmin: mainnetContracts.proxyAdminWithTimelock,
    strategy: '0x1D659F4357e30De73eD2Dc02Ed4e34bCa262dCC8',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x891BDf6580D58337E9557B44dd01D8eaBE07Df15',
    BBTranche: '0xE4EF3FD4eE87fF6EdF20Fd8F92301341a5a52D5b'
  },
};

const trancheErc4626Wrappers = {
  // trancheErc4626WrapperUSDT is used for new wrappers as it uses safeApprove
  cppordai: {
    original: mainnetContracts.trancheErc4626WrapperUSDT,
    cdo: CDOs.cppoldai,
    AATrancheWraper: '0x79c4fE26f3b2809fD29Ec8588242036b8136f32D',
    BBTrancheWraper: '0xA9F908DA2E3Ec7475a743e97Bb5B06081B688aE4',
  },
  cpporusdc: {
    original: mainnetContracts.trancheErc4626WrapperUSDT,
    cdo: CDOs.cpporusdc,
    AATrancheWraper: '0x291eEcab3a2d3f403745968C14edBB227d183636',
    BBTrancheWraper: '0xa35B7A9fe5DC4cD51bA47ACdf67B0f41c893329A',
  },
  cpfasusdt: {
    original: mainnetContracts.trancheErc4626WrapperUSDT,
    cdo: CDOs.cpfasusdt,
    AATrancheWraper: mainnetContracts.trancheErc4626WrapperUSDT,
    BBTrancheWraper: '0x28bC4D9aD73A761049c773038c344F54D906B152',
  },
  cpfoldai: {
    original: mainnetContracts.trancheErc4626Wrapper,
    cdo: CDOs.cpfoldai,
    AATrancheWraper: '0x6CDCf560f228bFf4AbDa74E11842D3E1d5F15189',
    BBTrancheWraper: '0xEd0532E47aa7E7774D2f4D2cE1cA66cD61C3451a',
  },
  cpwinusdc: {
    original: mainnetContracts.trancheErc4626Wrapper,
    cdo: CDOs.cpwinusdc,
    AATrancheWraper: '0x0BD58ca59f2C18F88882562bc8188d9f8939CA68',
    BBTrancheWraper: '0x43b9B5B8fbcb9AD21B54C44f422F3cA33712A3E3',
  },
  lidoBal: {
    original: mainnetContracts.trancheErc4626WrapperBalancerVariant,
    cdo: CDOs.lido,
    BBTrancheWraper: mainnetContracts.trancheErc4626WrapperBalancerVariant,
  },
  lido: {
    original: mainnetContracts.trancheErc4626Wrapper,
    cdo: CDOs.lido,
    BBTrancheWraper: '0x79F05f75df6c156B2B98aC1FBfb3637fc1e6f048',
  },
  eulerusdcstaking: {
    original: mainnetContracts.trancheErc4626Wrapper,
    cdo: CDOs.eulerusdcstaking,
    BBTrancheWraper: '0xc6Ff7AA2CFF3ba1A4a8BC2C324e819c28D7e0495',
  },
  eulerageur: {
    original: mainnetContracts.trancheErc4626Wrapper,
    cdo: CDOs.eulerageur,
    BBTrancheWraper: '0x6aB3CF01b27e507953365DDF70f97da99471706B',
  },
}

const idleTokenErc4626Wrappers = {
  idleusdcjunior: {
    original: mainnetContracts.idleTokenErc4626Wrapper,
    idleToken: '0xDc7777C771a6e4B3A82830781bDDe4DBC78f320e',
    idleTokenWrapper: '0xc3dA79e0De523eEf7AC1e4ca9aBFE3aAc9973133',
  },
  idleusdtjunior: {
    original: mainnetContracts.idleTokenErc4626WrapperUSDT,
    idleToken: '0xfa3AfC9a194BaBD56e743fA3b7aA2CcbED3eAaad',
    idleTokenWrapper: mainnetContracts.idleTokenErc4626WrapperUSDT,
  },
  idledaijunior: {
    original: mainnetContracts.idleTokenErc4626Wrapper,
    idleToken: '0xeC9482040e6483B7459CC0Db05d51dfA3D3068E1',
    idleTokenWrapper: '0x0c80F31B840C6564e6c5E18f386FaD96b63514cA',
  },
}

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
  creditbastionusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x4Ddb301403Ee3C4B4099ED128b34c36d86f6df35',
    underlying: polygonContracts.USDT,
    cdoAddr: '0xF9E2AE779a7d25cDe46FccC41a27B8A4381d4e52',
    proxyAdmin: polygonContracts.proxyAdminWithTimelock,
    strategy: '0x4Ddb301403Ee3C4B4099ED128b34c36d86f6df35',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xaE65d6C295E4a28519182a632FB25b7C1966AED7',
    BBTranche: '0x9429b7B3d830475F59374ece266Df9366a90dE9F',
    queue: '0xeAB324e9450d1EfFa087ccE8eff6C1FB476d60Ff'
  },
};

const optimismCDOs = {
  cpfasusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x8A42DDE5040675C71C09499F63fBa8Ed98fee77B',
    underlying: optimismContracts.USDT,
    cdoAddr: '0x94e399Af25b676e7783fDcd62854221e67566b7f',
    proxyAdmin: optimismContracts.proxyAdmin,
    strategy: '0x8A42DDE5040675C71C09499F63fBa8Ed98fee77B',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x50BA0c3f940f0e851f8e30f95d2A839216EC5eC9',
    BBTranche: '0x7038D2A5323064f7e590EADc0E8833F2613F6317'
  },
  // DEPRECATED
  // cpporusdc: {
  //   decimals: 6,
  //   // strategyToken it's the strategy itself here
  //   strategyToken: '0x2361130282a24421D9fdf2d1072C8edE2a79F108',
  //   underlying: optimismContracts.cpPOR_USDC,
  //   cdoAddr: '0x957572d61DD16662471c744837d4905bC04Bbaeb',
  //   proxyAdmin: optimismContracts.proxyAdmin,
  //   strategy: '0x2361130282a24421D9fdf2d1072C8edE2a79F108',
  //   AArewards: '0x0000000000000000000000000000000000000000',
  //   BBrewards: '0x0000000000000000000000000000000000000000',
  //   AATranche: '0xE422ca30eCC45Fc45e5ADD79E54505345F0cd482',
  //   BBTranche: '0x56A4283a4CE7202672A1518340732d5ffC511c0b'
  // },
  cpporusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x5d4E705315ACa451Db40bf7c067077C768B3FFd0',
    underlying: optimismContracts.USDT,
    cdoAddr: '0x8771128e9E386DC8E4663118BB11EA3DE910e528',
    proxyAdmin: optimismContracts.proxyAdmin,
    strategy: '0x5d4E705315ACa451Db40bf7c067077C768B3FFd0',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x8552801C75C4f2b1Cac088aF352193858B201D4E',
    BBTranche: '0xafbAeA12DE33bF6B44105Eceecec24B29163077c'
  },
  // DEPRECATED
  // cpwincusdc: {
  //   decimals: 6,
  //   // strategyToken it's the strategy itself here
  //   strategyToken: '0x7bE5622b27ceb9f2f3776fa5c8e3BA23Db65Ced7',
  //   underlying: optimismContracts.cpWINC_USDC,
  //   cdoAddr: '0xa26b308B2386DBd906Cf1F8a653ca7d758f301B3',
  //   proxyAdmin: optimismContracts.proxyAdmin,
  //   strategy: '0x7bE5622b27ceb9f2f3776fa5c8e3BA23Db65Ced7',
  //   AArewards: '0x0000000000000000000000000000000000000000',
  //   BBrewards: '0x0000000000000000000000000000000000000000',
  //   AATranche: '0xb00BbFD1bD0ee3EefF953FA02cdBe4A55BaaC55f',
  //   BBTranche: '0x0BD3cC920926472606bAe4CE479430df18E99F75'
  // },
  cpwincusdcv2: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xB144eE58679e15f1b25A5F6EfcEBDd0AB8c8BEF5',
    underlying: optimismContracts.USDC,
    cdoAddr: '0xe49174F0935F088509cca50e54024F6f8a6E08Dd',
    proxyAdmin: optimismContracts.proxyAdmin,
    strategy: '0xB144eE58679e15f1b25A5F6EfcEBDd0AB8c8BEF5',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6AB470a650E1E0E68b8D1C0f154E78ca1a7147BF',
    BBTranche: '0xB1aD1E9309e5f10982d9bf480bC241580ccc4b02'
  },
  cpbasusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x98c1E0261Fe4C4c701Cc509Cce2168084944bA4B',
    underlying: optimismContracts.USDT,
    cdoAddr: '0x67D07aA415c8eC78cbF0074bE12254E55Ad43f3f',
    proxyAdmin: optimismContracts.proxyAdmin,
    strategy: '0x98c1E0261Fe4C4c701Cc509Cce2168084944bA4B',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x834cB085Ffdce6256C2aEe4a63Bc878870Ff04d',
    BBTranche: '0x9837cC130FB339FAB85Dc09E9de6343b3324246F'
  },
  // credittestusdc: {
  //   decimals: 6,
  //   // strategyToken it's the strategy itself here
  //   strategyToken: '0x6C748E4ea9f15e9c4121b90b5e5689c4deE3a938',
  //   underlying: optimismContracts.USDC,
  //   cdoAddr: '0x0581f1F01E05b77612Feaf529da3E048E1424A7E',
  //   proxyAdmin: optimismContracts.proxyAdminWithTimelock,
  //   strategy: '0x6C748E4ea9f15e9c4121b90b5e5689c4deE3a938',
  //   AArewards: '0x0000000000000000000000000000000000000000',
  //   BBrewards: '0x0000000000000000000000000000000000000000',
  //   AATranche: '0x55cf0BB9F893De8000D4d63F5c621283eE930e59',
  //   BBTranche: '0x6e2a21F6fEC6f2093503AB1a12EB6eF1e3BA89F1'
  // },
  credittestsamusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x8186AbBDF9AF3a1fc59A7C5BC34bab66a2e7bEF2',
    underlying: optimismContracts.USDC,
    cdoAddr: '0x7F70Ec0bdc89f0D61e108Afe921311205b4C3431',
    proxyAdmin: optimismContracts.proxyAdmin,
    strategy: '0x8186AbBDF9AF3a1fc59A7C5BC34bab66a2e7bEF2',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xfA6bA4b504814f3fB524Ea506c79D76077E5D540',
    BBTranche: '0xe89577e5687bB7a1f78739452Ec99907aF23aD36',
    queue: '0xB73F90123919780ff5fCd50bf1aFF57F3b777578'
  },
  creditmaventestusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x8C1B4A409098b5326E3103458bdFE23eEEB1Aa5F',
    underlying: optimismContracts.USDC,
    cdoAddr: '0xD7d76180e12D53b6c4d835cb0F5e3df3732055a3',
    proxyAdmin: optimismContracts.proxyAdminWithTimelock,
    strategy: '0x8C1B4A409098b5326E3103458bdFE23eEEB1Aa5F',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x3353348Fa9526Bf76569B93d04d731cb7B46B343',
    BBTranche: '0xa9976626918b8D788E8be8b83F7584479Bf1F0e9'
  },
  creditfalcontestusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x58BA1463fB0a781571079859D6fcdbc00b50cD55',
    underlying: optimismContracts.USDC,
    cdoAddr: '0x34f54d3Dd46Fd9bef92B54c3CDe526c54F62452d',
    proxyAdmin: optimismContracts.proxyAdmin,
    strategy: '0x58BA1463fB0a781571079859D6fcdbc00b50cD55',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x5e8cd1a018DB46f7FA47925C22E8e3325EaC1923',
    BBTranche: '0xE09736A41898e63A2F32cE100878f260d066b868',
    queue: '0x07EE2F1272914e869D0E47E08b5a10007b8FdF31'
  },
  creditfaxusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xca0E467Cf2d0011EF3424D0a2c1999009991405a',
    underlying: optimismContracts.USDC,
    cdoAddr: '0x218Fcd276d03A2942e97833c92b66Eb3447b4309',
    proxyAdmin: optimismContracts.proxyAdminWithTimelock,
    strategy: '0xca0E467Cf2d0011EF3424D0a2c1999009991405a',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x62426336067c37c10A681Da6275c01D373AbC7E0',
    BBTranche: '0xC55Dc4592dcdBAD5EF4bc0Dfa87745791d041A82',
    queue: '0x0D81b042bB9939B4d32CDf7861774c442A2685CE'
  },
  creditfaxusdcfinal: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x2bfcaC093774Ec1CbBeA994334C69279caEB4E6B',
    underlying: optimismContracts.USDC,
    cdoAddr: '0xBd9Ad85Ab0115ceFF7A1c51652D3DE3171dA1E56',
    proxyAdmin: optimismContracts.proxyAdminWithTimelock,
    strategy: '0x2bfcaC093774Ec1CbBeA994334C69279caEB4E6B',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x4898A7a2039f583170AbEf343a6110e68E4dd9CD',
    BBTranche: '0xEFc4dFb27a736065F5151c8d27FfD95cCA6092D4',
    queue: '0x42Ab464A3de110ac91cbdfCaa69B0E0C4f3a59A1'
  },
  creditfaxusdcfinalfinal: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x2BCf124aa4f7F32f0fe54f498d924B934C942B31',
    underlying: optimismContracts.USDC,
    cdoAddr: '0xD2c0D848aA5AD1a4C12bE89e713E70B73211989B',
    proxyAdmin: optimismContracts.proxyAdminWithTimelock,
    strategy: '0x2BCf124aa4f7F32f0fe54f498d924B934C942B31',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x24e16F9Fad32891f8bA69cE8fEdd273A2649331A',
    BBTranche: '0xB967000B6bB3FCb17018030761dA9EA2b7E79c3B',
    queue: '0x463465c334742D72907CA5fB97db44688B4EC3dC'
  },
};

const arbitrumCDOs = {
  tfwinusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: arbitrumContracts.tfWIN_USDC,
    underlying: arbitrumContracts.USDC,
    cdoAddr: '0x6b8A1e78Ac707F9b0b5eB4f34B02D9af84D2b689',
    proxyAdmin: arbitrumContracts.proxyAdmin,
    strategy: '0xB5D4D8d9122Bf252B65DAbb64AaD68346405443C',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6AaB2db845b23729aF1F5B0902Ff4BDc32BBf948',
    BBTranche: '0x1FdAF221fF3929e86266D6A5930fa7263c1bD4DF'
  },
  creditbastionusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x341c6418005feFad6F1e0984B411Ca73D63C8686',
    underlying: arbitrumContracts.USDC,
    cdoAddr: '0x0E90CF05aCB23D8DFa856A74e74a165C6A7aF8b3',
    proxyAdmin: arbitrumContracts.proxyAdminWithTimelock,
    strategy: '0x341c6418005feFad6F1e0984B411Ca73D63C8686',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0xd7d7d88D753d05862B9c13d8b2637d2A03dFA445',
    BBTranche: '0x0968b9706F8a94854CDe67Cb44e70f4d1b0E760b',
    queue: '0x466cFDfF869666941CdB89daa412c3CddC55D6c1'
  },
  creditbastionusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x5b11507F8A91005aD1591F54ef64133AabA6d06E',
    underlying: arbitrumContracts.USDT,
    cdoAddr: '0x3919396Cd445b03E6Bb62995A7a4CB2AC544245D',
    proxyAdmin: arbitrumContracts.proxyAdminWithTimelock,
    strategy: '0x5b11507F8A91005aD1591F54ef64133AabA6d06E',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x97F476F664A95106931f78113489e0361Cf1c9Fa',
    BBTranche: '0x42A2f36EC49dD9AF7928cF2Ec46E06866292495B',
    queue: '0x133F1C751f25C2AAf0E83f0609A67074915144A4'
  },
};

const polygonZKCDOs = {
  cpfasusdc: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0x73318bF57Fa6A4a97e0140e5CfF8219755FcDdbc',
    underlying: polygonZKContracts.USDC,
    cdoAddr: '0x8890957F80d7D771337f4ce42e15Ec40388514f1',
    proxyAdmin: polygonZKContracts.proxyAdmin,
    strategy: '0x73318bF57Fa6A4a97e0140e5CfF8219755FcDdbc',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x3Ed123E94C95A5777149AeEc50F4C956b29EcceC',
    BBTranche: '0xBF78b393d14A90B52cdc2325e11c92F24f2F54F3'
  },
  cpporusdt: {
    decimals: 6,
    // strategyToken it's the strategy itself here
    strategyToken: '0xB5D4D8d9122Bf252B65DAbb64AaD68346405443C',
    underlying: polygonZKContracts.USDT,
    cdoAddr: '0x6b8A1e78Ac707F9b0b5eB4f34B02D9af84D2b689',
    proxyAdmin: polygonZKContracts.proxyAdmin,
    strategy: '0xB5D4D8d9122Bf252B65DAbb64AaD68346405443C',
    AArewards: '0x0000000000000000000000000000000000000000',
    BBrewards: '0x0000000000000000000000000000000000000000',
    AATranche: '0x6AaB2db845b23729aF1F5B0902Ff4BDc32BBf948',
    BBTranche: '0x1FdAF221fF3929e86266D6A5930fa7263c1bD4DF'
  },
}

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
  eulerusdcstaking: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleEulerStakingStrategy',
    strategyParams: [
      mainnetContracts.eUSDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      mainnetContracts.eUSDCStaking, // _stakingRewards
      'owner', // owner address
    ],
    cdo: CDOs.eulerusdcstaking,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '50000000',
    isAYSActive: true,
    // cpwinusdc has the latest implementation
    proxyCdoAddress: CDOs.cpwinusdc.cdoAddr,
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
    cdo: CDOs.eulerusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdc.cdoAddr,
  },
  eulerusdtstaking: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    strategyName: 'IdleEulerStakingStrategy',
    strategyParams: [
      mainnetContracts.eUSDT, // _strategyToken
      mainnetContracts.USDT, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      mainnetContracts.eUSDTStaking, // _stakingRewards
      'owner', // owner address
    ],
    cdo: CDOs.eulerusdtstaking,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '50000000',
    isAYSActive: true,
    // cpwinusdc has the latest implementation
    proxyCdoAddress: CDOs.cpwinusdc.cdoAddr,
  },
  eulerwethstaking: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'IdleEulerStakingStrategy',
    strategyParams: [
      mainnetContracts.eWETH, // _strategyToken
      mainnetContracts.WETH, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      mainnetContracts.eWETHStaking, // _stakingRewards
      'owner', // owner address
    ],
    cdo: CDOs.eulerwethstaking,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '50000000',
    isAYSActive: true,
    // cpwinusdc has the latest implementation
    proxyCdoAddress: CDOs.cpwinusdc.cdoAddr,
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
  eulerdaistaking: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleEulerStakingStrategyPSM',
    strategyParams: [
      mainnetContracts.eUSDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      mainnetContracts.eulerMain, // _euler
      mainnetContracts.eUSDCStaking, // _stakingRewards
      'owner', // owner address
    ],
    cdo: CDOs.eulerdaistaking,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '50000000',
    isAYSActive: true,
    // cpwinusdc has the latest implementation
    proxyCdoAddress: CDOs.eulerusdcstaking.cdoAddr,
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
  cpfoldai: { // wintermute pool with DAI as underlying
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleClearpoolPSMStrategy',
    strategyParams: [
      mainnetContracts.cpFOL_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpfoldai,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: '',
  },
  cpfolusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleClearpoolStrategy',
    strategyParams: [
      mainnetContracts.cpFOL_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpfolusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.cpwinusdc.cdoAddr,
  },
  cpporusdc: { // portofino pool
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleClearpoolStrategy',
    strategyParams: [
      mainnetContracts.cpPOR_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpporusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.lido.cdoAddr,
  },
  cppordai: { // wintermute pool with DAI as underlying
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleClearpoolPSMStrategy',
    strategyParams: [
      mainnetContracts.cpPOR_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cppordai,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.lido.cdoAddr,
  },
  cpfasusdt: { // fasanara usdt pool
    decimals: 6,
    underlying: mainnetContracts.USDT,
    strategyName: 'IdleClearpoolStrategy',
    strategyParams: [
      mainnetContracts.cpFAS_USDT, // _strategyToken
      mainnetContracts.USDT, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpfasusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.lido.cdoAddr,
  },
  cpfasusdc: { // fasanara usdc pool
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleClearpoolStrategy',
    strategyParams: [
      mainnetContracts.cpFAS_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpfasusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.lido.cdoAddr,
  },
  cpfasdai: { // fasanara usdc pool via psm
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleClearpoolPSMStrategy',
    strategyParams: [
      mainnetContracts.cpFAS_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    // cdo: CDOs.cpfasdai,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.lido.cdoAddr,
  },
  cpwincusdc: { // wincent usdc pool
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleClearpoolStrategy',
    strategyParams: [
      mainnetContracts.cpWINC_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.cpwincusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '40000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.cpfasusdc.cdoAddr,
  },
  // Ribbon Lend
  rwindai: { // wintermute pool with DAI as underlying
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'IdleRibbonPSMStrategy',
    strategyParams: [
      mainnetContracts.rWIN_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.rwindai,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.cpfoldai.cdoAddr,
  },
  rwinusdc: { // wintermute pool
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleRibbonStrategy',
    strategyParams: [
      mainnetContracts.rWIN_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    cdo: CDOs.rwinusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.cpwinusdc.cdoAddr,
  },
  rfolusdc: { // folkvang pool
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleRibbonStrategy',
    strategyParams: [
      mainnetContracts.rFOL_USDC, // _strategyToken
      mainnetContracts.USDC, // _underlyingToken
      'owner', // owner address
      mainnetContracts.univ2Router
    ],
    // cdo: CDOs.rfolusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '200000000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.cpwinusdc.cdoAddr,
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
  // Euler leverage
  eullevusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleLeveragedEulerStrategy',
    strategyParams: [
      mainnetContracts.eulerMain,
      mainnetContracts.eUSDC,
      mainnetContracts.dUSDCEul,
      mainnetContracts.USDC,
      'owner', // owner address
      mainnetContracts.eulerDistributor,
      mainnetContracts.univ3Router,
      ethers.utils.solidityPack(
        ['address', 'uint24', 'address', 'uint24', 'address'],
        [
          mainnetContracts.EUL,
          10000,
          mainnetContracts.WETH,
          3000,
          mainnetContracts.USDC
        ]
      ), // path
      (1.013 * 1e18).toString(), // initial target health -> ~ 15x leverage
    ],
    // cdo: CDOs.eullevusdc,
    cdoVariant: 'IdleCDOLeveregedEulerVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '2000000',
    isAYSActive: true,
    proxyCdoAddress: '', // deploy new instance
  },
  // stMATIC
  stmatic: {
    decimals: 18,
    underlying: mainnetContracts.MATIC,
    strategyName: 'IdlePoLidoStrategy',
    strategyParams: [
      'owner' // owner address
    ],
    cdo: CDOs.stmatic,
    cdoVariant: 'IdleCDOPoLidoVariant',
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

  // Morpho
  morphoaaveusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'MorphoAaveV2SupplyVaultStrategy',
    strategyParams: [
      mainnetContracts.maUSDC,
      mainnetContracts.USDC,
      'owner', // owner address
      mainnetContracts.aUSDC,
      // mainnetContracts.MORPHO,
      addr0, // MORPHO is non transferrable yet
    ],
    cdo: CDOs.morphoaaveusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdcstaking.cdoAddr,
  },
  morphoaavedai: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    strategyName: 'MorphoAaveV2SupplyVaultStrategy',
    strategyParams: [
      mainnetContracts.maDAI,
      mainnetContracts.DAI,
      'owner', // owner address
      mainnetContracts.aDAI,
      // mainnetContracts.MORPHO,
      addr0, // MORPHO is non transferrable yet
    ],
    cdo: CDOs.morphoaavedai,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdcstaking.cdoAddr,
  },
  morphoaaveusdt: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    strategyName: 'MorphoAaveV2SupplyVaultStrategy',
    strategyParams: [
      mainnetContracts.maUSDT,
      mainnetContracts.USDT,
      'owner', // owner address
      mainnetContracts.aUSDT,
      // mainnetContracts.MORPHO,
      addr0, // MORPHO is non transferrable yet
    ],
    cdo: CDOs.morphoaaveusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdcstaking.cdoAddr,
  },
  morphoaaveweth: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'MorphoAaveV2SupplyVaultStrategy',
    strategyParams: [
      mainnetContracts.maWETH,
      mainnetContracts.WETH,
      'owner', // owner address
      mainnetContracts.aWETH,
      // mainnetContracts.MORPHO,
      addr0, // MORPHO is non transferrable yet
    ],
    cdo: CDOs.morphoaaveweth,
    ...baseCDOArgs,
    AARatio: '20000',
    isAYSActive: true,
    proxyCdoAddress: CDOs.eulerusdcstaking.cdoAddr,
  },

  // Instadapp lite v2 stETH vault
  instastethv2: {
    decimals: 18,
    underlying: mainnetContracts.stETH,
    strategyName: 'InstadappLiteETHV2Strategy',
    strategyParams: [
      'owner', // owner address
    ],
    cdo: CDOs.instastethv2,
    cdoVariant: 'IdleCDOInstadappLiteVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '600',
    isAYSActive: true,
    proxyCdoAddress: '', // deploy new instance
  },

  // Amphor
  amphorwsteth: {
    decimals: 18,
    underlying: mainnetContracts.wstETH,
    strategyName: 'AmphorStrategy',
    strategyParams: [
      mainnetContracts.amprWSTETH,
      mainnetContracts.wstETH,
      'owner', // owner address
    ],
    // cdo: CDOs.amphorwsteth,
    cdoVariant: 'IdleCDOAmphorVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: '', // deploy new instance
  },
  amphorusdc: {
    decimals: 18,
    underlying: mainnetContracts.USDC,
    strategyName: 'AmphorStrategy',
    strategyParams: [
      mainnetContracts.amprUSDC,
      mainnetContracts.USDC,
      'owner', // owner address
    ],
    // cdo: CDOs.amphorusdc,
    cdoVariant: 'IdleCDOAmphorVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: CDOs.amphorwsteth.cdoAddr
  },

  // Metamorpho
  mmWETHbbWETH: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'MetaMorphoStrategy',
    strategyParams: [
      mainnetContracts.mmWETHbbWETH,
      mainnetContracts.WETH,
      'owner', // owner address
      mainnetContracts.mmSnippets,
      [
        mainnetContracts.MORPHO,
        mainnetContracts.wstETH,
      ]
    ],
    cdo: CDOs.mmwethbbweth,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: CDOs.morphoaaveweth.cdoAddr, // deploy new instance
    urds: [
      '0x678dDC1d07eaa166521325394cDEb1E4c086DF43', // MORPHO
      '0x2EfD4625d0c149EbADf118EC5446c6de24d916A4' // WSTETH
    ]
  },
  mmUSDCsteakUSDC: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'MetaMorphoStrategy',
    strategyParams: [
      mainnetContracts.mmUSDCsteakUSDC,
      mainnetContracts.USDC,
      'owner', // owner address
      mainnetContracts.mmSnippets,
      [
        mainnetContracts.MORPHO,
      ]
    ],
    cdo: CDOs.mmusdcsteakusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: CDOs.morphoaaveweth.cdoAddr, // deploy new instance
    urds: [
      '0x678dDC1d07eaa166521325394cDEb1E4c086DF43', // MORPHO
      '0x2EfD4625d0c149EbADf118EC5446c6de24d916A4' // WSTETH
    ]
  },
  mmWETHre7WETH: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'MetaMorphoStrategy',
    strategyParams: [
      mainnetContracts.mmWETHre7WETH,
      mainnetContracts.WETH,
      'owner', // owner address
      mainnetContracts.mmSnippets,
      [
        mainnetContracts.MORPHO,
        mainnetContracts.USDC,
        mainnetContracts.SWISE,
        mainnetContracts.BTRFLY,
      ]
    ],
    rewardsData: [
      {
        id: 0,
        reward: mainnetContracts.MORPHO,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0x678dDC1d07eaa166521325394cDEb1E4c086DF43',
        marketId: '0x698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115',
        uniV3Path: '0x',
      },
      {
        id: 1,
        reward: mainnetContracts.MORPHO,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0x678dDC1d07eaa166521325394cDEb1E4c086DF43',
        marketId: '0xd5211d0e3f4a30d5c98653d988585792bb7812221f04801be73a44ceecb11e89',
        uniV3Path: '0x',
      },
      {
        id: 0,
        reward: mainnetContracts.USDC,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0xb5b17231e2c89ca34ce94b8cb895a9b124bb466e',
        marketId: '0x698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115',
        uniV3Path: ethers.utils.solidityPack(
          ['address', 'uint24', 'address'],
          // 0.05% fee tier
          [mainnetContracts.USDC, 500, mainnetContracts.WETH]
        ),
      },
      {
        id: 0,
        reward: mainnetContracts.SWISE,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0xfd9b178257ae397a674698834628262fd858aad3',
        marketId: '0xd5211d0e3f4a30d5c98653d988585792bb7812221f04801be73a44ceecb11e89',
        uniV3Path: ethers.utils.solidityPack(
          ['address', 'uint24', 'address'],
          // 0.3% fee tier
          [mainnetContracts.SWISE, 3000, mainnetContracts.WETH]
        ),
      },
      {
        id: 0,
        reward: mainnetContracts.BTRFLY,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0xfd5ee44774a162ec25dbf3a4cff6242a1fa5e338',
        marketId: '0x8bbd1763671eb82a75d5f7ca33a0023ffabdd9d1a3d4316f34753685ae988e80',
        uniV3Path: ethers.utils.solidityPack(
          ['address', 'uint24', 'address'],
          // 0.3% fee tier
          [mainnetContracts.BTRFLY, 10000, mainnetContracts.WETH]
        ),
      },
    ],
    urds: [
      '0x678dDC1d07eaa166521325394cDEb1E4c086DF43', // MORPHO
      '0xb5b17231e2c89ca34ce94b8cb895a9b124bb466e', // WSTETH
      '0xfd9b178257ae397a674698834628262fd858aad3', // SWISE
      '0xfd5ee44774a162ec25dbf3a4cff6242a1fa5e338', // BTRFLY
    ],
    cdo: CDOs.mmwethre7weth,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: CDOs.morphoaaveweth.cdoAddr, // deploy new instance
  },
  mmWETHre7WETHFarm: {
    farmTranche: true,
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'MetaMorphoStrategy',
    strategyParams: [
      mainnetContracts.mmWETHre7WETH,
      mainnetContracts.WETH,
      'owner', // owner address
      mainnetContracts.mmSnippets,
      [
        mainnetContracts.MORPHO,
        mainnetContracts.USDC,
        mainnetContracts.SWISE,
        mainnetContracts.BTRFLY,
      ]
    ],
    rewardsData: [
      {
        id: 0,
        reward: mainnetContracts.MORPHO,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0x678dDC1d07eaa166521325394cDEb1E4c086DF43',
        marketId: '0x698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115',
        uniV3Path: '0x',
      },
      {
        id: 1,
        reward: mainnetContracts.MORPHO,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0x678dDC1d07eaa166521325394cDEb1E4c086DF43',
        marketId: '0xd5211d0e3f4a30d5c98653d988585792bb7812221f04801be73a44ceecb11e89',
        uniV3Path: '0x',
      },
      {
        id: 0,
        reward: mainnetContracts.USDC,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0xb5b17231e2c89ca34ce94b8cb895a9b124bb466e',
        marketId: '0x698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115',
        uniV3Path: ethers.utils.solidityPack(
          ['address', 'uint24', 'address'],
          // 0.05% fee tier
          [mainnetContracts.USDC, 500, mainnetContracts.WETH]
        ),
      },
      {
        id: 0,
        reward: mainnetContracts.SWISE,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0xfd9b178257ae397a674698834628262fd858aad3',
        marketId: '0xd5211d0e3f4a30d5c98653d988585792bb7812221f04801be73a44ceecb11e89',
        uniV3Path: ethers.utils.solidityPack(
          ['address', 'uint24', 'address'],
          // 0.3% fee tier
          [mainnetContracts.SWISE, 3000, mainnetContracts.WETH]
        ),
      },
      {
        id: 0,
        reward: mainnetContracts.BTRFLY,
        sender: '0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143',
        urd: '0xfd5ee44774a162ec25dbf3a4cff6242a1fa5e338',
        marketId: '0x8bbd1763671eb82a75d5f7ca33a0023ffabdd9d1a3d4316f34753685ae988e80',
        uniV3Path: ethers.utils.solidityPack(
          ['address', 'uint24', 'address'],
          // 0.3% fee tier
          [mainnetContracts.BTRFLY, 10000, mainnetContracts.WETH]
        ),
      },
    ],
    urds: [
      '0x678dDC1d07eaa166521325394cDEb1E4c086DF43', // MORPHO
      '0xb5b17231e2c89ca34ce94b8cb895a9b124bb466e', // WSTETH
      '0xfd9b178257ae397a674698834628262fd858aad3', // SWISE
      '0xfd5ee44774a162ec25dbf3a4cff6242a1fa5e338', // BTRFLY
    ],
    cdo: CDOs.mmwethre7wethfarm,
    ...baseCDOArgs,
    AARatio: '100000',
    limit: '0',
    isAYSActive: false,
    proxyCdoAddress: CDOs.mmwethre7weth.cdoAddr,
  },
  ethenasusde: {
    decimals: 18,
    underlying: mainnetContracts.USDe,
    strategyName: 'EthenaSusdeStrategy',
    strategyParams: [
      mainnetContracts.SUSDe,
      mainnetContracts.USDe,
      'owner', // owner address
    ],
    cdo: CDOs.ethenasusde,
    cdoVariant: 'IdleCDOEthenaVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: ''
  },
  gearboxweth: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'GearboxStrategy',
    strategyParams: [
      mainnetContracts.dWETH,
      mainnetContracts.WETH,
      'owner', // owner address
      mainnetContracts.sdWETH,
      ethers.utils.solidityPack(
        ['address', 'uint24', 'address'],
        // 1% fee tier
        [mainnetContracts.GEAR, 10000, mainnetContracts.WETH]
      )
    ],
    cdo: CDOs.gearboxweth,
    cdoVariant: 'IdleCDOGearboxVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: ''
  },
  gearboxusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'GearboxStrategy',
    strategyParams: [
      mainnetContracts.dUSDC,
      mainnetContracts.USDC,
      'owner', // owner address
      mainnetContracts.sdUSDC,
      ethers.utils.solidityPack(
        ['address', 'uint24', 'address', 'uint24', 'address'],
        // 1% fee tier
        [mainnetContracts.GEAR, 10000, mainnetContracts.WETH, 500, mainnetContracts.USDC]
      )
    ],
    cdo: CDOs.gearboxusdc,
    cdoVariant: 'IdleCDOGearboxVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: true,
    proxyCdoAddress: CDOs.gearboxweth.cdoAddr
  },
  creditfasanarausdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // fin wallet
      '0xB0b621b2911F44548233e9437F256942dC16694A', // borrower
      'Fasanara', // borrower name
      0,
    ],
    cdo: CDOs.creditfasanarausdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params 
    epochDuration: '604800', // 7 days
    bufferPeriod: '0', // manually managed buffer period
    // // ## instant params
    // instantWithdrawDelay: '86400', // 1 days
    // instantWithdrawAprDelta: 1e18.toString(),
    // disableInstantWithdraw: true,
    // ## keyring params
    // keyring: '0xD18d17791f2071Bf3C855bA770420a9EdEa0728d',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // #########
    proxyCdoAddress: ''
  },
  creditbastionusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xF381ee632bF26d57f6d5F8717bA573aED835820a', // borrower
      'Bastion', // borrower name
      10e18.toString(), // intialApr 10%
    ],
    cdo: CDOs.creditbastionusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '1209600', // 14 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: false,
    proxyCdoAddress: ''
  },
  creditadaptivefrontierusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xaAeD5a7D6c04025f0Dda7e6b47275db1F1b2b7d5', // borrower
      'Adaptive Frontier', // borrower name
      13e18.toString(), // intialApr 13%
    ],
    cdo: CDOs.creditadaptivefrontierusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '604800', // 7 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 7304190,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: CDOs.creditbastionusdc.cdoAddr,
  },
  creditgauntlettestusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0x920c04BeA067288C8Fd2ebc5dDcF5Cc0ef9542E2', // manager
      '0x920c04BeA067288C8Fd2ebc5dDcF5Cc0ef9542E2', // borrower
      'GauntletTest', // borrower name
      10e18.toString(), // intialApr
    ],
    cdo: CDOs.creditgauntlettestusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '600', // 10 minutes
    bufferPeriod: '600', // 10 minutes
    // ## instant params values
    instantWithdrawDelay: '300', // 5 minutes
    instantWithdrawAprDelta: 0.9e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: addr0,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    hypernative: false,
    proxyCdoAddress: CDOs.creditfalconxusdc.cdoAddr,
  },
  creditroxusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0x2b8D601091a1d43Cf634222024961599eE3878A7', // borrower
      'RockawayX', // borrower name
      10e18.toString(), // intialApr
    ],
    cdo: CDOs.creditroxusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '2592000', // 30 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 5e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 16310000,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    hypernative: true,
    proxyCdoAddress: CDOs.creditgauntlettestusdc.cdoAddr,
  },
  creditfalconxusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0x1fb0f3602F52e2420aCff5CF04DBfDE96378Df58', // manager
      '0x653F71339144e8641A645758F4df4e317Fe998A3', // borrower
      'FalconX', // borrower name
      0e18.toString(), // intialApr - redacted
    ],
    cdo: CDOs.creditfalconxusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '864000', // 10 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 18,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: '',
  },
  creditabraxasusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xb99a2c4C1C4F1fc27150681B740396F6CE1cBcF5', // borrower
      'Abraxas Capital Management', // borrower name
      9e18.toString(), // intialApr
    ],
    cdo: CDOs.creditabraxasusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '604800', // 7 days
    bufferPeriod: '86400', // 1 day
    // ## instant params values
    instantWithdrawDelay: '86400', // 1 day
    instantWithdrawAprDelta: 5e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 13083170,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    hypernative: true,
    proxyCdoAddress: CDOs.creditroxusdc.cdoAddr,
  },
  creditabraxasv2usdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0x04B760fEccCbc41f7bB8f785dbdc0dc769FDc27a', // borrower
      'Abraxas Capital Management', // borrower name
      9e18.toString(), // intialApr
    ],
    cdo: CDOs.creditabraxasv2usdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '604800', // 7 days
    bufferPeriod: '86400', // 1 day
    // ## instant params values
    instantWithdrawDelay: '86400', // 1 day
    instantWithdrawAprDelta: 5e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 13083170,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    hypernative: true,
    proxyCdoAddress: CDOs.creditabraxasusdc.cdoAddr,
  },
  creditpsalionusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0x0CA17Dd6a7A18fa47e350948B97Ae02B9F3CD67b', // manager
      '0x2D03Ed8e16D53bB33310f5dAcB4269d25Ed06354', // borrower
      'Psalion', // borrower name
      10e18.toString(), // intialApr
    ],
    cdo: CDOs.creditpsalionusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '604800', // 7 days
    bufferPeriod: '172800', // 2 day
    // ## instant params values
    instantWithdrawDelay: '172800', // 2 day
    instantWithdrawAprDelta: 5e18.toString(),
    disableInstantWithdraw: true,
    // ## keyring params
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 16003355,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: false,
    writeoff: false,
    hypernative: true,
    proxyCdoAddress: CDOs.creditfalconxusdc.cdoAddr,
  },
  creditcarpathianweth: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.WETH,
      'owner', // owner address
      '0x77479a74abdFe9ACb6626b15950b4cC5E3Fe6414', // manager
      '0x10a1960615d61AFbDD00A7AbE0B1975A650C617f', // borrower
      'Carpathian', // borrower name
      14e18.toString(), // intialApr
    ],
    cdo: CDOs.creditcarpathianweth,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '604800', // 7 days
    bufferPeriod: '86400', // 1 day
    // ## instant params values
    instantWithdrawDelay: '86400', // 1 day
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 16003355,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    writeoff: false,
    hypernative: true,
    proxyCdoAddress: CDOs.creditfalconxusdc.cdoAddr,
  },
  creditl1testusdc: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      mainnetContracts.USDC,
      'owner', // owner address
      '0x8c90CEC0e380D1037b46Afc35c9461672495B8F3', // manager
      '0x77479a74abdFe9ACb6626b15950b4cC5E3Fe6414', // borrower
      'L1Test', // borrower name
      10e18.toString(), // intialApr
    ],
    cdo: CDOs.creditl1testusdc,
    cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '600', // 10 minutes
    bufferPeriod: '300', // 5 minutes
    // ## instant params values
    instantWithdrawDelay: '150', // 2 day
    instantWithdrawAprDelta: 2e18.toString(),
    disableInstantWithdraw: true,
    // ## keyring params
    keyring: mainnetContracts.keyringWhitelist,
    keyringPolicy: 16003355,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: false,
    writeoff: false,
    hypernative: false,
    proxyCdoAddress: CDOs.creditfalconxusdc.cdoAddr,
  },
  // creditflowdeskusdc: {
  //   decimals: 6,
  //   underlying: mainnetContracts.USDC,
  //   strategyName: 'IdleCreditVault',
  //   strategyParams: [
  //     mainnetContracts.USDC,
  //     'owner', // owner address
  //     'owner', // manager
  //     // '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
  //     '', // borrower
  //     'Flowdesk', // borrower name
  //     9e18.toString(), // intialApr 9%
  //   ],
  //   cdo: CDOs.creditflowdeskusdc,
  //   cdoVariant: 'contracts/IdleCDOEpochVariant.sol:IdleCDOEpochVariant',
  //   ...baseCDOArgs,
  //   AARatio: '100000',
  //   isAYSActive: false,
  //   limit: '0',
  //   // #########
  //   isCreditVault: true,
  //   // ## epoch params
  //   epochDuration: '2629800', // 30 days
  //   bufferPeriod: '21600', // 6 hours
  //   // ## instant params values
  //   instantWithdrawDelay: '259200', // 3 days
  //   instantWithdrawAprDelta: 1e18.toString(),
  //   disableInstantWithdraw: false,
  //   // ## keyring params
  //   // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
  //   keyring: mainnetContracts.keyringWhitelist,
  //   keyringPolicy: 1280224,
  //   keyringAllowWithdraw: false,
  //   // ## fees (if different from 15%)
  //   fees: '10000', // 10%
  //   // #########
  //   queue: true,
  //   proxyCdoAddress: CDOs.creditfalconxusdc.cdoAddr,
  // },
  usualusd0pptest: {
    decimals: 18,
    underlying: mainnetContracts.USD0pp,
    strategyName: 'IdleUsualStrategy',
    strategyParams: [
      mainnetContracts.USD0pp,
      'owner', // owner address
    ],
    cdo: CDOs.usualusd0pptest,
    cdoVariant: 'IdleCDOUsualVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: false,
    proxyCdoAddress: ''
  },
  usualusd0pp: {
    decimals: 18,
    underlying: mainnetContracts.USD0pp,
    strategyName: 'IdleUsualStrategy',
    strategyParams: [
      mainnetContracts.USD0pp,
      'owner', // owner address
    ],
    cdo: CDOs.usualusd0pp,
    cdoVariant: 'IdleCDOUsualVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '0',
    isAYSActive: false,
    proxyCdoAddress: CDOs.usualusd0pptest.cdoAddr
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
  creditbastionusdt: {
    decimals: 6,
    underlying: polygonContracts.USDT,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      polygonContracts.USDT,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xF381ee632bF26d57f6d5F8717bA573aED835820a', // borrower
      'Bastion', // borrower name
      13e18.toString(), // intialApr 13%
    ],
    cdo: polygonCDOs.creditbastionusdt,
    cdoVariant: 'IdleCDOEpochVariantPolygon',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '2678400', // 31 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params default values
    // instantWithdrawDelay: '259200', // 3 days
    // instantWithdrawAprDelta: 1e18.toString(),
    // disableInstantWithdraw: true,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: polygonContracts.keyringWhitelist,
    keyringPolicy: 20,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: ''
  }
};

exports.deployTokensPolygonZK = {
  cpfasusdc: { // fasanara usdc pool
    decimals: 6,
    underlying: polygonZKContracts.USDC,
    strategyName: 'IdleClearpoolStrategyPolygonZK',
    strategyParams: [
      polygonZKContracts.cpFAS_USDC, // _strategyToken
      polygonZKContracts.USDC, // _underlyingToken
      'owner', // owner address
    ],
    cdo: polygonZKCDOs.cpfasusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: polygonZKCDOs.cpporusdt.cdoAddr,
  },
  cpporusdt: { // portofino usdt pool
    decimals: 6,
    underlying: polygonZKContracts.USDT,
    strategyName: 'IdleClearpoolStrategyPolygonZK',
    strategyParams: [
      polygonZKContracts.cpPOR_USDT, // _strategyToken
      polygonZKContracts.USDT, // _underlyingToken
      'owner', // owner address
    ],
    cdo: polygonZKCDOs.cpporusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: '',
  },
};

exports.deployTokensOptimism = {
  cpfasusdt: { // fasanara usdt pool
    decimals: 6,
    underlying: optimismContracts.USDT,
    strategyName: 'IdleClearpoolStrategyOptimism',
    strategyParams: [
      optimismContracts.cpFAS_USDT, // _strategyToken
      optimismContracts.USDT, // _underlyingToken
      'owner', // owner address
    ],
    cdo: optimismCDOs.cpfasusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: optimismCDOs.cpporusdt.cdoAddr,
  },
  cpporusdt: { // portofino usdt pool
    decimals: 6,
    underlying: optimismContracts.USDT,
    strategyName: 'IdleClearpoolStrategyOptimism',
    strategyParams: [
      optimismContracts.cpPOR_USDT, // _strategyToken
      optimismContracts.USDT, // _underlyingToken
      'owner', // owner address
    ],
    cdo: optimismCDOs.cpporusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: optimismCDOs.cpporusdt.cdoAddr,
  },
  cpwincusdc: { // wincent usdc pool
    decimals: 6,
    underlying: optimismContracts.USDCe,
    strategyName: 'IdleClearpoolStrategyOptimism',
    strategyParams: [
      optimismContracts.cpWINC_USDC, // _strategyToken
      optimismContracts.USDCe, // _underlyingToken
      'owner', // owner address
    ],
    cdo: optimismCDOs.cpwincusdc,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: optimismCDOs.cpporusdt.cdoAddr,
  },
  cpwincusdcv2: { // wincent usdc pool v2
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleClearpoolStrategyOptimism',
    strategyParams: [
      optimismContracts.cpWINC_USDC_V2, // _strategyToken
      optimismContracts.USDC, // _underlyingToken
      'owner', // owner address
    ],
    cdo: optimismCDOs.cpwincusdcv2,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: optimismCDOs.cpporusdt.cdoAddr,
  },
  cpbasusdt: { // bastion trading usdt pool
    decimals: 6,
    underlying: optimismContracts.USDT,
    strategyName: 'IdleClearpoolStrategyOptimism',
    strategyParams: [
      optimismContracts.cpBAS_USDT, // _strategyToken
      optimismContracts.USDT, // _underlyingToken
      'owner', // owner address
    ],
    cdo: optimismCDOs.cpbasusdt,
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: optimismCDOs.cpporusdt.cdoAddr,
  },
  // cpporusdc: { // portofino usdc pool
  //   decimals: 6,
  //   underlying: optimismContracts.USDC,
  //   strategyName: 'IdleClearpoolStrategyOptimism',
  //   strategyParams: [
  //     optimismContracts.cpPOR_USDC, // _strategyToken
  //     optimismContracts.USDC, // _underlyingToken
  //     'owner', // owner address
  //   ],
  //   cdo: optimismCDOs.cpporusdc,
  //   ...baseCDOArgs,
  //   AARatio: '20000',
  //   limit: '20000000',
  //   isAYSActive: true,
  //   proxyCdoAddress: '',
  // },
  credittestusdc: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // borrower
      'TestBorrower2', // borrower name
      0,
    ],
    cdo: optimismCDOs.credittestusdc,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    epochDuration: '604800',
    // ## instant params
    instantWithdrawDelay: '86400',
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: true,
    // ## keyring params
    keyring: addr0,
    keyringPolicy: 4,
    // #########
    proxyCdoAddress: ''
  },
  credittestsamusdc: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0x442Aea0Fd2AFbd3391DAE768F7046f132F0a6300', // manager
      '0x442Aea0Fd2AFbd3391DAE768F7046f132F0a6300', // borrower
      'Sam Test', // borrower name
      10e18.toString(),
    ],
    cdo: optimismCDOs.credittestsamusdc,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params default values
    epochDuration: '120', // 30 days
    bufferPeriod: '120', // 5 days
    // ## instant params default values
    instantWithdrawDelay: '60', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    keyring: addr0,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // #########
    proxyCdoAddress: ''
  },
  creditmaventestusdc: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0xbF56762Cd00cD68347ddA29f307811fE15Bc9c49', // manager
      '0xb6Cd2FfF9f3d60f055FA16cF0ff6f1653C048073', // borrower
      'Maven Test', // borrower name
      10e18.toString(),
    ],
    cdo: optimismCDOs.creditmaventestusdc,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '180', // 3 minutes
    bufferPeriod: '60', // 1 minutes
    // ## instant params default values
    instantWithdrawDelay: '60', // 1 min
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    keyring: addr0,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // #########
    proxyCdoAddress: optimismCDOs.credittestsamusdc.cdoAddr
  },
  creditfalcontestusdc: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0x1fb0f3602F52e2420aCff5CF04DBfDE96378Df58', // manager
      '0x20322eF8857ebeF4fAf2bF4c4A37515E3ae3a745', // borrower
      'FxTest', // borrower name
      15e18.toString(), // intialApr
    ],
    cdo: optimismCDOs.creditfalcontestusdc,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '86400', // 1 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params default values
    instantWithdrawDelay: '43200', // 12 hours
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    keyring: addr0,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // #########
    queue: true,
    proxyCdoAddress: ''
  },
  creditfaxusdc: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0x1fb0f3602F52e2420aCff5CF04DBfDE96378Df58', // manager
      '0x20322eF8857ebeF4fAf2bF4c4A37515E3ae3a745', // borrower
      'Redacted', // borrower name
      0e17.toString(), // intialApr - redacted
    ],
    cdo: optimismCDOs.creditfaxusdc,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '1036800', // 12 days
    bufferPeriod: '43200', // 12 hours
    // ## instant params default values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: optimismContracts.keyringWhitelist,
    keyringPolicy: 18,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: ''
  },
  creditfaxusdcfinal: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0x1fb0f3602F52e2420aCff5CF04DBfDE96378Df58', // manager
      '0x653f71339144e8641a645758f4df4e317fe998a3', // borrower
      'Redacted', // borrower name
      0e17.toString(), // intialApr - redacted
    ],
    cdo: optimismCDOs.creditfaxusdcfinal,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '658800',
    bufferPeriod: '21600', // 12 hours
    // ## instant params default values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: optimismContracts.keyringWhitelist,
    keyringPolicy: 18,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: ''
  },
  creditfaxusdcfinalfinal: {
    decimals: 6,
    underlying: optimismContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      optimismContracts.USDC,
      'owner', // owner address
      '0x1fb0f3602F52e2420aCff5CF04DBfDE96378Df58', // manager
      '0x653f71339144e8641a645758f4df4e317fe998a3', // borrower
      'Redacted', // borrower name
      0e18.toString(), // intialApr - redacted
    ],
    cdo: optimismCDOs.creditfaxusdcfinalfinal,
    cdoVariant: 'IdleCDOEpochVariantOptimism',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '2131200', // 24.666 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params default values
    instantWithdrawDelay: '259200', // 3 days
    instantWithdrawAprDelta: 1e18.toString(),
    disableInstantWithdraw: false,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: optimismContracts.keyringWhitelist,
    keyringPolicy: 18,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: ''
  },
};

exports.deployTokensArbitrum = {
  tfwinusdc: {
    decimals: 6,
    underlying: arbitrumContracts.USDC,
    strategyName: 'TruefiCreditLineStrategy',
    strategyParams: [
      arbitrumContracts.tfWIN_USDC, // _strategyToken
      arbitrumContracts.USDC, // _underlyingToken
      'owner', // owner address
    ],
    cdo: arbitrumCDOs.tfwinusdc,
    cdoVariant: 'IdleCDOTruefiCreditVariant',
    ...baseCDOArgs,
    AARatio: '20000',
    limit: '20000000',
    isAYSActive: true,
    proxyCdoAddress: '',
    // proxyCdoAddress: arbitrumCDOs.cpporusdt.cdoAddr,
  },
  creditbastionusdc: {
    decimals: 6,
    underlying: arbitrumContracts.USDC,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      arbitrumContracts.USDC,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xF381ee632bF26d57f6d5F8717bA573aED835820a', // borrower
      'Bastion', // borrower name
      17e18.toString(), // intialApr 17%
    ],
    cdo: arbitrumCDOs.creditbastionusdc,
    cdoVariant: 'IdleCDOEpochVariantArbitrum',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '2678400', // 31 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params default values
    // instantWithdrawDelay: '259200', // 3 days
    // instantWithdrawAprDelta: 1e18.toString(),
    // disableInstantWithdraw: true,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: arbitrumContracts.keyringWhitelist,
    keyringPolicy: 4,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: ''
  },
  creditbastionusdt: {
    decimals: 6,
    underlying: arbitrumContracts.USDT,
    strategyName: 'IdleCreditVault',
    strategyParams: [
      arbitrumContracts.USDT,
      'owner', // owner address
      '0xeA173648F959790baea225cE3E75dF8A53a6BDE5', // manager
      '0xF381ee632bF26d57f6d5F8717bA573aED835820a', // borrower
      'Bastion', // borrower name
      17e18.toString(), // intialApr 17%
    ],
    cdo: arbitrumCDOs.creditbastionusdt,
    cdoVariant: 'IdleCDOEpochVariantArbitrum',
    ...baseCDOArgs,
    AARatio: '100000',
    isAYSActive: false,
    limit: '0',
    // #########
    isCreditVault: true,
    // ## epoch params
    epochDuration: '2678400', // 31 days
    bufferPeriod: '21600', // 6 hours
    // ## instant params default values
    // instantWithdrawDelay: '259200', // 3 days
    // instantWithdrawAprDelta: 1e18.toString(),
    // disableInstantWithdraw: true,
    // ## keyring params
    // keyring: '0x88e097C960aD0239B4eEC6E8C5B4f74f898eFdA3',
    keyring: arbitrumContracts.keyringWhitelist,
    keyringPolicy: 20,
    keyringAllowWithdraw: false,
    // ## fees (if different from 15%)
    fees: '10000', // 10%
    // #########
    queue: true,
    proxyCdoAddress: ''
  }
};

exports.deployTokensBYOptimism = {
  idleusdtrwa: {
    decimals: 6,
    underlying: optimismContracts.USDT,
    symbol: 'idleUSDTRWA',
    name: 'IdleUSDT RWA',
    address: '0x9Ebcb025949FFB5A77ff6cCC142e0De649801697',
    strategies: [
      // AA tranche wrapper for cpfasusdt
      '0x133F1C751f25C2AAf0E83f0609A67074915144A4',
      // AA tranche wrapper for cpporusdt
      '0x0fDCdC3dF70420BAD4f7EAD4852F961b5D809Df1',
      // AA tranche wrapper for cpbasusdt
      '0xd24A6f07E78165AD865e9Ee2FB6FfF894F5B6A0C',
    ],
  },
}
exports.deployTokensBY = {
  idleusdcjunior: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    symbol: 'idleUSDCJunior',
    name: 'IdleUSDC Junior',
    address: '0xDc7777C771a6e4B3A82830781bDDe4DBC78f320e',
    strategies: [
      // BB tranche of cpPORUSDC PYT
      '0x46e30328920036d7BffCcc14348808bF65C6DaEE',
      // BB tranche of maUSDC PYT
      '0x9db5a6bd77572748e541a0cf42f787f5fe03049e',
      // BB tranche of cpFASUSDC PYT
      '0xC72e841B460Ec6D3e969e5C457A1961463e12e00',
    ],
  },
  idleusdtjunior: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    symbol: 'idleUSDTJunior',
    name: 'IdleUSDT Junior',
    address: '0xfa3AfC9a194BaBD56e743fA3b7aA2CcbED3eAaad',
    strategies: [
      // BB tranche of cpFASUSDT PYT
      '0x9115469239A781e52A518158CBAf36FAfc8B2A77',
      // BB tranche of maUSDT PYT
      '0x5Ac8094308918C3566330EEAe7cf4becaDACEc3E'
    ],
  },
  idledaijunior: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    symbol: 'idleDAIJunior',
    name: 'IdleDAI Junior',
    address: '0xeC9482040e6483B7459CC0Db05d51dfA3D3068E1',
    strategies: [
      // BB tranche of eDAIStaking PYT
      // '0x7188A402Ebd2638d6CccB855019727616a81bBd9',
      // BB tranche of maDAI PYT
      '0x37Dd9A73a84bb0EF562C17b3f7aD34001FEdAf38',
      // BB tranche of cpPOR-DAI PYT
      '0xBC4c00f28b3023620db7ce398F6df0ac3Bdf952C'
    ],
  },
  idlewethjunior: {
    decimals: 18,
    underlying: mainnetContracts.WETH,
    symbol: 'idleWETHJunior',
    name: 'IdleWETH Junior',
    address: '0x62A0369c6BB00054E589D12aaD7ad81eD789514b',
    strategies: [
      // BB tranche of maWETH PYT
      '0x9750c398993862Ebc9C5A30a9F8Be78Daa440677'
    ],
  }
}

exports.whale = '0xba12222222228d8ba445958a75a0704d566bf2c8'; // balancer
exports.whale1 = '0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE'; // binance
exports.whaleLDO = '0x09F82Ccd6baE2AeBe46bA7dd2cf08d87355ac430';
exports.addr0 = addr0;
exports.idleDeployer = '0xE5Dab8208c1F4cce15883348B72086dBace3e64B';
exports.timelock = '0xD6dABBc2b275114a2366555d6C481EF08FDC2556';
exports.CDOs = CDOs;
exports.trancheErc4626Wrappers = trancheErc4626Wrappers;
exports.idleTokenErc4626Wrappers = idleTokenErc4626Wrappers;
exports.polygonCDOs = polygonCDOs;
exports.polygonZKCDOs = polygonZKCDOs;
exports.optimismCDOs = optimismCDOs;
exports.arbitrumCDOs = arbitrumCDOs;
exports.mainnetContracts = mainnetContracts;