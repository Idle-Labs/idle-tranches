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
const POOL_ID_CRV3EUR = 60;
const DEPOSIT_POSITION_CRV3EUR = 0;
const WHALE_CRV3EUR = '0x7c1124184c6f0952e5fb4acd1246ad1197bff1c7';
const FEI = '0x956f47f50a910163d8bf957cf5846d573e7f87ca';
const agEUR = '0x1a7e4e63778b4f12a199c062f3efdd288afcbce8';
const TOKEN_CRV3EUR = '0xb9446c4Ef5EBE66268dA6700D26f96273DE3d571';
const CVX = '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B';
const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const UNI_ROUTER = '0x7a250d5630b4cf539739df2c5dacb4c659f2488d';
const SUSHI_ROUTER = '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F';

const CVXWETH = [CVX, WETH]
const CRVWETH = [CRV, WETH]
const WETHAGEUR = [WETH, FEI, agEUR]


describe("ConvexStrategyMeta3Token (using 3eur for tests)", async () => {
  
  before(async () => {
    // setup
    signers = await ethers.getSigners();
    owner = signers[0];
    Random = signers[1];
    RandomAddr = Random.address;
    Random2Addr = signers[2].address;

    one = ONE_TOKEN(18);

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    erc20_CRV3EUR = MockERC20.attach(TOKEN_CRV3EUR);

    booster = await ethers.getContractAt("IBooster", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31");

    // funding the buyer
    await owner.sendTransaction({to: RandomAddr, value: ethers.utils.parseEther("20")});
    // funding the whale to transfer CRV3EUR
    await owner.sendTransaction({to: WHALE_CRV3EUR, value: ethers.utils.parseEther("20")});

    curve_args = [agEUR, addresses.addr0, DEPOSIT_POSITION_CRV3EUR]
    reward_cvx = [CVX, SUSHI_ROUTER, CVXWETH];
    reward_crv = [CRV, SUSHI_ROUTER, CRVWETH];
    weth2deposit = [UNI_ROUTER, WETHAGEUR];
  });
  
  beforeEach(async () => {
    strategy = await helpers.deployUpgradableContract('ConvexStrategyPlainPool3Token', [POOL_ID_CRV3EUR, owner.address, 0, curve_args, [reward_crv, reward_cvx], weth2deposit]);
  });

  afterEach(async () => {
    const balanceCRV3EUR = await erc20_CRV3EUR.balanceOf(RandomAddr);
    await helpers.fundWallets(TOKEN_CRV3EUR, [WHALE_CRV3EUR], RandomAddr, balanceCRV3EUR);
  });

  it("should redeemRewards (simulate 7 days)", async () => {
    const addr = RandomAddr;
    const _amount = BN('30000').mul(one);

    await helpers.fundWallets(TOKEN_CRV3EUR, [RandomAddr], WHALE_CRV3EUR, _amount);

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
    const initialSharePrice = await strategy.price();
    for(let i = 0; i < days; i++) {
      // distribute CRVs to reward pools, this is not an automatic
      booster.earmarkRewards(POOL_ID_CRV3EUR);

      await network.provider.send("evm_increaseTime", [oneDay]);
      await network.provider.send("evm_mine", []);

      const roundInitialPrice = await strategy.price();
      await redeemRewards(addr);
      const roundFinalPrice = await strategy.price();

      // basic expectation
      expect(roundFinalPrice.gt(roundInitialPrice)).to.be.true;
    }
    const finalSharePrice = await strategy.price();

    // basic expectation
    expect(finalSharePrice.gt(initialSharePrice)).to.be.true;

    const priceGain = ethers.utils.formatEther(finalSharePrice.sub(initialSharePrice));
    
    console.log('💵 Price gain (15 days): ', priceGain);

    // No token left in the contract
    expect(await erc20_CRV3EUR.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });
  


  const setWhitelistedCDO = async (addr) => {
    await helpers.sudoCall(owner.address, strategy, 'setWhitelistedCDO', [addr]);
  }

  const deposit = async (addr, amount) => {
    await helpers.sudoCall(addr, erc20_CRV3EUR, 'approve', [strategy.address, MAX_UINT]);
    await helpers.sudoCall(addr, strategy, 'deposit', [amount]);
  }
  
  const redeemRewards = async (addr) => {
    // encode params for redeemRewards: uint256[], bool[], uint256, uint256
    const params = [
      [5, 5, 5],
      [false, false, false],
      3,
      4
    ];
    const extraData = helpers.encodeParams(['uint256[]', 'bool[]', 'uint256', 'uint256'], params);
    const [a, b, res] = await helpers.sudoCall(addr, strategy, 'redeemRewards', [extraData]);
    return res;
  }
});