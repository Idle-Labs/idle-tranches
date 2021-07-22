const mainnetContracts = {
  idleDAIBest:  "0x3fE7940616e5Bc47b0775a0dccf6237893353bB4",
  idleUSDCBest: "0x5274891bEC421B39D23760c04A6755eCB444797C",
  idleUSDTBest: "0xF34842d05A1c888Ca02769A633DF37177415C2f8",
  idleSUSDBest: "0xf52cdcd458bf455aed77751743180ec4a595fd3f",
  idleTUSDBest: "0xc278041fDD8249FE4c1Aad1193876857EEa3D68c",
  idleWBTCBest: "0x8C81121B15197fA0eEaEE1DC75533419DcfD3151",
  idleWETHBest: "0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80",
  idleRAIBest: "0x5C960a3DCC01BE8a0f49c02A8ceBCAcf5D07fABe",
  idleDAIRisk:  "0xa14eA0E11121e6E951E87c66AFe460A00BCD6A16",
  idleUSDCRisk: "0x3391bc034f2935ef0e1e41619445f998b2680d35",
  idleUSDTRisk: "0x28fAc5334C9f7262b3A3Fe707e250E01053e07b5",

  mainnetProposer: '',
  DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
  cDAI: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643',
  USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
  cUSDC: '0x39aa39c021dfbae8fac545936693ac917d5e7563',
  USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
  cUSDT: '0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9',
  IDLE: '0x875773784Af8135eA0ef43b5a374AaD105c5D39e',
  stkAAVE: '0x4da27a545c0c5b758a6ba100e3a049001de870f5',
  COMP: '0xc00e94Cb662C3520282E6f5717214004A7f26888',
  treasuryMultisig: "0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814",
  devLeagueMultisig: '0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  // NOTE: This is hardcoded in the contract too
  feeReceiver: '0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4',
  feeTreasury: "0x69a62C24F16d4914a48919613e8eE330641Bcb94"
}

exports.IdleTokens = {
  mainnet: mainnetContracts,
  local: mainnetContracts,
  kovan: {
    idleDAIBest: "0x295CA5bC5153698162dDbcE5dF50E436a58BA21e",
    idleUSDCBest: "0x0de23D3bc385a74E2196cfE827C8a640B8774B9f",
  },
};
exports.whale = '0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE';
exports.addr0 = '0x0000000000000000000000000000000000000000';
exports.deployTokens = {
  DAI: {
    decimals: 18,
    underlying: mainnetContracts.DAI,
    idleToken: mainnetContracts.idleDAIBest,
    cToken: mainnetContracts.cDAI,
    cdo: CDOs.idleDAI.cdo
  },
  USDC: {
    decimals: 6,
    underlying: mainnetContracts.USDC,
    idleToken: mainnetContracts.idleUSDCBest,
    cToken: mainnetContracts.cUSDC
  },
  USDT: {
    decimals: 6,
    underlying: mainnetContracts.USDT,
    idleToken: mainnetContracts.idleUSDTBest,
    cToken: mainnetContracts.cUSDT
  }
};

exports.CDOs = {
  idleDAI: {
    strategyToken: mainnetContracts.idleDAIBest,
    underlying: mainnetContracts.DAI,
    cdo: '0x675a1378777cc2d25dbf430a28738cb6b7a3f8c2',
    proxyAdmin: '0x0138A84f821809e2d01B16d053f4b4A5b88b725E',
    strategy: '0x0cDcBEAddF2276Df7f41d8b1f45249bf3d63a8d6',
    AArewards: '0xa8c7b9c4F18B227Abc4b099bA92d6a1CfEb9649C',
    BBrewards: '0x0962fB33A7E0172d0E413b0fab003bEe5142E6B6',
    AATranche: '0xe524EE80584b120c4df8c2f130AE571ed6C196DB',
    BBTranche: '0x95a2834AFDC65dd7f28585d2d992367600afb457'
  }
}
