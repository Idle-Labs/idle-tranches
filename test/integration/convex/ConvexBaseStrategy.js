require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../../scripts/helpers");
const { expect } = require("chai");
const addresses = require("../../../lib/addresses");
const { smock } = require('@defi-wonderland/smock');
const { ethers, network } = require("hardhat");

require('chai').use(smock.matchers);

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const POOL_ID_3CRV = 9;
const DEPOSIT_POSITION_3CRV = 1;
const WHALE_3CRV = '0x7acaed42fd79aaf0cdec641a2c59e06d996b96a0';
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
const TOKEN_3CRV = '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490'
const CVX = '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B';
const SPELL = '0x090185f2135308bad17527004364ebcc2d37e5f6';
const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const SUSHI_ROUTER = '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F';

const CVXWETH = [CVX, WETH]
const CRVWETH = [CRV, WETH]
const SPELLWETH = [SPELL, WETH]
const WETHUSDC = [WETH, USDC]


describe("ConvexBaseStrategy (using 3pool for tests)", async () => {
  
  before(async () => {
    // setup
    signers = await ethers.getSigners();
    owner = signers[0];
    Random = signers[1];
    RandomAddr = Random.address;
    Random2Addr = signers[2].address;

    one = ONE_TOKEN(18);

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    erc20_3crv = MockERC20.attach(TOKEN_3CRV);

    booster = await ethers.getContractAt("IBooster", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31");

    // funding the buyer
    await owner.sendTransaction({to: RandomAddr, value: ethers.utils.parseEther("20")});
    // funding the whale to transfer 3crv
    await owner.sendTransaction({to: WHALE_3CRV, value: ethers.utils.parseEther("20")});

    curve_args = [USDC, addresses.addr0, DEPOSIT_POSITION_3CRV]
    reward_cvx = [CVX, SUSHI_ROUTER, CVXWETH];
    reward_crv = [CRV, SUSHI_ROUTER, CRVWETH];
    reward_spell = [SPELL, SUSHI_ROUTER, SPELLWETH];
    weth2deposit = [SUSHI_ROUTER, WETHUSDC];
  });
  
  beforeEach(async () => {
    strategy = await helpers.deployUpgradableContract('ConvexStrategy3Token', [POOL_ID_3CRV, owner.address, 1500, curve_args, [reward_crv, reward_cvx, reward_spell], weth2deposit]);
  });

  afterEach(async () => {
    const balance3crv = await erc20_3crv.balanceOf(RandomAddr);
    await helpers.fundWallets(TOKEN_3CRV, [WHALE_3CRV], RandomAddr, balance3crv);
  });

  it("should not reinitialize the contract", async () => {
    await expect(
      strategy.connect(owner).initialize(POOL_ID_3CRV, owner.address, 1500, curve_args, [reward_crv, reward_cvx], weth2deposit),
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should initialize", async () => {
    const REWARD_POOL = '0x689440f2Ff927E1f24c72F1087E1FAF471eCe1c8';
    
    // from interface
    expect(await strategy.strategyToken()).to.equal(strategy.address);
    expect(await strategy.token()).to.equal(TOKEN_3CRV);
    expect(await strategy.tokenDecimals()).to.be.equal(BN(18));
    expect(await strategy.oneToken()).to.be.equal(one);
    expect(await strategy.owner()).to.equal(owner.address);

    // from convex strat specific storage
    expect(await strategy.depositor()).to.equal(addresses.addr0);
    expect(await strategy.curveLpToken()).to.equal(TOKEN_3CRV);
    expect(await strategy.curveLpDecimals()).to.be.equal(BN(18));
    expect(await strategy.curveDeposit()).to.be.equal(USDC);
    expect(await strategy.depositPosition()).to.equal(BN(1));
    expect(await strategy.rewardPool()).to.equal(REWARD_POOL);

    // rewards
    expect(await strategy.convexRewards(0)).to.equal(CRV);
    expect(await strategy.convexRewards(1)).to.equal(CVX);
    expect(await strategy.weth2DepositPath(0)).to.equal(WETH);
    expect(await strategy.weth2DepositPath(1)).to.equal(USDC);
    expect(await strategy.reward2WethPath(CRV, 0)).to.equal(CRV);
    expect(await strategy.reward2WethPath(CRV, 1)).to.equal(WETH);
    expect(await strategy.reward2WethPath(CVX, 0)).to.equal(CVX);
    expect(await strategy.reward2WethPath(CRV, 1)).to.equal(WETH);
    expect(await strategy.weth2DepositRouter()).to.equal(SUSHI_ROUTER);
    expect(await strategy.rewardRouter(CRV)).to.equal(SUSHI_ROUTER);
    expect(await strategy.rewardRouter(CVX)).to.equal(SUSHI_ROUTER);
  });

  it("should not be able to deposit if not whitelisted", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);
    
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);

    await expect(deposit(addr, _amount)).to.be.revertedWith('Not whitelisted CDO');

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should not be able to redeem if not whitelisted", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);

    setWhitelistedCDO(addr);
    
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);

    await deposit(addr, _amount);

    setWhitelistedCDO(Random2Addr);

    await expect(redeem(addr, _amount)).to.be.revertedWith('Not whitelisted CDO');

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should not be able to redeemUnderlying if not whitelisted", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);

    setWhitelistedCDO(addr);
    
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);

    await deposit(addr, _amount);

    setWhitelistedCDO(Random2Addr);

    await expect(redeemUnderlying(addr, _amount)).to.be.revertedWith('Not whitelisted CDO');

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should not be able to redeemRewards if not whitelisted", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);

    setWhitelistedCDO(addr);
    
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);

    await deposit(addr, _amount);

    setWhitelistedCDO(Random2Addr);

    await expect(redeemRewards(RandomAddr)).to.be.revertedWith('Not whitelisted CDO');

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should deposit", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);
    
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);

    setWhitelistedCDO(addr);

    const initial3crvBalance = await erc20_3crv.balanceOf(addr);

    await deposit(addr, _amount);
    const final3crvBalance = await erc20_3crv.balanceOf(addr);
    const strategyBalance = await strategy.balanceOf(addr);

    expect(initial3crvBalance.sub(final3crvBalance)).to.equal(_amount);
    expect(strategyBalance).to.equal(_amount);

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should redeem", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);

    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);
    
    setWhitelistedCDO(addr);

    const initial3crvBalance = await erc20_3crv.balanceOf(addr);    
    await deposit(addr, _amount);
    const initialStrategyBalance = await strategy.balanceOf(addr);
    await redeem(addr, initialStrategyBalance);
    const final3crvBalance = await erc20_3crv.balanceOf(addr);
    const finalStrategyBalance = await strategy.balanceOf(addr);

    expect(final3crvBalance).to.equal(initial3crvBalance);
    expect(finalStrategyBalance).to.equal(0);

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should redeemUnderlying (equivalent to redeem)", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);

    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);
    
    setWhitelistedCDO(addr);

    const initial3crvBalance = await erc20_3crv.balanceOf(addr);    
    await deposit(addr, _amount);
    const initialStrategyBalance = await strategy.balanceOf(addr);
    await redeemUnderlying(addr, initialStrategyBalance);
    const final3crvBalance = await erc20_3crv.balanceOf(addr);
    const finalStrategyBalance = await strategy.balanceOf(addr);

    expect(final3crvBalance).to.equal(initial3crvBalance);
    expect(finalStrategyBalance).to.equal(0);

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("should skip redeem if amount is 0", async () => {
    const addr = RandomAddr;
    const _amount = BN('1000').mul(one);

    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);
    
    setWhitelistedCDO(addr);

    const initial3crvBalance = await erc20_3crv.balanceOf(addr);    
    await deposit(addr, _amount);
    const initialStrategyBalance = await strategy.balanceOf(addr);
    await redeem(addr, BN('0'));
    const final3crvBalance = await erc20_3crv.balanceOf(addr);
    const finalStrategyBalance = await strategy.balanceOf(addr);

    expect(final3crvBalance).to.equal(initial3crvBalance.sub(_amount));
    expect(finalStrategyBalance).to.equal(initialStrategyBalance);

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });

  it("price should be updated based on events", async () => {
    const addr = RandomAddr;
    const _amount = BN('10000').mul(one);

    // price should increase after some harvesting
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);
    
    setWhitelistedCDO(addr);

    // price equals one lp token at the beginning, totalSupply == 0
    const initialPrice = await strategy.price();
    console.log("💲 Initial Price: ", initialPrice.toString());
    
    expect(initialPrice).to.equal(ethers.utils.parseEther('1'));    
    
    await deposit(addr, _amount);

    // distribute CRVs to reward pools, this is not an automatic
    booster.earmarkRewards(POOL_ID_3CRV);

    await network.provider.send("evm_increaseTime", [3600 * 24]); // one day of rewards
    await network.provider.send("evm_mine", []);
    
    await redeemRewards(addr);

    const instantHarvestPrice = await strategy.price();
    console.log("💲 (Immediate) Harvest Price: ", instantHarvestPrice.toString());

    expect(instantHarvestPrice.eq(initialPrice)).to.be.true;

    for(let i = 0; i < 1500; i++) { await network.provider.send("evm_mine", []); } // wait 1500 blocks

    const harvestPrice = await strategy.price();
    console.log("💲 Harvest Price: ", harvestPrice.toString());

    expect(harvestPrice.gt(initialPrice)).to.be.true;

    // price should stay the same when redeeming
    await redeem(addr, BN('5000'));

    const redeemPrice = await strategy.price();
    console.log("💲 After redeem Price: ", redeemPrice.toString());

    expect(redeemPrice.eq(harvestPrice)).to.be.true;
  });
  
  it("redeemRewards should return the minAmounts to use for selling rewards to WETH, WETH to depositToken, and depositToken to curveLpToken", async () => {
    const addr = RandomAddr;
    const _amount = BN('10000').mul(one);
    
    // price should increase after some harvesting
    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);
    
    setWhitelistedCDO(addr);
    
    await deposit(addr, _amount);
    
    // distribute CRVs to reward pools, this is not an automatic
    booster.earmarkRewards(POOL_ID_3CRV);
    
    await network.provider.send("evm_increaseTime", [3600 * 24]); // one day of rewards
    await network.provider.send("evm_mine", []);
    
    const res = await redeemRewards(addr, true);
    expect(res.length).to.be.equal(5);
    expect(res[0].gt(0)).to.be.true;
    expect(res[1].gt(0)).to.be.true;
    // additional rewards are not distributed each time
    expect(res[2].eq(0)).to.be.true;
    expect(res[3].gt(0)).to.be.true;
    expect(res[4].gt(0)).to.be.true;
  });
  
  const setWhitelistedCDO = async (addr) => {
    await helpers.sudoCall(owner.address, strategy, 'setWhitelistedCDO', [addr]);
  }
  
  const deposit = async (addr, amount) => {
    await helpers.sudoCall(addr, erc20_3crv, 'approve', [strategy.address, MAX_UINT]);
    await helpers.sudoCall(addr, strategy, 'deposit', [amount]);
  }
  
  const redeem = async (addr, amount) => {
    await helpers.sudoCall(addr, strategy, 'redeem', [amount]);
  }
  
  const redeemUnderlying = async (addr, amount) => {
    await helpers.sudoCall(addr, strategy, 'redeemUnderlying', [amount]);
  }
  
  const redeemRewards = async (addr, static = false) => {
    // encode params for redeemRewards: uint256[], bool[], uint256, uint256
    const params = [
      [5,5,5],
      [false, false, false],
      3,
      4
    ];
    const extraData = helpers.encodeParams(['uint256[]', 'bool[]', 'uint256', 'uint256'], params);
    if (static) {
      return await helpers.sudoStaticCall(addr, strategy, 'redeemRewards', [extraData]);
    }
    const [a, b, res] = await helpers.sudoCall(addr, strategy, 'redeemRewards', [extraData]);
    return res;
  }
});

