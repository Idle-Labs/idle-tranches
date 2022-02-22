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
const POOL_ID_IBCRV = 29;
const DEPOSIT_POSITION_IBCRV = 0;
const WHALE_IBCRV = '0xd4dfbde97c93e56d1e41325bb428c18299db203f';
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
const TOKEN_IBCRV = '0x5282a4eF67D9C33135340fB3289cc1711c13638C'
const CVX = '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B';
const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const SUSHI_ROUTER = '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F';

const CVXWETH = [CVX, WETH]
const CRVWETH = [CRV, WETH]
const WETHDAI = [WETH, DAI]


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
    erc20_ibcrv = MockERC20.attach(TOKEN_IBCRV);

    booster = await ethers.getContractAt("IBooster", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31");

    // funding the buyer
    await owner.sendTransaction({to: RandomAddr, value: ethers.utils.parseEther("20")});
    // funding the whale to transfer ibcrv
    await owner.sendTransaction({to: WHALE_IBCRV, value: ethers.utils.parseEther("20")});

    curve_args = [DAI, addresses.addr0, DEPOSIT_POSITION_IBCRV]
    reward_cvx = [CVX, SUSHI_ROUTER, CVXWETH];
    reward_crv = [CRV, SUSHI_ROUTER, CRVWETH];
    weth2deposit = [SUSHI_ROUTER, WETHDAI];
  });
  
  beforeEach(async () => {
    strategy = await helpers.deployUpgradableContract('ConvexStrategy3TokenUnderlying', [POOL_ID_IBCRV, owner.address, 0, curve_args, [reward_crv, reward_cvx], weth2deposit]);
  });

  afterEach(async () => {
    const balanceibcrv = await erc20_ibcrv.balanceOf(RandomAddr);
    await helpers.fundWallets(TOKEN_IBCRV, [WHALE_IBCRV], RandomAddr, balanceibcrv);
  });

  it("should redeemRewards (simulate 7 days)", async () => {
    const addr = RandomAddr;
    const _amount = BN('100').mul(one);

    await helpers.fundWallets(TOKEN_IBCRV, [RandomAddr], WHALE_IBCRV, _amount);

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
      booster.earmarkRewards(POOL_ID_IBCRV);

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
    expect(await erc20_ibcrv.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.balanceOf(strategy.address)).to.equal(0);
  });
  


  const setWhitelistedCDO = async (addr) => {
    await helpers.sudoCall(owner.address, strategy, 'setWhitelistedCDO', [addr]);
  }

  const deposit = async (addr, amount) => {
    await helpers.sudoCall(addr, erc20_ibcrv, 'approve', [strategy.address, MAX_UINT]);
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