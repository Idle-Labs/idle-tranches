const { ethers } = require("hardhat");
const { expect } = require("chai");
import { BigNumber } from "ethers";

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));

describe("IdleStrategy", function () {
  beforeEach(async () => {
    // reset fork

    // deploy contracts
  });

  describe("IdleStrategy Tests", function () {
    it("should pass", async function () {
      // const [owner, addr1] = await ethers.getSigners();
      // await strat.connect(addr1).setGreeting("Hallo, Erde!");

      // const account = '0x364d6D0333432C3Ac016Ca832fb8594A8cE43Ca6';
      // await hre.network.provider.request({
      //   method: "hardhat_impersonateAccount",
      //   params: [account]}
      // )
      // const signer = await ethers.provider.getSigner(account)
      // signer.sendTransaction(...)

      // const IdleStrategy = await ethers.getContractAt("IIdleToken", '0x3fE7940616e5Bc47b0775a0dccf6237893353bB4');
      // const sushiLPToken = await hre.ethers.getContractAt("IERC20", addresses.networks.mainnet.sushiLPToken)
      //
      // const IdleStrategy = await ethers.getContractFactory("IdleStrategy");
      // const strat = await IdleStrategy.deploy("Hello, world!");
      //
      // await strat.deployed();
      // expect(await strat.greet()).to.equal("Hello, world!");
    });
  });
});
