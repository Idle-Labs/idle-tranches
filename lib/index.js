const mainnetContracts = {
  idleDAIBest:  "0x3fE7940616e5Bc47b0775a0dccf6237893353bB4",
  idleUSDCBest: "0x5274891bEC421B39D23760c04A6755eCB444797C",
  idleUSDTBest: "0xF34842d05A1c888Ca02769A633DF37177415C2f8",
  idleSUSDBest: "0xf52cdcd458bf455aed77751743180ec4a595fd3f",
  idleTUSDBest: "0xc278041fDD8249FE4c1Aad1193876857EEa3D68c",
  idleWBTCBest: "0x8C81121B15197fA0eEaEE1DC75533419DcfD3151",
  idleWETHBest: "0xC8E6CA6E96a326dC448307A5fDE90a0b21fd7f80",
  idleDAIRisk:  "0xa14eA0E11121e6E951E87c66AFe460A00BCD6A16",
  idleUSDCRisk: "0x3391bc034f2935ef0e1e41619445f998b2680d35",
  idleUSDTRisk: "0x28fAc5334C9f7262b3A3Fe707e250E01053e07b5",

  mainnetProposer: '',
  DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
  treasuryMultisig: "0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814",
  devLeagueMultisig: '0xe8eA8bAE250028a8709A3841E0Ae1a44820d677b',
  rebalancer: '0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B',
  feeTreasury: "0x69a62C24F16d4914a48919613e8eE330641Bcb94"
}

exports.IDLE = "0x875773784Af8135eA0ef43b5a374AaD105c5D39e";
exports.IdleTokens = {
  mainnet: mainnetContracts,
  local: mainnetContracts,
  kovan: {
    idleDAIBest: "0x295CA5bC5153698162dDbcE5dF50E436a58BA21e",
    idleUSDCBest: "0x0de23D3bc385a74E2196cfE827C8a640B8774B9f",
  },
};

exports.signPermit = async (contractAddress, erc20Name, holder, spender, value, nonce, expiry, chainId) => {
  if (chainId === undefined) {
    const result = await web3.eth.getChainId();
    chainId = parseInt(result);
  }

  const domain = [
    { name: "name", type: "string" },
    { name: "version", type: "string" },
    { name: "chainId", type: "uint256" },
    { name: "verifyingContract", type: "address" }
  ];

  const permit = [
    { name: "holder", type: "address" },
    { name: "spender", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "expiry", type: "uint256" },
    { name: "allowed", type: "bool" },
  ];

  const domainData = {
    name: erc20Name,
    version: "1",
    chainId: chainId,
    verifyingContract: contractAddress
  };

  const message = {
    holder,
    spender,
    nonce,
    expiry,
    allowed: true,
  };

  const data = {
    types: {
      EIP712Domain: domain,
      Permit: permit,
    },
    primaryType: "Permit",
    domain: domainData,
    message: message
  };

  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      id: Date.now().toString().substring(9),
      method: "eth_signTypedData",
      params: [holder, data],
      from: holder
    }, (error, res) => {
      if (error) {
        return reject(error);
      }

      resolve(res.result);
    });
  });
}

exports.signPermitEIP2612 = async (contractAddress, erc20Name, owner, spender, value, nonce, deadline, chainId) => {
  if (chainId === undefined) {
    const result = await web3.eth.getChainId();
    chainId = parseInt(result);
  }

  const domain = [
    { name: "name", type: "string" },
    { name: "version", type: "string" },
    { name: "chainId", type: "uint256" },
    { name: "verifyingContract", type: "address" }
  ];

  const permit = [
    { name: "owner", type: "address" },
    { name: "spender", type: "address" },
    { name: "value", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ];

  const domainData = {
    name: erc20Name,
    version: "2",
    chainId: chainId,
    verifyingContract: contractAddress
  };

  const message = {
    owner,
    spender,
    value,
    nonce,
    deadline,
  };

  const data = {
    types: {
      EIP712Domain: domain,
      Permit: permit,
    },
    primaryType: "Permit",
    domain: domainData,
    message: message
  };

  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      id: Date.now().toString().substring(9),
      method: "eth_signTypedData",
      params: [owner, data],
      from: owner
    }, (error, res) => {
      if (error) {
        return reject(error);
      }

      resolve(res.result);
    });
  });
}
