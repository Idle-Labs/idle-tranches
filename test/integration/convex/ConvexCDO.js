require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const addresses = require("../../../lib/addresses");
const { expect } = require("chai");
const { FakeContract, smock } = require('@defi-wonderland/smock');
const { solidityKeccak256 } = require("ethers/lib/utils");

require('chai').use(smock.matchers);

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const POOL_ID_3CRV = 9;
const DEPOSIT_POSITION_3CRV = BN(0);
const WHALE_3CRV = '0x0b096d1f0ba7ef2b3c7ecb8d4a5848043cdebd50';
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
const TOKEN_3CRV = '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490'
const CVX = '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B';
const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const SUSHI_ROUTER = '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F';

const CVXWETH = [CVX, WETH]
const CRVWETH = [CRV, WETH]
const WETHDAI = [WETH, DAI]

describe("IdleConvexCDO", function () {
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
    underlying = MockERC20.attach(TOKEN_3CRV);

    booster = await ethers.getContractAt("IBooster", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31");

    // funding the whale to transfer 3CRV
    await owner.sendTransaction({to: WHALE_3CRV, value: ethers.utils.parseEther("1")});

    curve_args = [DAI, addresses.addr0, DEPOSIT_POSITION_3CRV]
    reward_cvx = [CVX, SUSHI_ROUTER, CVXWETH];
    reward_crv = [CRV, SUSHI_ROUTER, CRVWETH];
    weth2deposit = [SUSHI_ROUTER, WETHDAI];

    idle = await MockERC20.attach('0x875773784Af8135eA0ef43b5a374AaD105c5D39e') // IDLE
    incentiveTokens = [idle.address]

    strategy = await helpers.deployUpgradableContract(
      "ConvexStrategy3Token",
      [POOL_ID_3CRV, owner.address, 0, curve_args, [reward_crv, reward_cvx], weth2deposit]
    );

    idleCDO = await helpers.deployUpgradableContract(
      'IdleCDO',
      [
        BN('500000').mul(ONE_TOKEN(18)), // limit
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

    strategy.setWhitelistedCDO(idleCDO.address)

    AA = await ethers.getContractAt("IdleCDOTranche", await idleCDO.AATranche());
    BB = await ethers.getContractAt("IdleCDOTranche", await idleCDO.BBTranche());

    const stakingRewardsParams = [
      incentiveTokens,
      owner.address, // owner / guardian
      idleCDO.address,
      owner.address, // recovery address
      10, // cooling period
    ];
    stakingRewardsAA = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [AA.address, ...stakingRewardsParams], owner
    );
    stakingRewardsBB = await helpers.deployUpgradableContract(
      'IdleCDOTrancheRewards', [BB.address, ...stakingRewardsParams], owner
    );

    // await idleCDO.setUnlentPerc(BN('0'));
    await idleCDO.setStakingRewards(stakingRewardsAA.address, stakingRewardsBB.address);
    await idleCDO.setIsStkAAVEActive(false);
    await idleCDO.setFeeReceiver(feeCollectorAddr);
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
        BN('500000').mul(ONE_TOKEN(18)), // limit
        underlying.address,
        owner.address,
        owner.address,
        owner.address,
        strategy.address,
        BN('20000'), // apr split: 20% interest to AA and 80% BB
        BN('50000'), // ideal value: 50% AA and 50% BB tranches
        incentiveTokens
      )
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize params", async () => {
    const AAERC20 = await ethers.getContractAt("IERC20Detailed", AA.address);
    const BBERC20 = await ethers.getContractAt("IERC20Detailed", BB.address);

    // IdleCDO
    expect(await idleCDO.AATranche()).to.equal(AA.address);
    expect(await idleCDO.BBTranche()).to.equal(BB.address);
    expect(await AAERC20.symbol()).to.equal('AA_idleCvx3Crv');
    expect(await AAERC20.name()).to.equal('IdleCDO AA Tranche - idleCvx3Crv');
    expect(await BBERC20.symbol()).to.equal('BB_idleCvx3Crv');
    expect(await BBERC20.name()).to.equal('IdleCDO BB Tranche - idleCvx3Crv');
    expect(await idleCDO.token()).to.equal(underlying.address);
    expect(await idleCDO.strategy()).to.equal(strategy.address);
    expect(await idleCDO.strategyToken()).to.equal(strategy.address);
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
    expect(await underlying.allowance(idleCDO.address, strategy.address)).to.be.equal(MAX_UINT);
    expect(await idleCDO.lastStrategyPrice()).to.be.equal(BN(10 ** 18));
    expect(await idleCDO.fee()).to.be.equal(BN('10000'));
    expect(await idleCDO.releaseBlocksPeriod()).to.be.equal(BN('1500'));
    expect(await idleCDO.feeReceiver()).to.equal(feeCollectorAddr);
    expect(await idleCDO.guardian()).to.equal(owner.address);
    expect(await idleCDO.weth()).to.equal(WETH);
    expect(await idleCDO.incentiveTokens(0)).to.equal(incentiveTokens[0]);
    // OwnableUpgradeable
    expect(await idleCDO.owner()).to.equal(owner.address);
    // GuardedLaunchUpgradable
    expect(await idleCDO.limit()).to.be.equal(BN('500000').mul(ONE_TOKEN(18)));
    expect(await idleCDO.governanceRecoveryFund()).to.equal(owner.address);
  });

  it("Integration", async () => {
    const _amount = BN('1000').mul(ONE_TOKEN(18));

    // Fund wallets
    await helpers.fundWallets(
      underlying.address,
      [
        AABuyerAddr,
        BBBuyerAddr,
        AABuyer2Addr,
        BBBuyer2Addr,
        RandomAddr
      ],
      WHALE_3CRV,
      _amount
    );

    // Buy AA tranche with `amount` underlying
    const aaTrancheBal = await helpers.deposit('AA', idleCDO, AABuyerAddr, _amount);
    // Buy BB tranche with `amount` underlying
    const bbTrancheBal = await helpers.deposit('BB', idleCDO, BBBuyerAddr, _amount.div(BN('2')));
    expect(aaTrancheBal).to.be.equal(_amount);
    expect(bbTrancheBal).to.be.equal(_amount.div(BN('2')));
    expect(await underlying.balanceOf(AABuyerAddr)).to.be.closeTo(_amount.sub(_amount), 1);
    expect(await underlying.balanceOf(BBBuyerAddr)).to.be.closeTo(_amount.sub(_amount.div(BN('2'))), 1);

    // Do an harvest to do a real deposit in ConvexStrategy
    await rebalanceFull(idleCDO, owner.address, true, true, false);
    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa2TrancheBal = await helpers.deposit('AA', idleCDO, AABuyer2Addr, _amount);
    // amount bought should be less than the one of AABuyerAddr because price increased
    await helpers.check(aa2TrancheBal, aaTrancheBal, 'AA1 bal is greater than the newly minted bal after harvest');

    console.log('######## First real rebalance (with CVX, CRV rewards accrued)');

    // tranchePriceAA and tranchePriceBB have been updated just before the deposit
    await rebalanceFull(idleCDO, owner.address, false, false, false);
    // so no IDLE in IdleCDO
    await helpers.checkBalance(idle, idleCDO.address, BN('0'));

    // strategy price should be increased after a rebalance and some time
    // Buy AA tranche with `amount` underlying from another user
    const aa3TrancheBal = await helpers.deposit('AA', idleCDO, RandomAddr, _amount);
    await helpers.checkIncreased(aa3TrancheBal, aa2TrancheBal, 'AA2 bal is greater than the newly minted bal after harvest');


    console.log('######## Withdraws');
    // First user withdraw
    await helpers.withdrawWithGain('AA', idleCDO, AABuyerAddr, _amount);
    await rebalanceFull(idleCDO, owner.address, false, false, false);

    await helpers.withdrawWithGain('BB', idleCDO, BBBuyerAddr, _amount.div(BN('2')));
    await rebalanceFull(idleCDO, owner.address, false, false);

    await helpers.withdrawWithGain('AA', idleCDO, AABuyer2Addr, _amount);
  });

  const rebalanceFull = async (idleCDO, address, skipRedeem, skipIncentivesUpdate, skipFeeDeposit) => {
    console.log('🚧 Waiting some time + 🚜 Harvesting');

    const oneDay = 3600 * 24;
    
    // distribute CRVs to reward pools, this is not an automatic
    booster.earmarkRewards(POOL_ID_3CRV);

    // wait 15 days
    await mineBlocks({ increaseOf: oneDay })

    await helpers.sudoCall(address, idleCDO, 'harvest', [skipRedeem, skipIncentivesUpdate, skipFeeDeposit, [], [], []]);
  }

  const mineBlocks = async ({ increaseOf }) => {
    await network.provider.send("evm_increaseTime", [increaseOf]);
    await network.provider.send("evm_mine", []);
  }
});
