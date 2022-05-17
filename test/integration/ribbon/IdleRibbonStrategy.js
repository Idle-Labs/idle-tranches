const { expect } = require("chai");
const { ethers } = require("hardhat");

// addresses
const GAMMA_ORACLE = '0x789cD7AB3742e23Ce0952F6Bc3Eb3A73A0E08833';
const ORACLE_OWNER = '0x2FCb2fc8dD68c48F406825255B4446EDFbD3e140';
const CHAINLINK_WETH_PRICER_STETH = '0x128cE9B4D97A6550905dE7d9Abc2b8C747b0996C';
const WSTETH_PRICER = '0x4661951D252993AFa69b36bcc7Ba7da4a48813bF';
const YEARN_PRICER_OWNER = '0xfacb407914655562d6619b0048a612B1795dF783';
const VAULT_ADDRESS = '0x25751853eab4d0eb3652b5eb6ecb102a2789644b';

// constants
const ORACLE_LOCKING_PERIOD = 300;
const ORACLE_DISPUTE_PERIOD = 7200;
const SECONDS_IN_DAY = 24 * 60 * 60;
const DEPOSIT_AMOUNT = ethers.utils.parseEther('1');
const INITIAL_AMOUNT = ethers.utils.parseEther('0.0000001')

// npx hardhat test test/integration/ribbon/IdleRibbonStrategy.js

// 5 for friday
const getOptionExpiryDate = () => {
  const dt = new Date();
  const resultDate = new Date(dt.getTime());
  resultDate.setDate(dt.getDate() + 7 + ((7 + 5 - dt.getDay() - 1) % 7) + 1);
  resultDate.setHours(8, 0, 0, 0);
  return resultDate;
}

const increase = async (time) => {
  await ethers.provider.send('evm_increaseTime', [time])
  await ethers.provider.send('evm_mine', [])
}

const increaseTo = async (amount) => {
  const target = ethers.BigNumber.from(amount)
  const block = await ethers.provider.getBlock('latest')
  const now = ethers.BigNumber.from(block.timestamp)
  const duration = ethers.BigNumber.from(target.sub(now))

  await increase(duration.toNumber())
}

const setOpynExpiryPrice = async (vault, underlyingAsset, underlyingSettlePrice, opynOracle, stethPricer, wethPricerSigner, stethPricerSigner) => {

  // increase time (oracle locking period)
  const currentOption = await vault.currentOption()
  const otoken = await ethers.getContractAt('IOtoken', currentOption)
  const expiry = await otoken.expiryTimestamp()
  await increaseTo(expiry.toNumber() + ORACLE_LOCKING_PERIOD + 1)

  // set expiry price
  await opynOracle.connect(wethPricerSigner).setExpiryPrice(underlyingAsset, expiry, underlyingSettlePrice)

  // set expiry price in oracle
  const receipt = await stethPricer.connect(stethPricerSigner).setExpiryPriceInOracle(expiry)

  // increase time (oracle dispute period)
  const block = await ethers.provider.getBlock(receipt.blockNumber)
  await increaseTo(block.timestamp + ORACLE_DISPUTE_PERIOD + 1)
}

describe.only("IdleRibbonStrategy", function () {

  // contracts
  let vault, opynOracle, stethPricer, IdleRibbonStrategy, strikeSelection, weth;

  // signers
  let wethPricerSigner, stethPricerSigner, keeperSigner, vaultSigner;

  before(async () => {

    // get signers
    const [ownerSigner, , proxyAdmin] = await ethers.getSigners();

    // deploy strategy proxy
    const IdleRibbonStrategyFactory = await ethers.getContractFactory("IdleRibbonStrategy");
    const IdleRibbonStrategyLogic = await IdleRibbonStrategyFactory.deploy();
    const TransparentUpgradableProxyFactory = await ethers.getContractFactory("TransparentUpgradeableProxy");
    const TransparentUpgradableProxy = await TransparentUpgradableProxyFactory.deploy(IdleRibbonStrategyLogic.address, proxyAdmin.address, "0x");
    await TransparentUpgradableProxy.deployed();
    
    // get strategy proxy contract
    IdleRibbonStrategy = await ethers.getContractAt('IdleRibbonStrategy', TransparentUpgradableProxy.address);
    await ownerSigner.sendTransaction({to: IdleRibbonStrategy.address, value: ethers.utils.parseEther('10')});

    // get vault proxy contract
    vault = await ethers.getContractAt('IRibbonThetaSTETHVault', VAULT_ADDRESS);
    
    // get oracle contract
    opynOracle = await ethers.getContractAt('IChainlinkOracle', GAMMA_ORACLE, ownerSigner);

    // get oracle contract
    stethPricer = await ethers.getContractAt('IYearnPricer', WSTETH_PRICER);

    // get weth contract
    const assetAddress = await vault.WETH();
    weth = await ethers.getContractAt('IWETH', assetAddress)
    await weth.connect(ownerSigner).approve(IdleRibbonStrategy.address, ethers.constants.MaxUint256)

    // get force send contract
    const forceSendContract = await ethers.getContractFactory('ForceSend');
    const forceSend = await forceSendContract.deploy();

    // get vault signer
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [vault.address] });
    vaultSigner = await ethers.provider.getSigner(vault.address);
    await ownerSigner.sendTransaction({to: vaultSigner._address, value: ethers.utils.parseEther('10')});
    
    // get keeper signer
    const keeperAddress = await vault.keeper();
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [keeperAddress] });
    keeperSigner = await ethers.provider.getSigner(keeperAddress);

    // get weth pricer signer
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [CHAINLINK_WETH_PRICER_STETH] });
    wethPricerSigner = await ethers.provider.getSigner(CHAINLINK_WETH_PRICER_STETH);
    
    // get steth pricer signer
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [YEARN_PRICER_OWNER], });
    await ownerSigner.sendTransaction({to: YEARN_PRICER_OWNER, value: ethers.utils.parseEther('10')});
    stethPricerSigner = await ethers.provider.getSigner(YEARN_PRICER_OWNER);

    // get oracle owner signer
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [ORACLE_OWNER] });
    const oracleOwnerSigner = await ethers.provider.getSigner(ORACLE_OWNER);
    await ownerSigner.sendTransaction({to: oracleOwnerSigner._address, value: ethers.utils.parseEther('10')});

    // force send ether
    await forceSend.connect(ownerSigner).go(CHAINLINK_WETH_PRICER_STETH, { value: ethers.utils.parseEther('10') });

    // set asset pricer
    await opynOracle.connect(oracleOwnerSigner).setAssetPricer(assetAddress, CHAINLINK_WETH_PRICER_STETH);

    // initialize strategy proxy
    await IdleRibbonStrategy.connect(ownerSigner).initialize(assetAddress, assetAddress, VAULT_ADDRESS, ownerSigner.address);
    await IdleRibbonStrategy.connect(ownerSigner).setWhitelistedCDO(ownerSigner.address);

    // get strike selection
    const strikeSelectionAddress = await vault.connect(ownerSigner).strikeSelection();
    strikeSelection = await ethers.getContractAt('IDeltaStrikeSelection', strikeSelectionAddress);

  });

  it("Check Ribbon strategy contract", async () => {
    // check if deployed correctly
    expect(ethers.utils.isAddress(IdleRibbonStrategy.address)).to.eq(true);

    // check parameters initialized correctly
    expect(await IdleRibbonStrategy.totalDeposited()).eq(0);
  });

  it("Check strategy APR", async () => {

    // get signers
    const [ownerSigner] = await ethers.getSigners();

    // sets lastIndexedTime and lastIndexAmount
    await weth.connect(ownerSigner).deposit({ value: INITIAL_AMOUNT })
    await IdleRibbonStrategy.connect(ownerSigner).deposit(INITIAL_AMOUNT);
    expect(await IdleRibbonStrategy.lastIndexAmount()).gt(0);
    expect(await IdleRibbonStrategy.lastIndexedTime()).gt(0);
    expect(await IdleRibbonStrategy.lastApr()).eq(0);

    // check initial apr
    const aprInitial = await IdleRibbonStrategy.getApr();
    expect(aprInitial).eq(0);
    
    // check apr not changing
    await increase(4 * SECONDS_IN_DAY)
    const aprAfter = await IdleRibbonStrategy.getApr();
    expect(aprAfter).eq(0);

  });

  it("Deposit in Ribbon tranche", async () => {
    
    // get signers
    const [ownerSigner, userSigner] = await ethers.getSigners();

    // deposit eth into the vault
    const sharesBefore = await IdleRibbonStrategy.totalSupply();
    const aprBefore = await IdleRibbonStrategy.getApr();
    await weth.connect(ownerSigner).deposit({ value: DEPOSIT_AMOUNT })
    await IdleRibbonStrategy.connect(ownerSigner).deposit(DEPOSIT_AMOUNT);
    
    // update oracle
    const assetAddress = await vault.WETH();
    const firstOptionExpiry = Math.floor(+getOptionExpiryDate() / 1000);
    const [firstOptionStrike] = await strikeSelection.getStrikePrice(firstOptionExpiry, false); // call option
    await setOpynExpiryPrice(vault, assetAddress, firstOptionStrike.add(INITIAL_AMOUNT), opynOracle, stethPricer, wethPricerSigner, stethPricerSigner);
    await vault.connect(userSigner).commitAndClose();
    await vault.connect(keeperSigner).rollToNextOption();
    
    // check shares and apr
    const sharesAfter = await IdleRibbonStrategy.totalSupply();
    expect(sharesAfter.gt(sharesBefore));
    const aprAfter = await IdleRibbonStrategy.getApr();
    expect(aprBefore).lt(aprAfter);

  });
  
  it("Initiate redeem deposit from Ribbon strategy", async () => {

    // get signers
    const [ownerSigner] = await ethers.getSigners();

    // initialize withdraw
    const balanceBefore = await vault.balanceOf(IdleRibbonStrategy.address);
    const withdrawlsBefore = await vault.connect(ownerSigner).withdrawals(IdleRibbonStrategy.address);
    await IdleRibbonStrategy.connect(ownerSigner).redeem(DEPOSIT_AMOUNT);
    
    // check round and shares
    const balanceAfter = await vault.balanceOf(IdleRibbonStrategy.address);
    const withdrawlsAfter = await vault.connect(ownerSigner).withdrawals(IdleRibbonStrategy.address);
    expect(balanceAfter).gt(balanceBefore);
    expect(withdrawlsAfter.round).gt(withdrawlsBefore.round);
    expect(withdrawlsAfter.shares).gt(withdrawlsBefore.shares);

  })

  it("Complete redeem deposit from Ribbon strategy", async () => {

    // get signers
    const [ownerSigner, userSigner] = await ethers.getSigners();
    
    // update oracle
    const assetAddress = await vault.WETH();
    const weth = await ethers.getContractAt('IWETH', assetAddress)
    const firstOptionExpiry = Math.floor(+getOptionExpiryDate() / 1000);
    const [firstOptionStrike] = await strikeSelection.getStrikePrice(firstOptionExpiry, false); // call option
    await setOpynExpiryPrice(vault, assetAddress, firstOptionStrike.add(INITIAL_AMOUNT), opynOracle, stethPricer, wethPricerSigner, stethPricerSigner);
    await vault.connect(userSigner).commitAndClose();
    await vault.connect(keeperSigner).rollToNextOption();
    
    // complete withdraw
    const sharesBefore = await IdleRibbonStrategy.totalSupply();
    const totalDepositedBefore = await IdleRibbonStrategy.totalDeposited();
    const balanceWethBefore = await weth.balanceOf(ownerSigner.address)
    await IdleRibbonStrategy.connect(ownerSigner).completeRedeem();
    
    // check withdraw
    const balanceWethAfter = await weth.balanceOf(ownerSigner.address)
    const sharesAfter = await IdleRibbonStrategy.totalSupply();
    const totalDepositedAfter = await IdleRibbonStrategy.totalDeposited();
    expect((balanceWethAfter).gt(balanceWethBefore)).eq(true);
    expect(sharesAfter).lt(sharesBefore);
    expect((totalDepositedAfter).lt(totalDepositedBefore)).eq(true);
  
    // debug
    const perc = (balanceWethAfter.sub(balanceWethBefore)).mul(1e4).div(DEPOSIT_AMOUNT).toNumber()
    console.log('apr', (perc / 100).toFixed(2), '%')

  });

});
