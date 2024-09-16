require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const addresses = require("../../../utils/addresses");
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

describe("IdleLidoCDO", function () {
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

    const Gateway = await ethers.getContractFactory("LidoCDOTrancheGateway");
    const MockLido = await ethers.getContractFactory("MockLido"); // underlyingToken
    const WETH = await ethers.getContractFactory("MockWETH"); // strategyToken
    const MockWstETH = await ethers.getContractFactory("MockWstETH"); // strategyToken
    const MockLidoOracle = await ethers.getContractFactory("MockLidoOracle");
    const MockERC20 = await ethers.getContractFactory("MockERC20");

    // Lido deployed contracts: https://docs.lido.fi/deployed-contracts
    lido = await MockLido.attach('0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84')
    underlying = lido
    weth = await WETH.attach('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2');
    wstETH = await MockWstETH.attach('0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0');
    oracle = await MockLidoOracle.attach('0x442af784A788A5bd6F42A01Ebe9F287a871243fb')
    // Incentive tokens are manually distributed directly in the staking contract for LDO
    incentiveTokens = []

    strategy = await helpers.deployUpgradableContract(
      "IdleLidoStrategy",
      [
        wstETH.address,
        underlying.address,
        owner.address,
      ],
      owner
    );

    await lido
      .connect(owner)
      .submit(ZERO_ADDRESS, { value: BN("100").mul(ONE_TOKEN(18)) });
    
    await weth
      .connect(owner)
      .deposit({ value: BN("100").mul(ONE_TOKEN(18)) });
    
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

    initialAmount = BN("10").mul(ONE_TOKEN(18));
    // Fund wallets
    await helpers.fundWallets(
      underlying.address,
      [
        AABuyerAddr,
        BBBuyerAddr,
        AABuyer2Addr,
        BBBuyer2Addr,
      ],
      owner.address,
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

  it("should not reinitialize the contract", async () => {
    await expect(
      idleCDO.connect(owner).initialize(
        BN('10000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000') // apr split: 20% interest to AA and 80% BB
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize params", async () => {
    const AAERC20 = await ethers.getContractAt("IERC20Detailed", AA.address);
    const BBERC20 = await ethers.getContractAt("IERC20Detailed", BB.address);

    // IdleCDO
    expect(await idleCDO.AATranche()).to.equal(AA.address);
    expect(await idleCDO.BBTranche()).to.equal(BB.address);
    expect(await AAERC20.symbol()).to.equal('AA_wstETH');
    expect(await AAERC20.name()).to.equal('IdleCDO AA Tranche - wstETH');
    expect(await BBERC20.symbol()).to.equal('BB_wstETH');
    expect(await BBERC20.name()).to.equal('IdleCDO BB Tranche - wstETH');
    expect(await idleCDO.token()).to.equal(underlying.address);
    expect(await idleCDO.strategy()).to.equal(strategy.address);
    expect(await idleCDO.strategyToken()).to.equal(wstETH.address);
    expect(await idleCDO.rebalancer()).to.equal(owner.address);
    expect(await idleCDO.trancheAPRSplitRatio()).to.be.equal(BN('20000'));
    expect(await idleCDO.trancheIdealWeightRatio()).to.be.equal(BN('50000'));
    expect(await idleCDO.idealRange()).to.be.equal(BN('10000'));
    expect(await idleCDO.unlentPerc()).to.be.equal(BN('2000'));
    expect(await idleCDO.oneToken()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.priceAA()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.priceBB()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.allowAAWithdraw()).to.equal(true);
    expect(await idleCDO.allowBBWithdraw()).to.equal(true);
    expect(await idleCDO.revertIfTooLow()).to.equal(true);
    expect(await wstETH.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await underlying.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await idleCDO.lastStrategyPrice()).to.be.equal(await wstETH.stEthPerToken());
    expect(await idleCDO.fee()).to.be.equal(BN('10000'));
    expect(await idleCDO.releaseBlocksPeriod()).to.be.equal(BN('1500'));
    expect(await idleCDO.feeReceiver()).to.equal(feeCollectorAddr);
    expect(await idleCDO.guardian()).to.equal(owner.address);
    expect(await idleCDO.weth()).to.equal(weth.address);
    // OwnableUpgradeable
    expect(await idleCDO.owner()).to.equal(owner.address);
    // GuardedLaunchUpgradable
    expect(await idleCDO.limit()).to.be.equal(BN('10000').mul(ONE_TOKEN(18)));
    expect(await idleCDO.governanceRecoveryFund()).to.equal(owner.address);
  });

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

    // LidoTranche is no extra rewards such as COMP, LDO
    console.log('######## First real rebalance (with interest and rewards accrued)');

    // tranchePriceAA and tranchePriceBB have been updated just before the deposit
    // some gov token (IDLE but not COMP because it has been sold) should be present in the contract after the rebalance
    await rebalanceFull(idleCDO, owner.address, true, false);

    console.log('######## Withdraws');
    // First user withdraw
    await helpers.withdrawWithGain('AA', idleCDO, AABuyerAddr, _amount);
    await rebalanceFull(idleCDO, owner.address, true, false);
    await helpers.withdrawWithGain('BB', idleCDO, BBBuyerAddr, _amount.div(BN('2')));
    await rebalanceFull(idleCDO, owner.address, true, false);
    await helpers.withdrawWithGain('AA', idleCDO, AABuyer2Addr, _amount);
  });

  const rebalanceFull = async (idleCDO, address, skipIncentivesUpdate, skipFeeDeposit) => {
    console.log('🚧 Waiting some time + 🚜 Harvesting');

    await mineBlocks({ blocks: 500 })
    const strategyAddr = await idleCDO.strategy();
    let idleStrategy = await ethers.getContractAt("IdleStrategy", strategyAddr);
    const rewardTokens = await idleStrategy.getRewardTokens();

    let res = await helpers.sudoStaticCall(address, idleCDO, 'harvest', [[false, skipIncentivesUpdate, skipFeeDeposit, false && skipIncentivesUpdate && skipFeeDeposit], rewardTokens.map(r => false), rewardTokens.map(r => BN('0')), rewardTokens.map(r => BN('0')), '0x']);
    let sellAmounts = res[0];
    let minAmounts = res[1];
    // Add some slippage tolerance
    minAmounts = minAmounts.map(m => BN(m).div(BN('100')).mul(BN('97'))); // 3 % slippage
    await helpers.sudoCall(address, idleCDO, 'harvest', [[false, skipIncentivesUpdate, skipFeeDeposit, false], rewardTokens.map(r => false), minAmounts, sellAmounts, '0x']);
    await mineBlocks({ blocks: 500 })

    // Lido oracle updates the status
    const { beaconBalance } = await lido.getBeaconStat()
    await rebaseStETH(lido.address, beaconBalance.add(ONE_TOKEN(9)))
  }

  const mineBlocks = async ({ blocks }) => {
    for (let index = 0; index < blocks; index++) {
      await ethers.provider.send("evm_mine");
    }
  }

  // trigger rebasing stETH token manually, using `hardhat_setStorageAt`
  // stETH contract use unstructured storage layout for storing beacon balance.
  // ref: https://github.com/lidofinance/lido-dao/blob/816bf1d0995ba5cfdfc264de4acda34a7fe93eba/contracts/0.4.24/Lido.sol#L78
  const rebaseStETH = async (lidoAddr, balance) => {
    const value = '0x' + balance.toHexString().slice(2).padStart(64, '0')
    const slot = solidityKeccak256(["string"], ["lido.Lido.beaconBalance"])
    const prevValue = await hre.network.provider.send("eth_getStorageAt", [
      lidoAddr,
      slot,
    ])
    console.log(`Set Storage at ${slot} from ${prevValue} to ${value}`);
    // Override beacon balance.
    await hre.network.provider.send("hardhat_setStorageAt", [
      lidoAddr,
      slot,
      value,
    ])
  }
});
