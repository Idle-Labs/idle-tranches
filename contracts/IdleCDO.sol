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

/// @author Idle Labs Inc.
/// @title Tranches
contract IdleCDO is Initializable, PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  function initialize(
    uint256 _limit, address _guardedToken, address _governanceFund, address _guardian, // GuardedLaunch args
    address _rebalancer,
    address _strategy,
    uint256 _trancheAPRSplitRatio, // for AA tranches, so eg 10000 means 10% interest to AA and 90% BB
    uint256 _trancheIdealWeightRatio // for AA tranches, so eg 10000 means 10% of tranches are AA and 90% BB
  ) public initializer {
    // Initialize contracts
    PausableUpgradeable.__Pausable_init();
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _guardedToken, _governanceFund, _guardian);
    // Deploy Tranches tokens
    AATranche = address(new IdleCDOTranche("Idle CDO AA Tranche", "IDLE_CDO_AA"));
    BBTranche = address(new IdleCDOTranche("Idle CDO BB Tranche", "IDLE_CDO_BB"));
    // Set CDO params
    token = _guardedToken;
    strategy = _strategy;
    strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    rebalancer = _rebalancer;
    trancheAPRSplitRatio = _trancheAPRSplitRatio;
    trancheIdealWeightRatio = _trancheIdealWeightRatio;
    idealRange = 10000; // trancheIdealWeightRatio ± 10%
    oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    incentiveToken = address(0x875773784Af8135eA0ef43b5a374AaD105c5D39e);
    priceAA = oneToken;
    priceBB = oneToken;
    lastAAPrice = oneToken;
    lastBBPrice = oneToken;
    // Set flags
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;
    skipDefaultCheck = false;
    // Set allowance for strategy
    IERC20Detailed(_guardedToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    IERC20Detailed(strategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    // Save current strategy price
    lastStrategyPrice = strategyPrice();
    // Fee params
    fee = 10000; // 100000 => 100%
    feeReceiver = address(0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4); // feeCollector
    guardian = _guardian;
  }

  // ###############
  // Public methods
  // ###############

  // User should approve this contract first to spend IdleTokens
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

  // TODO this should probably go in another separate contract and users would need to stake
  // tranches tokens to earn eg IDLE rewards. This will allow more easy integrations
  // function updateIncentives() external {
  //   // uint256 currAARatio = getCurrentAARatio();
  //   // bool isAAHigh = currAARatio > (trancheIdealWeightRatio + idealRange);
  //   // bool isAALow = currAARatio < (trancheIdealWeightRatio - idealRange);
  //   // uint256 idleBal = _contractTokenBalance(incentiveToken);
  //   //
  //   // if (isAAHigh) {
  //   //   // TODO give more rewards to BB holders
  //   // }
  //   //
  //   // if (isAALow) {
  //   //   // TODO give more rewards to AA holders
  //   // }
  // }

  // Permit and Deposit support
  // function permitAndDepositAA(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
  //   _deposit(amount, AATranche);
  // }
  //
  // function permitAndDepositBB(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
  //   _deposit(amount, BBTranche);
  // }
  //
  // function permitEIP2612AndDepositAA(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(token).permit(msg.sender, address(this), amount, expiry, v, r, s);
  //   _deposit(amount, AATranche);
  // }
  //
  // function permitEIP2612AndDepositUnlimitedAA(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(token).permit(msg.sender, address(this), type(uint256).max, expiry, v, r, s);
  //   _deposit(amount, AATranche);
  // }
  //
  // function permitEIP2612AndDepositBB(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(token).permit(msg.sender, address(this), amount, expiry, v, r, s);
  //   _deposit(amount, BBTranche);
  // }
  //
  // function permitEIP2612AndDepositUnlimitedBB(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
  //   IERC20Permit(token).permit(msg.sender, address(this), type(uint256).max, expiry, v, r, s);
  //   _deposit(amount, BBTranche);
  // }

  // ###############
  // Views
  // ###############

  function tranchePrice(address _tranche) external view returns (uint256) {
    return _tranchePrice(_tranche);
  }

  function lastTranchePrice(address _tranche) external view returns (uint256) {
    return _lastTranchePrice(_tranche);
  }

  // In underlyings, rewards (gov tokens) are not counted
  function getContractValue() public override view returns (uint256) {
    return ((_contractTokenBalance(strategyToken) * strategyPrice() / oneToken) + _contractTokenBalance(token));
  }

  // Apr at ideal trancheIdealWeightRatio balance between AA and BB
  function getIdealApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, trancheIdealWeightRatio);
  }

  // Get actual apr given current ratio between AA and BB tranches
  function getApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, getCurrentAARatio());
  }

  function strategyAPR() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).getApr();
  }

  function strategyPrice() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).price(address(this));
  }

  function getRewards() public view returns (address[] memory) {
    return IIdleCDOStrategy(strategy).getRewardTokens();
  }

  function getCurrentAARatio() public view returns (uint256) {
    uint256 AABal = _balanceAATranche();
    uint256 contractVal = AABal + _balanceBBTranche();
    if (contractVal == 0) {
      return 0;
    }
    // Current AA tranche split ratio = AABal * FULL_ALLOC / getContractValue()
    return AABal * FULL_ALLOC / contractVal;
  }

  // Prices with current nav
  function virtualPriceAA() external view returns (uint256) {
    uint256 nav = getContractValue();
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0 || (nav <= lastNAV)) {
      return oneToken;
    }
    // AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
    // priceAA = (lastNAVAA + AAGain) * oneToken / AATotSupply
    return (lastNAVAA + ((nav - lastNAV) * trancheAPRSplitRatio / FULL_ALLOC)) * oneToken / IdleCDOTranche(AATranche).totalSupply();
  }

  function virtualPriceBB() external view returns (uint256) {
    uint256 nav = getContractValue();
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0 || (nav <= lastNAV)) {
      return oneToken;
    }

    uint256 BBGain = (nav - lastNAV) * (FULL_ALLOC - trancheAPRSplitRatio) / FULL_ALLOC;
    return (lastNAVBB + BBGain) * oneToken / IdleCDOTranche(BBTranche).totalSupply();
  }

  // ###############
  // Internal
  // ###############
  function _deposit(uint256 _amount, address _tranche) internal returns (uint256 _minted) {
    _guarded(_amount);
    _updateCallerBlock();
    _checkDefault();

    _updatePrices();

    // mint of shares should be done before transferring funds
    _minted = _mintShares(_amount, msg.sender, _tranche);
    IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  function _updatePrices() internal {
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0) {
      return;
    }

    uint256 nav = getContractValue();
    if (nav <= lastNAV) {
      return;
    }

    uint256 gain = nav - lastNAV;
    uint256 AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
    uint256 BBGain = gain - AAGain;
    lastNAVAA += AAGain;
    lastNAVBB += BBGain;
    priceAA = lastNAVAA * oneToken / IdleCDOTranche(AATranche).totalSupply();
    priceBB = lastNAVBB * oneToken / IdleCDOTranche(BBTranche).totalSupply();
  }

  function _mintShares(uint256 _amount, address _to, address _tranche) internal returns (uint256 _minted) {
    _minted = _amount * oneToken / _tranchePrice(_tranche);
    IdleCDOTranche(_tranche).mint(_to, _minted);
    // update NAV with the _amount of underlyings added
    if (_tranche == AATranche) {
      lastNAVAA += _amount;
    } else {
      lastNAVBB += _amount;
    }
  }

  function _depositFees(uint256 _amount) internal returns (uint256 _minted) {
    // Choose the right tranche to mint based on getCurrentAARatio
    address _tranche = getCurrentAARatio() >= trancheIdealWeightRatio ? BBTranche : AATranche;
    _minted = _mintShares(_amount, feeReceiver, _tranche);
    // TODO we should also stake those in the reward contract
  }

  function _updateLastTranchePrices() internal {
    lastAAPrice = priceAA;
    lastBBPrice = priceBB;
  }

  function _lastNAV() internal view returns (uint256) {
    return lastNAVAA + lastNAVBB;
  }

  // amount in trancheXXAmount
  function _withdraw(uint256 _amount, address _tranche) internal returns (uint256 toRedeem) {
    _checkSameTx();
    _checkDefault();
    _updatePrices();

    if (_amount == 0) {
      _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
    }
    require(_amount > 0, 'IDLE:IS_0');

    uint256 balanceUnderlying = _contractTokenBalance(token);
    // Use checkpoint price from last harvest

    // TODO can we directly use the _tranchePrice or should we use _lastTranchePrice to avoid
    // theft of interest ? (eg when reinvesting gov tokens?)
    toRedeem = _amount * _tranchePrice(_tranche) / oneToken;
    // toRedeem = _amount * _lastTranchePrice(_tranche) / oneToken;

    if (toRedeem > balanceUnderlying) {
      // there could be a difference of up to 100 wei due to rounding
      toRedeem = _liquidate(toRedeem - balanceUnderlying, revertIfTooLow);
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);
    // send underlying
    IERC20Detailed(token).safeTransfer(msg.sender, toRedeem);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= toRedeem;
    } else {
      lastNAVBB -= toRedeem;
    }
  }

  function _checkDefault() internal {
    uint256 currPrice = strategyPrice();
    if (!skipDefaultCheck) {
      require(lastStrategyPrice <= currPrice, "IDLE:DEFAULT_WAIT_SHUTDOWN");
    }
    lastStrategyPrice = currPrice;
  }

  // this should liquidate at least _amount or revertIfNeeded
  // _amount is in underlying
  function _liquidate(uint256 _amount, bool revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (revertIfNeeded) {
      // keep 100 wei as margin for rounding errors
      require(_redeemedTokens + 100 >= _amount, 'IDLE:TOO_LOW');
    }
  }

  function _tranchePrice(address _tranche) internal view returns (uint256) {
    if (IdleCDOTranche(_tranche).totalSupply() == 0) {
      return oneToken;
    }
    return _tranche == AATranche ? priceAA : priceBB;
  }

  function _lastTranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? lastAAPrice : lastBBPrice;
  }

  // in underlying
  function _balanceAATranche() internal view returns (uint256) {
    return IdleCDOTranche(AATranche).totalSupply() * priceAA / oneToken;
  }

  // in underlying
  function _balanceBBTranche() internal view returns (uint256) {
    return IdleCDOTranche(BBTranche).totalSupply() * priceBB / oneToken;
  }

  function _getApr(address _tranche, uint256 _AATrancheSplitRatio) internal view returns (uint256) {
    uint256 stratApr = strategyAPR();
    bool isAATranche = _tranche == AATranche;
    if (_AATrancheSplitRatio == 0) {
      return isAATranche ? 0 : stratApr;
    }
    return isAATranche ?
      stratApr * trancheAPRSplitRatio / _AATrancheSplitRatio :
      stratApr * (FULL_ALLOC - trancheAPRSplitRatio) / (FULL_ALLOC - _AATrancheSplitRatio);
  }

  // ###################
  // Protected
  // ###################

  function harvest(bool _skipRedeem, bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    if (!_skipRedeem) {
      uint256 initialBalance = _contractTokenBalance(token);
      IIdleCDOStrategy(strategy).redeemRewards();

      address[] memory rewards = getRewards();
      for (uint256 i = 0; i < rewards.length; i++) {
        address rewardToken = rewards[i];
        uint256 _currentBalance = _contractTokenBalance(rewardToken);
        if (rewardToken == incentiveToken || _skipReward[i] || _currentBalance == 0) { continue; }

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

      uint256 finalBalance = _contractTokenBalance(token);
      if (finalBalance > initialBalance) {
        // TODO do we need to get these fees here?
        // Get fee on governance token sell
        // TODO do we need to update prices before our deposit?
        _depositFees((finalBalance - initialBalance) * fee / FULL_ALLOC);
      }
    }

    IIdleCDOStrategy(strategy).deposit(_contractTokenBalance(token));
    // TODO get fees on principal too?
    // or get fixed fee on redeem?
    // or fixed fee on deposit ?

    _updatePrices();
    // update last saved prices for redeems
    _updateLastTranchePrices();
  }

  function liquidate(uint256 _amount, bool revertIfNeeded) external returns (uint256) {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    return _liquidate(_amount, revertIfNeeded);
  }

  // ###################
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
    strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    // Approve underlyingToken
    _token.safeIncreaseAllowance(_strategy, type(uint256).max);
    // Approve strategyToken
    IERC20Detailed(strategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);

    lastStrategyPrice = strategyPrice();
  }

  function setRebalancer(address _rebalancer) external onlyOwner {
    require((rebalancer = _rebalancer) != address(0), 'IDLE:IS_0');
  }

  function setFeeReceiver(address _feeReceiver) external onlyOwner {
    require((feeReceiver = _feeReceiver) != address(0), 'IDLE:IS_0');
  }

  function setGuardian(address _guardian) external onlyOwner {
    require((guardian = _guardian) != address(0), 'IDLE:IS_0');
  }

  function setFee(uint256 _fee) external onlyOwner {
    require((fee = _fee) <= MAX_FEE, 'IDLE:TOO_HIGH');
  }

  function setIdealRange(uint256 _idealRange) external onlyOwner {
    require((idealRange = _idealRange) <= FULL_ALLOC, 'IDLE:TOO_HIGH');
  }

  function emergencyShutdown() external onlyOwner {
    _pause();
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    skipDefaultCheck = false;
    revertIfTooLow = true;
  }

  function pause() external  {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _pause();
  }

  function unpause() external {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _unpause();
  }

  // ###################
  // Helpers
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
