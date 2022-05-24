require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const addresses = require("../../../lib/addresses");
const mainnetContracts = addresses.mainnetContracts;
const { expect } = require("chai");
const { FakeContract, smock } = require('@defi-wonderland/smock');
const { solidityKeccak256 } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

require('chai').use(smock.matchers);

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Euler PYT", function () {
  beforeEach(async () => {
    // deploy contracts
    addr0 = addresses.addr0;
    signers = await ethers.getSigners();
    owner = signers[0];
    AABuyer = signers[1];
    AABuyerAddr = AABuyer.address;
    BBBuyer = signers[2];
    BBBuyerAddr = BBBuyer.address;
    AABuyer2 = signers[3];
    AABuyer2Addr = AABuyer2.address;
    BBBuyer2 = signers[4];
    BBBuyer2Addr = BBBuyer2.address;
    Random = signers[5];
    RandomAddr = Random.address;
    Random2 = signers[6];
    Random2Addr = Random2.address;
    feeCollector = signers[7];
    feeCollectorAddr = feeCollector.address;

    one = ONE_TOKEN(18);

    const MockERC20 = await ethers.getContractFactory("MockERC20");

    eDAI = await MockERC20.attach(mainnetContracts.eDAI);
    DAI = await MockERC20.attach(mainnetContracts.DAI);
    eulerMain = await MockERC20.attach(mainnetContracts.eulerMain);
    underlying = DAI
    incentiveTokens = []

    strategy = await helpers.deployUpgradableContract(
      "IdleEulerStrategy",
      [
        eDAI.address,
        DAI.address,
        eulerMain.address,
        owner.address,
      ],
      owner
    );

    idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('10000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens
      ],
      owner
    );

    AA = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
    BB = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());

    await idleCDO.setIsStkAAVEActive(false);
    await idleCDO.setFeeReceiver(feeCollectorAddr);

    initialAmount = BN("10000").mul(ONE_TOKEN(18));
    // Fund wallets
    await helpers.fundWallets(
      underlying.address,
      [
        AABuyerAddr,
        BBBuyerAddr,
        AABuyer2Addr,
        BBBuyer2Addr,
        owner.address
      ],
      addresses.whale,
      initialAmount
    );
  });

  afterEach(async function () {
    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: hre.network.config.forking.url,
            blockNumber: hre.network.config.forking.blockNumber
          }
        }
      ]
    });
  })

  it("Integration", async () => {
    const _amount = BN('10').mul(ONE_TOKEN(18));
    // Buy AA tranche with `amount` underlying
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    // Buy BB tranche with `amount` underlying
    const bbTrancheBal = await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount.div(BN('2')));
    expect(aaTrancheBal).to.be.equal(_amount);
    expect(bbTrancheBal).to.be.equal(_amount.div(BN('2')));
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.closeTo(initialAmount.sub(_amount), 1);
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.closeTo(initialAmount.sub(_amount.div(BN('2'))), 1);

    // Do an harvest to do a real deposit in Idle
    // no gov tokens collected now because it's the first deposit
    await rebalanceFull(idleCDO, owner.address, true, false);
    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa2TrancheBal = await helpers.deposit('AA', idleCDO, AABuyer2Addr, _amount);
    // amount bought should be less than the one of AABuyerAddr because price increased
    await helpers.checkIncreased(aa2TrancheBal, aaTrancheBal, 'AA1 bal is greater than the newly minted bal after harvest');

    // Euler tranche has no extra rewards
    console.log('######## First real rebalance (with interest and rewards accrued)');

    // tranchePriceAA and tranchePriceBB have been updated just before the deposit
    // some gov token (IDLE but not COMP because it has been sold) should be present in the contract after the rebalance
    await rebalanceFull(idleCDO, owner.address, true, false);

    // Check that Apr is > 0
    const aprAA = await idleCDO.getApr(AA.address);
    const aprBB = await idleCDO.getApr(BB.address);
    expect(aprAA).to.be.bignumber.gt(BN('0'));
    expect(aprBB).to.be.bignumber.gt(BN('0'));

    console.log('######## Withdraws');
    // First user withdraw
    await helpers.withdrawWithGain('AA', idleCDO, AABuyerAddr, _amount);
    await rebalanceFull(idleCDO, owner.address, true, false);
    await helpers.withdrawWithGain('BB', idleCDO, BBBuyerAddr, _amount.div(BN('2')));
    await rebalanceFull(idleCDO, owner.address, true, false);
    await helpers.withdrawWithGain('AA', idleCDO, AABuyer2Addr, _amount);
  });

  const mineBlocks = async ({ blocks }) => {
    for (let index = 0; index < blocks; index++) {
      await ethers.provider.send("evm_mine");
    }
  }

  const rebalanceFull = async (idleCDO, address, skipIncentivesUpdate, skipFeeDeposit) => {
    console.log('🚧 Waiting some time + 🚜 Harvesting');

    await mineBlocks({ blocks: 500 })
    const strategyAddr = await idleCDO.strategy();
    let idleStrategy = await ethers.getContractAt("IdleStrategy", strategyAddr);
    const rewardTokens = await idleStrategy.getRewardTokens();
    const extraData = '0x';
    let res = await helpers.sudoStaticCall(address, idleCDO, 'harvest', [
      [false, skipIncentivesUpdate, skipFeeDeposit, false], 
      rewardTokens.map(r => false), 
      rewardTokens.map(r => BN('0')), 
      rewardTokens.map(r => BN('0')), 
      extraData
    ]);
    let sellAmounts = res[0];
    let minAmounts = res[1];
    // Add some slippage tolerance
    minAmounts = minAmounts.map(m => BN(m).div(BN('100')).mul(BN('97'))); // 3 % slippage
    await helpers.sudoCall(address, idleCDO, 'harvest', [
      [false, skipIncentivesUpdate, skipFeeDeposit, false], 
      rewardTokens.map(r => false), 
      minAmounts, 
      sellAmounts, 
      extraData
    ]);
    await mineBlocks({ blocks: 500 })
  }
});
