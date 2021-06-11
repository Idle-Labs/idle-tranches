// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "hardhat/console.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";

import "./GuardedLaunchUpgradable.sol";
import "./IdleCDOTranche.sol";
import "./IdleCDOTrancheRewards.sol";
import "./IdleCDOStorage.sol";

/// @title A continous tranche implementation
/// @author Idle Labs Inc.
/// @dev The contract is upgradable, to add storage slots, create IdleCDOStorageVX and inherit from IdleCDOStorage, then update the definitaion below
contract IdleCDO is Initializable, PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  // ###################
  // Initializer
  // ###################

  /// @notice can only be called once
  /// @dev Initialize the upgradable contract
  /// @param _limit contract value limit
  /// @param _guardedToken underlying token
  /// @param _governanceFund address where funds will be sent in case of emergency
  /// @param _guardian guardian address
  /// @param _rebalancer rebalancer address
  /// @param _strategy strategy address
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
    // Deploy Tranches Rewards contract (for tranches incentivization)
    // TODO set rewards. conditionally deploy those using flags
    AAStaking = address(new IdleCDOTrancheRewards(AATranche));
    BBStaking = address(new IdleCDOTrancheRewards(BBTranche));
    // Set CDO params
    token = _guardedToken;
    strategy = _strategy;
    strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    rebalancer = _rebalancer;
    trancheAPRSplitRatio = _trancheAPRSplitRatio;
    trancheIdealWeightRatio = _trancheIdealWeightRatio;
    idealRange = 10000; // trancheIdealWeightRatio ± 10%
    uint256 _oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    oneToken = _oneToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    incentiveToken = address(0x875773784Af8135eA0ef43b5a374AaD105c5D39e);
    priceAA = _oneToken;
    priceBB = _oneToken;
    lastAAPrice = _oneToken;
    lastBBPrice = _oneToken;
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
    fee = 10000; // 10% performance fee
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
    address _strategyToken = strategyToken;
    // strategyTokens value in underlying + unlent balance
    uint256 strategyTokenDecimals = IERC20Detailed(_strategyToken).decimals();
    return ((_contractTokenBalance(_strategyToken) * strategyPrice() / (10**(strategyTokenDecimals))) + _contractNetUnderlyingBalance());
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

  /// @return strategy net apr
  function strategyAPR() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).getApr();
  }

  /// @return strategy price, in underlyings
  function strategyPrice() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).price();
  }

  /// @return array of reward token addresses
  function getRewards() public view returns (address[] memory) {
    return IIdleCDOStrategy(strategy).getRewardTokens();
  }

  /// @return AA tranches ratio (in underlying value) considering all NAV
  function getCurrentAARatio() public view returns (uint256) {
    uint256 AABal = virtualBalance(AATranche);
    uint256 contractVal = AABal + virtualBalance(BBTranche);
    if (contractVal == 0) {
      return 0;
    }
    // Current AA tranche split ratio = AABal * FULL_ALLOC / getContractValue()
    return AABal * FULL_ALLOC / contractVal;
  }

  /// @notice this should always be >= of _tranchePrice(_tranche)
  /// @dev useful for showing updated gains on frontends
  /// @param _tranche address of the requested tranche
  /// @return tranche price with current nav
  function virtualPrice(address _tranche) public view returns (uint256) {
    uint256 nav = getContractValue();
    uint256 lastNAV = _lastNAV();
    uint256 trancheSupply = IdleCDOTranche(_tranche).totalSupply();
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;

    if (lastNAV == 0 || trancheSupply == 0) {
      return oneToken;
    }
    // If there is no gain return the current saved price
    if (nav <= lastNAV) {
      return _tranchePrice(_tranche);
    }

    uint256 gain = nav - lastNAV;
    // remove performance fee
    gain -= gain * fee / FULL_ALLOC;
    // trancheNAV is: lastNAV + trancheGain
    uint256 trancheNAV;
    if (_tranche == AATranche) {
      // trancheGain (AAGain) = gain * trancheAPRSplitRatio / FULL_ALLOC;
      trancheNAV = lastNAVAA + (gain * _trancheAPRSplitRatio / FULL_ALLOC);
    } else {
      // trancheGain (BBGain) = gain * (FULL_ALLOC - trancheAPRSplitRatio) / FULL_ALLOC;
      trancheNAV = lastNAVBB + (gain * (FULL_ALLOC - _trancheAPRSplitRatio) / FULL_ALLOC);
    }
    // price => trancheNAV * ONE_TRANCHE_TOKEN / trancheSupply
    return trancheNAV * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche considering all nav
  function virtualBalance(address _tranche) public view returns (uint256) {
    return IdleCDOTranche(_tranche).totalSupply() * virtualPrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  // ###############
  // Internal
  // ###############

  /// @notice automatically reverts on lending provider default (strategyPrice decreased)
  /// Ideally users should deposit right after an `harvest` call to maximize profit
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// @param _amount amount of underlyings (`token`) to deposit
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
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
    uint256 _oneToken = oneToken;
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
    // get performance fee amount
    uint256 performanceFee = gain * fee / FULL_ALLOC;
    gain -= performanceFee;
    // and add the value to unclaimedFees
    unclaimedFees += performanceFee;
    // split the gain between AA and BB holders according to trancheAPRSplitRatio
    uint256 AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
    // Update NAVs
    lastNAVAA += AAGain;
    // BBGain
    lastNAVBB += gain - AAGain;
    // Update tranche prices
    uint256 AATotSupply = IdleCDOTranche(AATranche).totalSupply();
    uint256 BBTotSupply = IdleCDOTranche(BBTranche).totalSupply();
    priceAA = AATotSupply > 0 ? lastNAVAA * ONE_TRANCHE_TOKEN / AATotSupply : _oneToken;
    priceBB = BBTotSupply > 0 ? lastNAVBB * ONE_TRANCHE_TOKEN / BBTotSupply : _oneToken;
  }

  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _mintShares(uint256 _amount, address _to, address _tranche) internal returns (uint256 _minted) {
    // calculate # of tranche token to mint based on current tranche price
    _minted = _amount * ONE_TRANCHE_TOKEN / _tranchePrice(_tranche);
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
  /// @return _minted number of tranche tokens minted
  function _depositFees(uint256 _amount) internal returns (uint256 _minted) {
    // Choose the right tranche to mint based on getCurrentAARatio
    address _tranche = getCurrentAARatio() >= trancheIdealWeightRatio ? BBTranche : AATranche;
    _minted = _mintShares(_amount, feeReceiver, _tranche);
    // reset unclaimedFees counter
    // TODO we could set it to 1 to save some gas
    unclaimedFees = 0;
    // TODO we should also stake those in the reward contract
  }

  /// @dev updates last tranche prices with the current ones
  function _updateLastTranchePrices() internal {
    lastAAPrice = priceAA;
    lastBBPrice = priceBB;
  }

  /// @notice automatically reverts on lending provider default (strategyPrice decreased)
  /// a user should wait at least one harvest before rededeming otherwise the redeemed amount
  /// would be less than the deposited one due to the use of a checkpointed price at last harvest
  /// Ideally users should redeem right after an `harvest` call
  /// @param _amount in tranche tokens
  /// @param _tranche tranche address
  /// @return toRedeem number of underlyings redeemed
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
    uint256 balanceUnderlying = _contractNetUnderlyingBalance();
    // Calculate the amount to redeem using the checkpointed price from last harvest
    // NOTE: if use _tranchePrice directly one can deposit a huge amount before an harvest
    // to steal interest generated from rewards
    toRedeem = _amount * _lastTranchePrice(_tranche) / ONE_TRANCHE_TOKEN;

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
  /// @return _redeemedTokens number of underlyings redeemed
  function _liquidate(uint256 _amount, bool _revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (_revertIfNeeded) {
      // keep 100 wei as margin for rounding errors
      require(_redeemedTokens + 100 >= _amount, 'IDLE:TOO_LOW');
    }
  }

  /// @notice sends specific rewards to the tranche rewards staking contracts
  function _updateIncentives() internal {
    // Read state variables only once to save gas
    uint256 _trancheIdealWeightRatio = trancheIdealWeightRatio;
    uint256 _idealRange = idealRange;
    address _BBStaking = BBStaking;
    address _AAStaking = AAStaking;
    // Get current AA ratio (using virtual prices with full NAV)
    uint256 currAARatio = getCurrentAARatio();
    // Get balance of all rewardTokens

    // TODO set incentiveToken as array and do this in a for loop
    uint256 idleBal = _contractTokenBalance(incentiveToken);

    if (_BBStaking != address(0)) {
      bool isAAHigh = currAARatio > (_trancheIdealWeightRatio + _idealRange);
      if (isAAHigh) {
        // TODO give more rewards to BB holders, ie send some rewards to _BBStaking contract
      }
    }

    if (_AAStaking != address(0)) {
      bool isAALow = currAARatio < (_trancheIdealWeightRatio - _idealRange);
      if (isAALow) {
        // TODO give more rewards to BB holders, ie send some rewards to _AAStaking contract
      }
    }
  }

  /// @return the total saved net asset value for all tranches
  function _lastNAV() internal view returns (uint256) {
    return lastNAVAA + lastNAVBB;
  }

  /// @param _tranche tranche address
  /// @return last saved price for minting tranche tokens, in underlyings
  function _tranchePrice(address _tranche) internal view returns (uint256) {
    if (IdleCDOTranche(_tranche).totalSupply() == 0) {
      return oneToken;
    }
    return _tranche == AATranche ? priceAA : priceBB;
  }

  /// @param _tranche tranche address
  /// @return last saved price for redeeming tranche tokens (updated on harvests), in underlyings
  function _lastTranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? lastAAPrice : lastBBPrice;
  }

  /// @notice the apr can be higher than the strategy apr
  /// @dev returns the current apr for a tranche based on trancheAPRSplitRatio and the provided AA split ratio
  /// @param _tranche tranche token
  /// @param _AATrancheSplitRatio AA split ratio used for calculations
  /// @return apr for the specific tranche
  function _getApr(address _tranche, uint256 _AATrancheSplitRatio) internal view returns (uint256) {
    uint256 stratApr = strategyAPR();
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    bool isAATranche = _tranche == AATranche;
    if (_AATrancheSplitRatio == 0) {
      return isAATranche ? 0 : stratApr;
    }
    return isAATranche ?
      stratApr * _trancheAPRSplitRatio / _AATrancheSplitRatio :
      stratApr * (FULL_ALLOC - _trancheAPRSplitRatio) / (FULL_ALLOC - _AATrancheSplitRatio);
  }

  // ###################
  // Protected
  // ###################

  /// @notice can be called only by the rebalancer or the owner
  /// @dev it redeems rewards if any from the lending provider of the strategy and converts them in underlyings.
  /// it also deposits eventual unlent balance already present in the contract with the strategy.
  /// This method will be called by an exteranl keeper bot which will call the method sistematically (eg once a day)
  /// @param _skipRedeem whether to redeem rewards from strategy or not (for gas savings)
  /// @param _skipIncentivesUpdate whether to update incentives or not
  /// @param _skipReward array of flags for skipping the market sell of specific rewards. Lenght should be equal to the `getRewards()` array
  /// @param _minAmount array of min amounts for uniswap trades. Lenght should be equal to the _skipReward array
  function harvest(bool _skipRedeem, bool _skipIncentivesUpdate, bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    address _token = token;
    address _strategy = strategy;
    if (!_skipRedeem) {
      uint256 initialBalance = _contractNetUnderlyingBalance();
      // Fetch state variables once to save gas
      address _incentiveToken = incentiveToken;
      address _weth = weth;
      address _uniswapRouterV2 = address(uniswapRouterV2);
      // Redeem all rewards associated with the strategy
      IIdleCDOStrategy(_strategy).redeemRewards();
      // get all rewards addresses
      address[] memory rewards = getRewards();
      for (uint256 i = 0; i < rewards.length; i++) {
        address rewardToken = rewards[i];
        // get the balance of a specific reward
        uint256 _currentBalance = _contractTokenBalance(rewardToken);
        // check if it should be sold or not
        if (rewardToken == _incentiveToken || _skipReward[i] || _currentBalance == 0) { continue; }
        // Prepare path for uniswap trade
        address[] memory _path = new address[](3);
        _path[0] = rewardToken;
        _path[1] = _weth;
        _path[2] = _token;
        // approve the uniswap router to spend our reward
        IERC20Detailed(rewardToken).safeIncreaseAllowance(_uniswapRouterV2, _currentBalance);
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
      uint256 finalBalance = _contractNetUnderlyingBalance();
      if (finalBalance > initialBalance) {
        // split converted rewards and updated tranche prices for mint
        // NOTE: that fee on gov tokens will be accumulated in unclaimedFees
        _updatePrices();
        // Get fees in the form of totalSupply diluition
        _depositFees(unclaimedFees);
      }
      // update last saved prices for redeems at this point
      // if we arrived here we assume all reward tokens with 'big' balance have been sold in the market
      // others could have been skipped (with flags set off chain) but it just means that
      // were not worth a lot so should be safe to assume that those wont' be siphoned from a theft of interest attacks
      // NOTE: This method call should not be inside the `if finalBalance > initialBalance` just in case
      // no rewards are distributed from the underlying strategy
      _updateLastTranchePrices();
      if (!_skipIncentivesUpdate) {
        // Update tranche incentives distribution and send rewards to staking contracts
        _updateIncentives();
      }
    }
    // If we _skipRedeem we don't need to call _updatePrices because lastNAV is already updated
    // Put unlent balance at work in the lending provider
    IIdleCDOStrategy(_strategy).deposit(_contractTokenBalance(_token));
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

  /// @notice updates the strategy used (potentially changing the lending protocol used)
  /// @dev it's REQUIRED to liquidate / redeem everything from the lending provider before changing strategy
  /// if the lending provider is changes
  /// @param _strategy new strategy address
  function setStrategy(address _strategy) external onlyOwner {
    require(_strategy != address(0), 'IDLE:IS_0');
    IERC20Detailed _token = IERC20Detailed(token);
    // revoke allowance for the current strategy
    _token.safeApprove(strategy, 0);
    // Updated strategy variables
    strategy = _strategy;
    strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    // Approve underlyingToken
    _token.safeIncreaseAllowance(_strategy, type(uint256).max);
    // Approve strategyToken
    IERC20Detailed(strategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    // Update last strategy price
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
    skipDefaultCheck = true;
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

  /// @return bal balance of underlying for this contract
  function _contractNetUnderlyingBalance() internal view returns (uint256 bal) {
    // For gas efficiency, read only once
    uint256 _unclaimedFees = unclaimedFees;
    // Get current balance
    bal = _contractTokenBalance(token);
    // remove unclaimedFees if any
    return bal >= _unclaimedFees ? (bal - _unclaimedFees) : bal;
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
