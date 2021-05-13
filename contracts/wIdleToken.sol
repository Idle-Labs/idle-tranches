// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import "./interfaces/IIdleTokenV3_1.sol";
import "./interfaces/IERC20Permit.sol";
import "./GuardedLaunchUpgradable.sol";
import "./wIdleTokenStorage.sol";
import "hardhat/console.sol";

contract wIdleToken is Initializable, ERC20Upgradeable, PausableUpgradeable, GuardedLaunchUpgradable, wIdleTokenStorage {
  using SafeERC20 for ERC20;

  function initialize(
    uint256 _limit, address _guardedToken, address _governanceFund, // GuardedLaunch args
    address _rebalancer,
    address _idleToken,
    string memory name, string memory symbol
  ) public initializer {
    ERC20Upgradeable.__ERC20_init(name, symbol);
    PausableUpgradeable.__Pausable_init();
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _guardedToken, _governanceFund);

    rebalancer = _rebalancer;
    idleToken = _idleToken;
    oneToken = 10**(ERC20(_guardedToken).decimals());
    token = _guardedToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    idle = address(0x875773784Af8135eA0ef43b5a374AaD105c5D39e);
    revertIfNeeded = true;

    ERC20(token).safeIncreaseAllowance(idleToken, type(uint256).max);
    lastPrice = _strategyPrice();
  }

  // Public methods
  // User should approve this contract first to spend IdleTokens idleToken
  function deposit(uint256 _amount) external returns (uint256) {
    return _deposit(_amount);
  }

  function withdraw(uint256 _wIdleTokenAmount) external returns (uint256 toRedeem) {
    _checkSameTx();
    _burn(msg.sender, _wIdleTokenAymount);
    // TODO is it correct? should be in order to always have the correct balance
    IIdleTokenV3_1(idleToken).redeemIdleToken(0);

    if (_wIdleTokenAmount == 0) {
      _wIdleTokenAmount = balanceOf(msg.sender);
    }
    uint256 balanceUnderlying = _contractTokenBalance(token);
    toRedeem = _wIdleTokenAmount * price() / ONE_18;
    if (toRedeem > balanceUnderlying) {
      _liquidate(toRedeem - balanceUnderlying, revertIfNeeded);
    }
    ERC20(token).safeTransfer(msg.sender, toRedeem);

    // TODO IDLE tokens?
  }

  // view methods
  function getApr(address _tranche) external view returns (uint256) {
    // return IIdleTokenV3_1(idleToken).getAvgAPR();
  }

  function price() public view returns (uint256) {
    return contractBalance() * oneToken / totalSupply();
  }

  function contractBalance() public view returns (uint256) {
    uint256 tokenBal = _contractTokenBalance(token);
    tokenBal = tokenBal + (
      // balance in Idle in underlyings
      _contractTokenBalance(idleToken) * _strategyPrice() / ONE_18
    );
    // add govTokens balance in underlying (flash loan resistant)
    // if we only have IDLE what do we do?
  }

  function getContractValue() public override view returns (uint256) {
    // TODO
  }

  // internal
  // ###############
  function _deposit(uint256 _amount) internal whenNotPaused returns (uint256 minted) {
    _guarded(_amount);
    _updateCallerBlock();
    _checkDefault();

    // get accrued gov tokens to the contract
    IIdleTokenV3_1(idleToken).redeemIdleToken(0);

    uint256 wIdlePrice = price();
    ERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
    minted = _amount * ONE_18 / wIdlePrice;

    uint256 supply = totalSupply();
    // contractAvgPrice = (contractAvgPrice * oldBalance) + (price * newQty)) / totBalance
    contractAvgPrice = (contractAvgPrice * supply) + (wIdlePrice * minted) / (supply + minted);
    // TODO is needed ?
    contractDepositedTokens = contractDepositedTokens + _amount;
    _mint(msg.sender, minted);
  }

  function _checkDefault() internal {
    uint256 currPrice = _strategyPrice();
    if (!skipDefaultCheck) {
      require(lastPrice > currPrice, "IDLE:PRICE_DOWN");
    }
    lastPrice = currPrice;
  }

  function _strategyPrice() internal view returns (uint256) {
    return IIdleTokenV3_1(idleToken).tokenPriceWithFee(address(this));
  }
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return ERC20(_token).balanceOf(address(this));
  }

  // this should liquidate at least _amount or revert
  // _amount is in underlying
  function _liquidate(uint256 _amount, bool _revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    uint256 idleTokens = _amount * oneToken / _strategyPrice();
    _redeemedTokens = IIdleTokenV3_1(idleToken).redeemIdleToken(idleTokens);
    if (_revertIfNeeded) {
      require(_redeemedTokens >= _amount - 1, 'IDLE:TOO_LOW');
    }
  }

  // Protected
  // ###################
  function liquidate(uint256 _amount) external returns (uint256) {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");

    return _liquidate(_amount, false);
  }

  function harvest(bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");

    address[] memory rewards = IIdleTokenV3_1(idleToken).getGovTokens();
    for (uint256 i = 0; i < rewards.length; i++) {
      address rewardToken = rewards[i];
      uint256 _currentBalance = _contractTokenBalance(rewardToken);
      if (rewardToken == idle || _skipReward[i] || _currentBalance == 0) { continue; }

      address[] memory _path = new address[](3);
      _path[0] = rewardToken;
      _path[1] = weth;
      _path[2] = token;
      ERC20(rewardToken).safeIncreaseAllowance(address(uniswapRouterV2), _currentBalance);

      uniswapRouterV2.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        _currentBalance,
        _minAmount[i],
        _path,
        address(this),
        block.timestamp + 10
      );
    }

    IIdleTokenV3_1(idleToken).mintIdleToken(_contractTokenBalance(token), true, address(0));

    // TODO get fees?
  }

  // Permit and Deposit support
  // ###################
  function permitAndDeposit(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
    _deposit(amount);
  }

  function permitEIP2612AndDeposit(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), amount, expiry, v, r, s);
    _deposit(amount);
  }

  function permitEIP2612AndDepositUnlimited(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), type(uint256).max, expiry, v, r, s);
    _deposit(amount);
  }

  // onlyOwner
  // ###################
  function setSkipDefaultCheck(bool _allowed) external onlyOwner {
    skipDefaultCheck = _allowed;
  }

  function setRevertIfNeeded(bool _allowed) external onlyOwner {
    revertIfNeeded = _allowed;
  }

  function setRebalancer(address _rebalancer) external onlyOwner {
    require(_rebalancer != address(0), 'IDLE:IS_0');
    rebalancer = _rebalancer;
  }

  function pause() external onlyOwner {
    _pause();
  }

  // helpers
  // ###################
  // Set last caller and block.number hash. This should be called at the beginning of the first function
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  // Check that the second function is not called in the same block from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "SAME_BLOCK");
  }
}
