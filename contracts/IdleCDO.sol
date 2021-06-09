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

/// @title A continous tranche implementation
/// @author Idle Labs Inc.
/// @dev The contract is upgradable, to add storage slots, create IdleCDOStorageVX and inherit from IdleCDOStorage, then update the definitaion below
contract IdleCDO is Initializable, PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @dev Initialize the contract
  /// @param _limit contract value limit
  /// @param _guardedToken underlying token
  /// @param _governanceFund address where funds will be sent in case of emergency
  /// @param _guardian guardian address
  /// @param _rebalancer rebalancer address
  /// @param _strategy
  /// @param _trancheAPRSplitRatio trancheAPRSplitRatio value
  /// @param _trancheIdealWeightRatio trancheIdealWeightRatio value
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
    // TODO do we need this or we can always use ONE_TOKEN ?
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
    fee = 15000; // 15% performance fee
    feeReceiver = address(0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4); // feeCollector
    guardian = _guardian;
  }

  // ###############
  // Public methods
  // ###############

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return AA tranche tokens minted
  function depositAA(uint256 _amount) external whenNotPaused returns (uint256) {
    return _deposit(_amount, AATranche);
  }

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return BB tranche tokens minted
  function depositBB(uint256 _amount) external whenNotPaused returns (uint256) {
    return _deposit(_amount, BBTranche);
  }

  /// @notice pausable
  /// @param _amount amount of AA tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawAA(uint256 _amount) external returns (uint256) {
    require(!paused() || allowAAWithdraw, 'IDLE:AA_!ALLOWED');
    return _withdraw(_amount, AATranche);
  }

  /// @notice pausable
  /// @param _amount amount of BB tranche tokens to burn
  /// @return underlying tokens redeemed
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

  /// @param _tranche tranche address
  /// @return tranche price
  function tranchePrice(address _tranche) external view returns (uint256) {
    return _tranchePrice(_tranche);
  }

  /// @param _tranche tranche address
  /// @return last tranche price
  function lastTranchePrice(address _tranche) external view returns (uint256) {
    return _lastTranchePrice(_tranche);
  }

  /// @notice rewards (gov tokens) are not counted
  /// @return contract value in underlyings
  function getContractValue() public override view returns (uint256) {
    // strategyTokens value in underlying + unlent balance
    return ((_contractTokenBalance(strategyToken) * strategyPrice() / oneToken) + _contractTokenBalance(token));
  }

  /// @param _tranche tranche address
  /// @return apr at ideal trancheIdealWeightRatio balance between AA and BB
  function getIdealApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, trancheIdealWeightRatio);
  }

  /// @param _tranche tranche address
  /// @return actual apr given current ratio between AA and BB tranches
  function getApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, getCurrentAARatio());
  }

  /// @return strategy apr
  function strategyAPR() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).getApr();
  }

  /// @return strategy price
  function strategyPrice() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).price();
  }

  /// @return array of reward token addresses
  function getRewards() public view returns (address[] memory) {
    return IIdleCDOStrategy(strategy).getRewardTokens();
  }

  /// @return AA tranches ratio (in underlying value)
  function getCurrentAARatio() public view returns (uint256) {
    uint256 AABal = _balanceAATranche();
    uint256 contractVal = AABal + _balanceBBTranche();
    if (contractVal == 0) {
      return 0;
    }
    // Current AA tranche split ratio = AABal * FULL_ALLOC / getContractValue()
    return AABal * FULL_ALLOC / contractVal;
  }

  /// @return AA price with current nav
  function virtualPriceAA() external view returns (uint256) {
    uint256 nav = getContractValue();
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0 || (nav <= lastNAV)) {
      return oneToken;
    }
    // gain = nav - lastNAV
    // AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
    // priceAA = (lastNAVAA + AAGain) * oneToken / AATotSupply
    return (lastNAVAA + ((nav - lastNAV) * trancheAPRSplitRatio / FULL_ALLOC)) * oneToken / IdleCDOTranche(AATranche).totalSupply();
  }

  /// @return BB price with current nav
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

  /// @notice automatically reverts on lending provider default (strategyPrice decreased)
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// @param _amount amount of underlyings (`token`) to deposit
  /// @param _tranche tranche address
  /// @return number of tranche tokens minted
  function _deposit(uint256 _amount, address _tranche) internal returns (uint256 _minted) {
    // check that we are not depositing more than the contract available limit
    _guarded(_amount);
    // set _lastCallerBlock hash
    _updateCallerBlock();
    // check if strategyPrice decreased
    _checkDefault();
    // interest accrued since last mint/redeem/harvest is splitted between AA and BB
    // according to trancheAPRSplitRatio. NAVs of AA and BB are so updated and tranche
    // prices adjusted accordingly
    _updatePrices();
    // NOTE: mint of shares should be done before transferring funds
    // mint tranches tokens according to the current prices
    _minted = _mintShares(_amount, msg.sender, _tranche);
    // get underlyings from sender
    IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  /// @dev accrues interest to the tranches (update NAVs variables) and updates tranche prices
  function _updatePrices() internal {
    // get last saved total net asset value
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0) {
      return;
    }
    // get the current total net asset value
    uint256 nav = getContractValue();
    if (nav <= lastNAV) {
      return;
    }
    // Calculate gain since last update
    uint256 gain = nav - lastNAV;
    // split the gain between AA and BB holders according to trancheAPRSplitRatio
    uint256 AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
    uint256 BBGain = gain - AAGain;
    // Update NAVs
    lastNAVAA += AAGain;
    lastNAVBB += BBGain;
    // Update tranche prices
    priceAA = lastNAVAA * oneToken / IdleCDOTranche(AATranche).totalSupply();
    priceBB = lastNAVBB * oneToken / IdleCDOTranche(BBTranche).totalSupply();
  }

  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return number of tranche tokens minted
  function _mintShares(uint256 _amount, address _to, address _tranche) internal returns (uint256 _minted) {
    // calculate # of tranche token to mint based on current tranche price
    _minted = _amount * oneToken / _tranchePrice(_tranche);
    IdleCDOTranche(_tranche).mint(_to, _minted);
    // update NAV with the _amount of underlyings added
    if (_tranche == AATranche) {
      lastNAVAA += _amount;
    } else {
      lastNAVBB += _amount;
    }
  }

  /// @notice this will be called only during harvests
  /// @param _amount amount of underlyings to deposit
  /// @return number of tranche tokens minted
  function _depositFees(uint256 _amount) internal returns (uint256 _minted) {
    // Choose the right tranche to mint based on getCurrentAARatio
    address _tranche = getCurrentAARatio() >= trancheIdealWeightRatio ? BBTranche : AATranche;
    _minted = _mintShares(_amount, feeReceiver, _tranche);
    // TODO we should also stake those in the reward contract
  }

  /// @dev updates last tranche prices with the current ones
  function _updateLastTranchePrices() internal {
    lastAAPrice = priceAA;
    lastBBPrice = priceBB;
  }

  /// @return the total saved net asset value for all tranches
  function _lastNAV() internal view returns (uint256) {
    return lastNAVAA + lastNAVBB;
  }

  /// @notice automatically reverts on lending provider default (strategyPrice decreased)
  /// @param _amount in tranche tokens
  /// @param _tranche tranche address
  /// @return number of underlyings redeemed
  function _withdraw(uint256 _amount, address _tranche) internal returns (uint256 toRedeem) {
    // check if a deposit is made in the same block from the same user
    _checkSameTx();
    // check if strategyPrice decreased
    _checkDefault();
    // accrue interest to tranches and updates tranche prices
    _updatePrices();
    // redeem all user balance if 0 is passed as _amount
    if (_amount == 0) {
      _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
    }
    require(_amount > 0, 'IDLE:IS_0');
    // get current unlent balance
    uint256 balanceUnderlying = _contractTokenBalance(token);
    // Calculate the amount to redeem using the checkpointed price from last harvest

    // TODO can we directly use the _tranchePrice or should we use _lastTranchePrice to avoid
    // theft of interest ? (eg when reinvesting gov tokens?)
    // toRedeem = _amount * _lastTranchePrice(_tranche) / oneToken;
    toRedeem = _amount * _tranchePrice(_tranche) / oneToken;

    if (toRedeem > balanceUnderlying) {
      // if the unlent balance is not enough we try to redeem directly from the strategy
      // NOTE: there could be a difference of up to 100 wei due to rounding
      toRedeem = _liquidate(toRedeem - balanceUnderlying, revertIfTooLow);
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);
    // send underlying to msg.sender
    IERC20Detailed(token).safeTransfer(msg.sender, toRedeem);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= toRedeem;
    } else {
      lastNAVBB -= toRedeem;
    }
  }

  /// @dev check if strategyPrice is decreased since last update and updates last saved strategy price
  function _checkDefault() internal {
    uint256 currPrice = strategyPrice();
    if (!skipDefaultCheck) {
      require(lastStrategyPrice <= currPrice, "IDLE:DEFAULT_WAIT_SHUTDOWN");
    }
    lastStrategyPrice = currPrice;
  }

  /// @dev this should liquidate at least _amount or revertIfNeeded
  /// @param _amount in underlying tokens
  /// @param _revertIfNeeded flag whether to revert or not if the redeemed amount is not enough
  /// @return number of underlyings redeemed
  function _liquidate(uint256 _amount, bool _revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (_revertIfNeeded) {
      // keep 100 wei as margin for rounding errors
      require(_redeemedTokens + 100 >= _amount, 'IDLE:TOO_LOW');
    }
  }

  /// @param _tranche tranche address
  /// @return last saved price for minting tranche tokens
  function _tranchePrice(address _tranche) internal view returns (uint256) {
    if (IdleCDOTranche(_tranche).totalSupply() == 0) {
      return oneToken;
    }
    return _tranche == AATranche ? priceAA : priceBB;
  }

  /// @param _tranche tranche address
  /// @return last saved price for redeeming tranche tokens (updated on harvests)
  function _lastTranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? lastAAPrice : lastBBPrice;
  }

  /// @return net asset value, in underlying tokens, for AA tranche based on AA token price at mint
  function _balanceAATranche() internal view returns (uint256) {
    return IdleCDOTranche(AATranche).totalSupply() * priceAA / oneToken;
  }

  /// @return net asset value, in underlying tokens, for BB tranche based on AA token price at mint
  function _balanceBBTranche() internal view returns (uint256) {
    return IdleCDOTranche(BBTranche).totalSupply() * priceBB / oneToken;
  }

  /// @notice the apr can be higher than the strategy apr
  /// @dev returns the current apr for a tranche based on trancheAPRSplitRatio and the provided AA split ratio
  /// @param _tranche tranche token
  /// @param _AATrancheSplitRatio AA split ratio used for calculations
  /// @return apr for the specific tranche
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

  /// @notice can be called only by the rebalancer or the owner
  /// @dev it redeems rewards if any from the lending provider of the strategy and converts them in underlyings.
  /// it also deposits eventual unlent balance already present in the contract with the strategy.
  /// This method will be called by an exteranl keeper bot which will call the method sistematically (eg once a day)
  /// @param _skipRedeem whether to redeem rewards from strategy or not (for gas savings)
  /// @param _skipReward array of flags for skipping the market sell of specific rewards. Lenght should be equal to the `getRewards()` array
  /// @param _minAmount array of min amounts for uniswap trades. Lenght should be equal to the _skipReward array
  function harvest(bool _skipRedeem, bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    if (!_skipRedeem) {
      // get current unlent balance
      uint256 initialBalance = _contractTokenBalance(token);
      // Redeem all rewards associated with the strategy
      IIdleCDOStrategy(strategy).redeemRewards();
      // get all rewards addresses
      address[] memory rewards = getRewards();
      for (uint256 i = 0; i < rewards.length; i++) {
        address rewardToken = rewards[i];
        // get the balance of a specific reward
        uint256 _currentBalance = _contractTokenBalance(rewardToken);
        // check if it should be sold or not
        if (rewardToken == incentiveToken || _skipReward[i] || _currentBalance == 0) { continue; }
        // Prepare path for uniswap trade
        address[] memory _path = new address[](3);
        _path[0] = rewardToken;
        _path[1] = weth;
        _path[2] = token;
        // approve the uniswap router to spend our reward
        IERC20Detailed(rewardToken).safeIncreaseAllowance(address(uniswapRouterV2), _currentBalance);
        // do the uniswap trade
        uniswapRouterV2.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          _currentBalance,
          _minAmount[i],
          _path,
          address(this),
          block.timestamp + 1
        );
      }
      // get unlent balance after selling rewards
      uint256 finalBalance = _contractTokenBalance(token);
      if (finalBalance > initialBalance) {
        // TODO do we need to get these fees here?
        // TODO do we need to update prices before our deposit?
        // Get fees on governance token sell
        _depositFees((finalBalance - initialBalance) * fee / FULL_ALLOC);
      }
    }
    // Put unlent balance at work in the lending provider
    IIdleCDOStrategy(strategy).deposit(_contractTokenBalance(token));
    // TODO get fees on principal too?
    // or get fixed fee on redeem?
    // or fixed fee on deposit ?


    // TODO: is it correct here to split interest and updatesd tranche prices for mint?
    _updatePrices();
    // update last saved prices for redeems
    _updateLastTranchePrices();
  }

  /// @notice can be called only by the rebalancer or the owner
  /// @param _amount in underlyings to liquidate from lending provider
  /// @param _revertIfNeeded flag to revert if amount liquidated is too low
  /// @return liquidated amount in underlyings
  function liquidate(uint256 _amount, bool _revertIfNeeded) external returns (uint256) {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    return _liquidate(_amount, _revertIfNeeded);
  }

  // ###################
  // onlyOwner
  // ###################

  /// @param _allowed flag to allow AA withdraws
  function setAllowAAWithdraw(bool _allowed) external onlyOwner {
    allowAAWithdraw = _allowed;
  }

  /// @param _allowed flag to allow BB withdraws
  function setAllowBBWithdraw(bool _allowed) external onlyOwner {
    allowBBWithdraw = _allowed;
  }

  /// @param _allowed flag to enable the 'default' check (whether strategyPrice decreased or not)
  function setSkipDefaultCheck(bool _allowed) external onlyOwner {
    skipDefaultCheck = _allowed;
  }

  /// @param _allowed flag to enable the check if redeemed amount during liquidations is enough
  function setRevertIfTooLow(bool _allowed) external onlyOwner {
    revertIfTooLow = _allowed;
  }

  /// @dev
  /// @param _strategy
  /// @return
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

  /// @param _rebalancer new rebalancer address
  function setRebalancer(address _rebalancer) external onlyOwner {
    require((rebalancer = _rebalancer) != address(0), 'IDLE:IS_0');
  }

  /// @param _feeReceiver new fee receiver address
  function setFeeReceiver(address _feeReceiver) external onlyOwner {
    require((feeReceiver = _feeReceiver) != address(0), 'IDLE:IS_0');
  }

  /// @param _guardian new guardian (pauser) address
  function setGuardian(address _guardian) external onlyOwner {
    require((guardian = _guardian) != address(0), 'IDLE:IS_0');
  }

  /// @param _fee new fee
  function setFee(uint256 _fee) external onlyOwner {
    require((fee = _fee) <= MAX_FEE, 'IDLE:TOO_HIGH');
  }

  /// @param _idealRange new ideal range
  function setIdealRange(uint256 _idealRange) external onlyOwner {
    require((idealRange = _idealRange) <= FULL_ALLOC, 'IDLE:TOO_HIGH');
  }

  /// @dev pause deposits and redeems for all classes of tranches
  function emergencyShutdown() external onlyOwner {
    _pause();
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    skipDefaultCheck = false;
    revertIfTooLow = true;
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev Pauses deposits and redeems
  function pause() external  {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _pause();
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev Unpauses deposits and redeems
  function unpause() external {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _unpause();
  }

  // ###################
  // Helpers
  // ###################

  /// @param _token token address
  /// @return balance of `_token` for this contract
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
  }

  /// @dev Set last caller and block.number hash. This should be called at the beginning of the first function to protect
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  /// @dev Check that the second function is not called in the same block from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "SAME_BLOCK");
  }
}
