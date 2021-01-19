// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Permit.sol";
import "./GuardedLaunchUpgradable.sol";
import "./FlashProtection.sol";
import "./IdleCDOTranche.sol";

contract IdleCDO is Initializable, OwnableUpgradeable, PausableUpgradeable, GuardedLaunchUpgradable, FlashProtection {
  using SafeMath for uint256;
  using SafeERC20 for ERC20;

  uint256 public constant FULL_ALLOC = 100000;

  address public rebalancer;
  address public token;
  address public weth;
  address public idle;
  address public strategy;
  address public AATranche;
  address public BBTranche;
  uint256 public trancheSplitRatio; // 100% => 100000 => 100% to tranche AA
  uint256 public oneToken;
  uint256 public lastPrice;
  bool public allowAAWithdraw;
  bool public allowBBWithdraw;
  bool public skipDefaultCheck;
  bool public revertIfTooLow;
  IUniswapV2Router02 private uniswapRouterV2;

  function initialize(
    uint256 _limit, uint256 _userLimit, address _guardedToken, address _governanceFund, // GuardedLaunch args
    address _rebalancer,
    address _strategy,
    uint256 _trancheSplitRatio // for AA tranches so eg 10000 means 10% interest to AA and 90% BB
  ) public initializer {
    OwnableUpgradeable.__Ownable_init();
    PausableUpgradeable.__Pausable_init();
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _userLimit, _guardedToken, _governanceFund);

    trancheSplitRatio = _trancheSplitRatio;
    rebalancer = _rebalancer;
    strategy = _strategy;
    oneToken = ERC20(_guardedToken).decimals();
    token = _guardedToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    idle = address(0x875773784Af8135eA0ef43b5a374AaD105c5D39e);

    // Deploy Tranches tokens
    AATranche = address(new IdleCDOTranche("Idle CDO AA Tranche", "IDLE_CDO_AA"));
    BBTranche = address(new IdleCDOTranche("Idle CDO BB Tranche", "IDLE_CDO_BB"));

    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;

    ERC20(token).safeIncreaseAllowance(strategy, uint256(-1));
    lastPrice = IIdleCDOStrategy(strategy).price();
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

  function getContractValue() public override view returns (uint256) {
    return _balanceAATranche().add(_balanceBBTranche());
  }

  // internal
  // ###############
  function _deposit(uint256 _amount, address _tranche) internal whenNotPaused returns (uint256 _minted) {
    _guarded(_amount);
    _updateCallerBlock();
    _checkDefault();

    _minted = _amount.mul(oneToken).div(_tranchePrice(_tranche));
    IdleCDOTranche(_tranche).mint(msg.sender, _minted);
    ERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  function _withdraw(uint256 _amount, address _tranche) internal returns (uint256 toRedeem) {
    _checkSameTx();
    _checkDefault();

    uint256 balanceUnderlying = ERC20(token).balanceOf(address(this));
    toRedeem = _amount.mul(_tranchePrice(_tranche)).div(oneToken);
    if (toRedeem > balanceUnderlying) {
      _liquidate(toRedeem.sub(balanceUnderlying), revertIfTooLow);
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);
    // send underlying
    ERC20(token).safeTransfer(msg.sender, toRedeem);
  }

  // this should liquidate at least _amount or revert?
  // _amount is in underlying
  function _liquidate(uint256 _amount, bool revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (revertIfNeeded) {
      require(_redeemedTokens >= _amount.sub(1), 'IDLE:TOO_LOW');
    }
  }

  function _tranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? _priceAATranche() : _priceBBTranche();
  }

  function _priceAATranche() internal view returns (uint256) {
    // 1 + ((price - 1) * trancheSplitRatio/FULL_ALLOC)
    return oneToken.add(IIdleCDOStrategy(strategy).price().sub(oneToken).mul(trancheSplitRatio).div(FULL_ALLOC));
  }

  function _priceBBTranche() internal view returns (uint256) {
    // 1 + ((price - 1) * (FULL_ALLOC-trancheSplitRatio)/FULL_ALLOC)
    return oneToken.add(IIdleCDOStrategy(strategy).price().sub(oneToken).mul(FULL_ALLOC.sub(trancheSplitRatio)).div(FULL_ALLOC));
  }

  function _balanceAATranche() internal view returns (uint256) {
    return IdleCDOTranche(AATranche).totalSupply().mul(_priceAATranche()).div(oneToken);
  }

  function _balanceBBTranche() internal view returns (uint256) {
    return IdleCDOTranche(BBTranche).totalSupply().mul(_priceBBTranche()).div(oneToken);
  }

  function _checkDefault() internal {
    uint256 currPrice = IIdleCDOStrategy(strategy).price();
    if (!skipDefaultCheck) {
      require(lastPrice > currPrice, "IDLE:DEFAULT_WAIT_SHUTDOWN");
    }
    lastPrice = currPrice;
  }

  // Protected
  // ###################
  function rebalance() external {
    require(msg.sender == rebalancer, "IDLE:!AUTH");

    uint256 balanceUnderlying = ERC20(token).balanceOf(address(this));
    IIdleCDOStrategy(strategy).deposit(balanceUnderlying);
  }

  function liquidate(uint256 _amount, bool revertIfNeeded) external returns (uint256) {
    require(msg.sender == rebalancer, "IDLE:!AUTH");

    return _liquidate(_amount, revertIfNeeded);
  }

  // Utilities
  // ###################
  // note path[0] will be added automatically, the entire path for each token should exist
  // function swap(address[] memory _tokens, address[] memory _path) external onlyOwner {
  //   for (uint256 i = 0; i < _tokens.length; i++) {
  //     address _tokenAddress = _tokens[i];
  //     uint256 _currentBalance = ERC20(_tokenAddress).balanceOf(address(this));
  //
  //     address[] memory path = new address[](2);
  //     path[0] = _tokenAddress;
  //     for (uint256 j = 0; j < _path.length; j++) {
  //       path[j+1] = _path[j];
  //     }
  //
  //     uniswapRouterV2.swapExactTokensForTokensSupportingFeeOnTransferTokens(
  //       _currentBalance,
  //       1, // receive at least 1 wei of ETH
  //       path,
  //       address(this),
  //       block.timestamp
  //     );
  //   }
  // }

  // TODO add support for each tranche permit and deposit support
  // ###################
  // function permitAndDeposit(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(underlying).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
  //   deposit(amount);
  // }
  //
  // function permitEIP2612AndDeposit(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(underlying).permit(msg.sender, address(this), amount, expiry, v, r, s);
  //   deposit(amount);
  // }
  //
  // function permitEIP2612AndDepositUnlimited(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(underlying).permit(msg.sender, address(this), uint256(-1), expiry, v, r, s);
  //   deposit(amount);
  // }

  // onlyOwner
  // ###################
  function emergencyShutdown() external onlyOwner {
    _pause();
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    skipDefaultCheck = false;
    revertIfTooLow = true;
  }

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
    ERC20(token).safeApprove(strategy, 0);
    strategy = _strategy;
    ERC20(token).safeIncreaseAllowance(_strategy, uint256(-1));
  }

  function setRebalancer(address _rebalancer) external onlyOwner {
    require(_rebalancer != address(0), 'IDLE:IS_0');
    rebalancer = _rebalancer;
  }

  function pause() external onlyOwner {
    _pause();
  }
}
