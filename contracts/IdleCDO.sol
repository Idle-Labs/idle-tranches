// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "hardhat/console.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Permit.sol";

import "./GuardedLaunchUpgradable.sol";
import "./IdleCDOTranche.sol";
import "./IdleCDOStorage.sol";

contract IdleCDO is Initializable, PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  function initialize(
    uint256 _limit, address _guardedToken, address _governanceFund, // GuardedLaunch args
    address _rebalancer,
    address _strategy,
    uint256 _trancheSplitRatio // for AA tranches so eg 10000 means 10% interest to AA and 90% BB
  ) public initializer {
    // Initialize contracts
    PausableUpgradeable.__Pausable_init();
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _guardedToken, _governanceFund);
    // Set CDO params
    trancheSplitRatio = _trancheSplitRatio;
    rebalancer = _rebalancer;
    strategy = _strategy;
    oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    token = _guardedToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // idle = address(0x875773784Af8135eA0ef43b5a374AaD105c5D39e);
    // Deploy Tranches tokens
    AATranche = address(new IdleCDOTranche("Idle CDO AA Tranche", "IDLE_CDO_AA"));
    BBTranche = address(new IdleCDOTranche("Idle CDO BB Tranche", "IDLE_CDO_BB"));
    // Set flags
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;
    skipDefaultCheck = false;
    // Set allowance for strategy
    IERC20Detailed(_guardedToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    // Fetch strategy and tranches prices
    uint256 _lastStrategyPrice = _strategyPrice();
    lastStrategyPrice = _lastStrategyPrice;
    lastAAPrice = _priceAATranche();
    lastBBPrice = _priceBBTranche();
  }

  // Public methods
  // User should approve this contract first to spend IdleTokens idleToken
  function depositAA(uint256 _amount) external whenNotPaused returns (uint256) {
    return _deposit(_amount, AATranche);
  }

  function depositBB(uint256 _amount) external whenNotPaused returns (uint256) {
    return _deposit(_amount, BBTranche);
  }

  function withdrawAA(uint256 _amount) external returns (uint256) {
    require(!paused() || allowAAWithdraw, 'IDLE:AA_!ALLOWED');
    return _withdraw(_amount, AATranche);
  }

  function withdrawBB(uint256 _amount) external returns (uint256) {
    require(!paused() || allowBBWithdraw, 'IDLE:BB_!ALLOWED');
    return _withdraw(_amount, BBTranche);
  }

  function tranchePrice(address _tranche) external view returns (uint256) {
    return _tranchePrice(_tranche);
  }

  function lastTranchePrice(address _tranche) external view returns (uint256) {
    return _lastTranchePrice(_tranche);
  }

  function _lastTranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? lastAAPrice : lastBBPrice;
  }

  function getContractValue() public override view returns (uint256) {
    return _balanceAATranche() + _balanceBBTranche();
  }

  function getApr(address _tranche) external view returns (uint256) {
    uint256 stratApr = IIdleCDOStrategy(strategy).getApr();
    uint256 AATrancheApr = stratApr * trancheSplitRatio / FULL_ALLOC;
    uint256 BBTrancheApr = stratApr - AATrancheApr;
    // uint256 currAARatio = _balanceAATranche() * FULL_ALLOC / _balanceBBTranche();

    // TODO

    return _tranche == AATranche ? AATrancheApr : BBTrancheApr;
  }

  function getAARatio() public view returns (uint256) {
    return _balanceAATranche() * FULL_ALLOC / _balanceBBTranche();
  }

  function getBBRatio() external view returns (uint256) {
    return FULL_ALLOC - getAARatio();
  }

  // Apr at ideal trancheSplitRatio balance between AA and BB
  function getIdealApr(address _tranche) external view returns (uint256) {
    uint256 stratApr = IIdleCDOStrategy(strategy).getApr();
    uint256 AATrancheApr = stratApr * trancheSplitRatio / FULL_ALLOC;
    uint256 BBTrancheApr = stratApr - AATrancheApr;

    return _tranche == AATranche ? AATrancheApr : BBTrancheApr;
  }

  // internal
  // ###############
  function _strategyPrice() internal view returns (uint256) {
    return IIdleCDOStrategy(strategy).price(address(this));
  }

  function _deposit(uint256 _amount, address _tranche) internal returns (uint256 _minted) {
    _guarded(_amount);
    _updateCallerBlock();
    _checkDefault();
    _minted = _amount * oneToken / _lastTranchePrice(_tranche);
    IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
    IdleCDOTranche(_tranche).mint(msg.sender, _minted);
  }

  // amount in trancheXXAmount
  function _withdraw(uint256 _amount, address _tranche) internal returns (uint256 toRedeem) {
    _checkSameTx();
    _checkDefault();
    if (_amount == 0) {
      _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
    }

    uint256 balanceUnderlying = _contractTokenBalance(token);
    toRedeem = _amount * _lastTranchePrice(_tranche) / oneToken;
    if (toRedeem > balanceUnderlying) {
      _liquidate(toRedeem - balanceUnderlying, revertIfTooLow);
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);
    // send underlying
    IERC20Detailed(token).safeTransfer(msg.sender, toRedeem);
  }

  function _checkDefault() internal {
    uint256 currPrice = _strategyPrice();
    if (!skipDefaultCheck) {
      require(lastStrategyPrice >= currPrice, "IDLE:DEFAULT_WAIT_SHUTDOWN");
    }
    lastStrategyPrice = currPrice;
  }

  // this should liquidate at least _amount or revert?
  // _amount is in underlying
  function _liquidate(uint256 _amount, bool revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (revertIfNeeded) {
      require(_redeemedTokens >= _amount - 1, 'IDLE:TOO_LOW');
    }
  }

  function _tranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? _priceAATranche() : _priceBBTranche();
  }

  function _priceAATranche() internal view returns (uint256) {
    // 1 + ((price - 1) * trancheSplitRatio/FULL_ALLOC)
    return oneToken + ((_strategyPrice() - oneToken) * trancheSplitRatio / FULL_ALLOC);
  }

  function _priceBBTranche() internal view returns (uint256) {
    // 1 + ((price - 1) * (FULL_ALLOC-trancheSplitRatio)/FULL_ALLOC)
    return oneToken + ((_strategyPrice() - oneToken) * (FULL_ALLOC - trancheSplitRatio) / FULL_ALLOC);
  }

  function _balanceAATranche() internal view returns (uint256) {
    return IdleCDOTranche(AATranche).totalSupply() * _priceAATranche() / oneToken;
  }

  function _balanceBBTranche() internal view returns (uint256) {
    return IdleCDOTranche(BBTranche).totalSupply() * _priceBBTranche() / oneToken;
  }

  // Permit and Deposit support
  // ###################
  function permitAndDepositAA(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
    _deposit(amount, AATranche);
  }

  function permitAndDepositBB(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
    _deposit(amount, BBTranche);
  }

  function permitEIP2612AndDepositAA(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), amount, expiry, v, r, s);
    _deposit(amount, AATranche);
  }

  function permitEIP2612AndDepositUnlimitedAA(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), type(uint256).max, expiry, v, r, s);
    _deposit(amount, AATranche);
  }

  function permitEIP2612AndDepositBB(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), amount, expiry, v, r, s);
    _deposit(amount, BBTranche);
  }

  function permitEIP2612AndDepositUnlimitedBB(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), type(uint256).max, expiry, v, r, s);
    _deposit(amount, BBTranche);
  }

  // Protected
  // ###################
  function rebalance() external {
    require(msg.sender == rebalancer, "IDLE:!AUTH");

    uint256 balanceUnderlying = IERC20Detailed(token).balanceOf(address(this));
    IIdleCDOStrategy(strategy).deposit(balanceUnderlying);

    // TODO get fees?
  }

  function liquidate(uint256 _amount, bool revertIfNeeded) external returns (uint256) {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    return _liquidate(_amount, revertIfNeeded);
  }

  function harvest(bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");

    address[] memory rewards = IIdleCDOStrategy(strategy).getRewardTokens();
    for (uint256 i = 0; i < rewards.length; i++) {
      address rewardToken = rewards[i];
      uint256 _currentBalance = _contractTokenBalance(rewardToken);
      if (rewardToken == idle || _skipReward[i] || _currentBalance == 0) { continue; }

      address[] memory _path = new address[](3);
      _path[0] = rewardToken;
      _path[1] = weth;
      _path[2] = token;
      IERC20Detailed(rewardToken).safeIncreaseAllowance(address(uniswapRouterV2), _currentBalance);

      uniswapRouterV2.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        _currentBalance,
        _minAmount[i],
        _path,
        address(this),
        block.timestamp + 1
      );
    }

    IIdleCDOStrategy(strategy).deposit(_contractTokenBalance(token));

    // TODO get fees?
  }

  // onlyOwner
  // ###################
  function setAllowAAWithdraw(bool _allowed) external onlyOwner {
    allowAAWithdraw = _allowed;
  }

  function setAllowBBWithdraw(bool _allowed) external onlyOwner {
    allowBBWithdraw = _allowed;
  }

  function setSkipDefaultCheck(bool _allowed) external onlyOwner {
    skipDefaultCheck = _allowed;
  }

  function setRevertIfTooLow(bool _allowed) external onlyOwner {
    revertIfTooLow = _allowed;
  }

  function setStrategy(address _strategy) external onlyOwner {
    require(_strategy != address(0), 'IDLE:IS_0');
    IERC20Detailed _token = IERC20Detailed(token);
    _token.safeApprove(strategy, 0);
    strategy = _strategy;
    _token.safeIncreaseAllowance(_strategy, type(uint256).max);
  }

  function setRebalancer(address _rebalancer) external onlyOwner {
    require(_rebalancer != address(0), 'IDLE:IS_0');
    rebalancer = _rebalancer;
  }

  function emergencyShutdown() external onlyOwner {
    _pause();
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    skipDefaultCheck = false;
    revertIfTooLow = true;
  }

  function pause() external onlyOwner {
    _pause();
  }

  // helpers
  // ###################
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
  }

  // Set last caller and block.number hash. This should be called at the beginning of the first function
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  // Check that the second function is not called in the same block from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "SAME_BLOCK");
  }
}
