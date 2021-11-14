require("hardhat/config")
const { BigNumber } = require("@ethersproject/bignumber");
const helpers = require("../../scripts/helpers");
const { expect } = require("chai");
const addresses = require("../../lib/addresses");
const { smock } = require('@defi-wonderland/smock');
const { ethers, network } = require("hardhat");

require('chai').use(smock.matchers);

const BN = n => BigNumber.from(n.toString());
const ONE_TOKEN = (n, decimals) => BigNumber.from('10').pow(BigNumber.from(n));
const MAX_UINT = BN('115792089237316195423570985008687907853269984665640564039457584007913129639935');
const POOL_ID_3CRV = 9;
const DEPOSIT_POSITION_3CRV = 1;
const WHALE_3CRV = '0x0f70a91dd4ae5a17868991180c0d4fcdba82f6b7';
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
const TOKEN_3CRV = '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490'
const CVX = '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B';
const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const SUSHI_ROUTER = '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F';

const CVXWETH = [CVX, WETH]
const CRVWETH = [CRV, WETH]
const WETHUSDC = [WETH, USDC]


describe("ConvexStrategy3Token (using 3pool for tests)", async () => {
  
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
    weth2deposit = [SUSHI_ROUTER, WETHUSDC];
  });
  
  beforeEach(async () => {
    strategy = await helpers.deployUpgradableContract('ConvexStrategy3Token', [POOL_ID_3CRV, owner.address, curve_args, [reward_crv, reward_cvx], weth2deposit]);
  });

  afterEach(async () => {
    const balance3crv = await erc20_3crv.balanceOf(RandomAddr);
    await helpers.fundWallets(TOKEN_3CRV, [WHALE_3CRV], RandomAddr, balance3crv);
  });

  it("should redeemRewards (simulate 7 days)", async () => {
    const addr = RandomAddr;
    const _amount = BN('500000').mul(one);

    await helpers.fundWallets(TOKEN_3CRV, [RandomAddr], WHALE_3CRV, _amount);

    setWhitelistedCDO(addr);

    await deposit(addr, _amount);

    // happy path: the strategy earns money! yay!
    
    // TODO: is there any way to calculate rewards and expected return in a PRECISE way?
    // harvest finance and co. seems to not cover the precision of the strategy, testing instead
    // that at least it earns something...

    // forwarding the chain to retrieve some rewards (1 day)
    // simulating the whole process 

    // Using half days is to simulate how we doHardwork in the real world
    let days = 15;
    let oneDay = 3600 * 24;
    const initial3crvBalance = await erc20_3crv.balanceOf(addr);
    for(let i = 0; i < days; i++) {
      // distribute CRVs to reward pools, this is not an automatic
      booster.earmarkRewards(POOL_ID_3CRV);

      await network.provider.send("evm_increaseTime", [oneDay]);
      await network.provider.send("evm_mine", []);

      const roundInitialBalance = await erc20_3crv.balanceOf(addr);
      await redeemRewards(addr);
      const roundFinalBalance = await erc20_3crv.balanceOf(addr);

      // basic expectation
      expect(roundFinalBalance.gt(roundInitialBalance));
    }
    const final3crvBalance = await erc20_3crv.balanceOf(addr);

    // basic expectation
    expect(final3crvBalance.gt(initial3crvBalance));

    const gained = ethers.utils.formatEther(final3crvBalance.sub(initial3crvBalance));
    
    console.log('💵 Total 3crv earned (15 days): ', gained);

    // No token left in the contract
    expect(await erc20_3crv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });
  


  const setWhitelistedCDO = async (addr) => {
    await helpers.sudoCall(owner.address, strategy, 'setWhitelistedCDO', [addr]);
  }

  const deposit = async (addr, amount) => {
    await helpers.sudoCall(addr, erc20_3crv, 'approve', [strategy.address, MAX_UINT]);
    await helpers.sudoCall(addr, strategy, 'deposit', [amount]);
  }
  
  const redeemRewards = async (addr) => {
    const [a,b,res] = await helpers.sudoCall(addr, strategy, 'redeemRewards', []);
    return res;
  }
});