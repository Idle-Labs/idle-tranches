const { expect } = require("chai");
const { ethers } = require("hardhat");
const {abi: ERC20Abi} = require('../../../artifacts/contracts/interfaces/IERC20Detailed.sol/IERC20Detailed.json')
const {abi: UniswapV2Router02} = require('../../../artifacts/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol/IUniswapV2Router02.json')

// constants
const ORACLE_LOCKING_PERIOD = 300;
const ORACLE_DISPUTE_PERIOD = 7200;
const DEPOSIT_AMOUNT = ethers.utils.parseEther('1');
const uniswapV2RouterV2Address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

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
const getOTokenExpiry = async (vault) => {
  const currentOption = await vault.currentOption()
  const otoken = await ethers.getContractAt('IOtoken', currentOption)
  const expiry = await otoken.expiryTimestamp()

  await increaseTo(expiry.toNumber() + ORACLE_LOCKING_PERIOD + 1)
  
  return expiry
}


const setOpynExpiryPrice = async (underlyingAsset, underlyingSettlePrice, expiry, opynOracle, stethPricer, wethPricerSigner, stethPricerSigner) => {
  
  // set expiry price
  await opynOracle.connect(wethPricerSigner).setExpiryPrice(underlyingAsset, expiry, underlyingSettlePrice)

  
  // set expiry price in oracle
  const receipt = await stethPricer.connect(stethPricerSigner).setExpiryPriceInOracle(expiry)
  const block = await ethers.provider.getBlock(receipt.blockNumber)
  
  await increaseTo(block.timestamp + ORACLE_DISPUTE_PERIOD + 1)
}

const getAsset = async (token, weth, amount, sender, strategyAddress) => {
  const underlyingContract = await ethers.getContractAt(ERC20Abi, token)
  const uniswapV2RouterV2 = await ethers.getContractAt(UniswapV2Router02, uniswapV2RouterV2Address)

  await weth.connect(sender).approve(uniswapV2RouterV2.address, ethers.constants.MaxUint256)
  await underlyingContract.connect(sender).approve(uniswapV2RouterV2.address, ethers.constants.MaxUint256);
  await underlyingContract.connect(sender).approve(strategyAddress, ethers.constants.MaxUint256);
  await uniswapV2RouterV2.connect(sender).swapExactETHForTokens(0, [weth.address, token], sender.address, "9999999999999", {value: amount});
}

function ribbonBaseStrategy (_isSwap ,underlyingToken, gammaOracle, oracleOwner, oracleAsset, chainlinkPricer, pricer, yearnPricerOwner, vaultAddress){

  // contracts
  let vault, opynOracle, stethPricer, IdleRibbonStrategy, strikeSelection, weth;

  // signers
  let wethPricerSigner, stethPricerSigner, keeperSigner, vaultSigner, vaultOwnerSigner;
  let isSwap = _isSwap

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

    // get vault proxy contract
    vault = await ethers.getContractAt('IRibbonVault', vaultAddress);

    // get oracle contract
    opynOracle = await ethers.getContractAt('IChainlinkOracle', gammaOracle, ownerSigner);

    // get oracle contract
    stethPricer = await ethers.getContractAt('IYearnPricer', pricer);

    // get weth contract
    const assetAddress = underlyingToken;
    assetContract = await ethers.getContractAt(ERC20Abi, assetAddress)
    await assetContract.connect(ownerSigner).approve(IdleRibbonStrategy.address, ethers.constants.MaxUint256)

    const wethAddress = await vault.WETH();
    weth = await ethers.getContractAt('IWETH', wethAddress)
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
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [chainlinkPricer] });
    wethPricerSigner = await ethers.provider.getSigner(chainlinkPricer);
    
    // get steth pricer signer
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [yearnPricerOwner], });
    await ownerSigner.sendTransaction({to: yearnPricerOwner, value: ethers.utils.parseEther('10')});
    stethPricerSigner = await ethers.provider.getSigner(yearnPricerOwner);

    // get oracle owner signer
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [oracleOwner] });
    const oracleOwnerSigner = await ethers.provider.getSigner(oracleOwner);
    await ownerSigner.sendTransaction({to: oracleOwnerSigner._address, value: ethers.utils.parseEther('10')});

    // get vault owner
    const vaultOwner = await vault.owner()
    await network.provider.request({ method: 'hardhat_impersonateAccount', params: [vaultOwner] });
    vaultOwnerSigner = await ethers.provider.getSigner(vaultOwner);
    await ownerSigner.sendTransaction({to: vaultOwnerSigner._address, value: ethers.utils.parseEther('10')});

    // force send ether
    await forceSend.connect(ownerSigner).go(chainlinkPricer, { value: ethers.utils.parseEther('10') });

    // set asset pricer
    await opynOracle.connect(oracleOwnerSigner).setAssetPricer(oracleAsset , chainlinkPricer);

    // initialize strategy proxy
    await IdleRibbonStrategy.connect(ownerSigner).initialize(assetAddress, underlyingToken, vaultAddress, ownerSigner.address);
    await IdleRibbonStrategy.connect(ownerSigner).setWhitelistedCDO(ownerSigner.address);

    // get strike selection
    const strikeSelectionAddress = await vault.connect(ownerSigner).strikeSelection();
    strikeSelection = await ethers.getContractAt('IDeltaStrikeSelection', strikeSelectionAddress);

    // get underlying asset
    if(underlyingToken.toLowerCase() === weth.address.toLowerCase()) {
      await weth.connect(ownerSigner).deposit({ value: DEPOSIT_AMOUNT })
    } else {
      await getAsset(underlyingToken, weth, DEPOSIT_AMOUNT, ownerSigner, IdleRibbonStrategy.address)
    }

    // update cap
    const depositAmount = await assetContract.balanceOf(ownerSigner.address);
    const currentCap = await vault.cap()
    await vault.connect(vaultOwnerSigner).setCap(currentCap.add(depositAmount))

    // check if deployed correctly
    expect(ethers.utils.isAddress(IdleRibbonStrategy.address)).to.eq(true);
  });

  it("Check strategy APR", async () => {

    const {round}= await vault.vaultState()
    const previousWeekStartAmount = await vault.roundPricePerShare(round - 2);
    const previousWeekEndAmount = await vault.roundPricePerShare(round - 1);
    const MAX_APR_PERC = ethers.BigNumber.from(100000)
    const weekApr = (previousWeekEndAmount.mul(MAX_APR_PERC).div(previousWeekStartAmount)).sub(MAX_APR_PERC);
    const expectedApr = weekApr.mul(ethers.BigNumber.from(52)) 

    const apr = await IdleRibbonStrategy.getApr();
    expect(apr.eq(expectedApr)).to.be.true
  });

  it("Deposit in Ribbon tranche", async () => {
    
    // get signers
    const [ownerSigner] = await ethers.getSigners();

    // deposit eth into the vault
    const sharesBefore = await IdleRibbonStrategy.totalSupply();
    const depositAmount = await assetContract.balanceOf(ownerSigner.address);
    await IdleRibbonStrategy.connect(ownerSigner).deposit(depositAmount);
    
    // update oracle
    const firstOptionExpiry = Math.floor(+getOptionExpiryDate() / 1000);
    const [firstOptionStrike] = await strikeSelection.getStrikePrice(firstOptionExpiry, false); // call option
    const expiry = await  getOTokenExpiry(vault)
    const price = firstOptionStrike.sub(1)
    await setOpynExpiryPrice(oracleAsset, price, expiry, opynOracle, stethPricer, wethPricerSigner, stethPricerSigner);
    if(isSwap){
      await vault.connect(ownerSigner).closeRound();
      await vault.connect(keeperSigner).commitNextOption();
    } else {
      await vault.connect(keeperSigner).commitAndClose();
    }
    await vault.connect(keeperSigner).rollToNextOption(); // starts auction
    
    // check shares and apr
    const sharesAfter = await IdleRibbonStrategy.totalSupply();
    expect(sharesAfter.gt(sharesBefore));

  });
  
  it("Initiate redeem deposit from Ribbon strategy", async () => {

    // get signers
    const [ownerSigner] = await ethers.getSigners();

    // initialize withdraw
    const withdrawlsBefore = await vault.connect(ownerSigner).withdrawals(IdleRibbonStrategy.address);
    const shares = await vault.connect(ownerSigner).shares(IdleRibbonStrategy.address)
    await IdleRibbonStrategy.connect(ownerSigner).redeem(shares);

    // check round and shares
    const withdrawlsAfter = await vault.connect(ownerSigner).withdrawals(IdleRibbonStrategy.address);

    // expect(balanceAfter).gt(balanceBefore);
    expect(withdrawlsAfter.round).gt(withdrawlsBefore.round);
    expect(withdrawlsAfter.shares).gt(withdrawlsBefore.shares);
  })

  it("Complete redeem deposit from Ribbon strategy", async () => {

    // get signers
    const [ownerSigner] = await ethers.getSigners();
    
    // update oracle
    const assetAddress = underlyingToken;
    const assetContract = await ethers.getContractAt(ERC20Abi, assetAddress)
    const firstOptionExpiry = Math.floor(+getOptionExpiryDate() / 1000);
    const [firstOptionStrike] = await strikeSelection.getStrikePrice(firstOptionExpiry, false); // call option
    const price = firstOptionStrike.sub(1)
    const expiry = await getOTokenExpiry(vault)
    await setOpynExpiryPrice(oracleAsset, price, expiry, opynOracle, stethPricer, wethPricerSigner, stethPricerSigner);

    if(isSwap){
      await vault.connect(ownerSigner).closeRound();
      await vault.connect(keeperSigner).commitNextOption();
    } else {
      await vault.connect(keeperSigner).commitAndClose();
    }
    await vault.connect(keeperSigner).rollToNextOption();
    
    // complete withdraw
    const balanceAssetBefore = await assetContract.balanceOf(ownerSigner.address)
    await IdleRibbonStrategy.connect(ownerSigner).completeRedeem(); // vault.completeWithdraw
    
    // check withdraw
    const balanceAssetAfter = await assetContract.balanceOf(ownerSigner.address)
    expect((balanceAssetAfter).gt(balanceAssetBefore)).eq(true);
  });
}
module.exports = ribbonBaseStrategy
