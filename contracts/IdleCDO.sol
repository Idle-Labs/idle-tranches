// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";
import "./interfaces/IStakedAave.sol";

import "./GuardedLaunchUpgradable.sol";
import "./IdleCDOTranche.sol";
import "./IdleCDOStorage.sol";

/// @title A perpetual tranche implementation
/// @author Idle Labs Inc.
/// @notice More info and high level overview in the README
/// @dev The contract is upgradable, to add storage slots, create IdleCDOStorageVX and inherit from IdleCDOStorage, then update the definitaion below
contract IdleCDO is PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  // ERROR MESSAGES:
  // 0 = is 0
  // 1 = already initialized
  // 2 = Contract limit reached
  // 3 = Tranche withdraw not allowed (Paused or in shutdown)
  // 4 = Default, wait shutdown
  // 5 = Amount too low
  // 6 = Not authorized
  // 7 = Amount too high
  // 8 = Same block

  // Used to prevent initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    token = address(1);
  }

  // ###################
  // Initializer
  // ###################

  /// @notice can only be called once
  /// @dev Initialize the upgradable contract
  /// @param _limit contract value limit, can be 0
  /// @param _guardedToken underlying token
  /// @param _governanceFund address where funds will be sent in case of emergency
  /// @param _owner guardian address (can pause, unpause and call emergencyShutdown)
  /// @param _rebalancer rebalancer address
  /// @param _strategy strategy address
  /// @param _trancheAPRSplitRatio trancheAPRSplitRatio value
  /// @param _trancheIdealWeightRatio trancheIdealWeightRatio value
  /// @param _incentiveTokens array of addresses for incentive tokens
  function initialize(
    uint256 _limit, address _guardedToken, address _governanceFund, address _owner, // GuardedLaunch args
    address _rebalancer,
    address _strategy,
    uint256 _trancheAPRSplitRatio, // for AA tranches, so eg 10000 means 10% interest to AA and 90% BB
    uint256 _trancheIdealWeightRatio, // for AA tranches, so eg 10000 means 10% of tranches are AA and 90% BB
    address[] memory _incentiveTokens
  ) external initializer {
    require(token == address(0), '1');
    require(_rebalancer != address(0) && _strategy != address(0) && _guardedToken != address(0), "0");
    // Initialize contracts
    PausableUpgradeable.__Pausable_init();
    // check for _governanceFund and _owner != address(0) are inside GuardedLaunchUpgradable
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _governanceFund, _owner);
    // Deploy Tranches tokens
    address _strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    // get strategy token symbol (eg. idleDAI)
    string memory _symbol = IERC20Detailed(_strategyToken).symbol();
    // create tranche tokens (concat strategy token symbol in the name and symbol of the tranche tokens)
    AATranche = address(new IdleCDOTranche(_concat(string("IdleCDO AA Tranche - "), _symbol), _concat(string("AA_"), _symbol)));
    BBTranche = address(new IdleCDOTranche(_concat(string("IdleCDO BB Tranche - "), _symbol), _concat(string("BB_"), _symbol)));
    // Set CDO params
    token = _guardedToken;
    strategy = _strategy;
    strategyToken = _strategyToken;
    rebalancer = _rebalancer;
    trancheAPRSplitRatio = _trancheAPRSplitRatio;
    trancheIdealWeightRatio = _trancheIdealWeightRatio;
    idealRange = 10000; // trancheIdealWeightRatio ± 10%
    uint256 _oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    oneToken = _oneToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    incentiveTokens = _incentiveTokens;
    priceAA = _oneToken;
    priceBB = _oneToken;
    unlentPerc = 2000; // 2%
    // # blocks, after an harvest, during which harvested rewards gets progressively unlocked
    releaseBlocksPeriod = 1500; // about 1/4 of a day
    // Set flags
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;
    // skipDefaultCheck = false is the default value
    // Set allowance for strategy
    _allowUnlimitedSpend(_guardedToken, _strategy);
    _allowUnlimitedSpend(strategyToken, _strategy);
    // Save current strategy price
    lastStrategyPrice = _strategyPrice();
    // Fee params
    fee = 10000; // 10% performance fee
    feeReceiver = address(0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4); // feeCollector
    guardian = _owner;
    // StkAAVE unwrapping is active
    isStkAAVEActive = true;
  }

  // ###############
  // Public methods
  // ###############

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return AA tranche tokens minted
  function depositAA(uint256 _amount) external returns (uint256) {
    return _deposit(_amount, AATranche);
  }

  /// @notice pausable in _deposit
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return BB tranche tokens minted
  function depositBB(uint256 _amount) external returns (uint256) {
    return _deposit(_amount, BBTranche);
  }

  /// @notice pausable in _deposit
  /// @param _amount amount of AA tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawAA(uint256 _amount) external returns (uint256) {
    require(!paused() || allowAAWithdraw, '3');
    return _withdraw(_amount, AATranche);
  }

  /// @notice pausable
  /// @param _amount amount of BB tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawBB(uint256 _amount) external returns (uint256) {
    require(!paused() || allowBBWithdraw, '3');
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

  /// @notice calculates the current total value locked (in `token` terms)
  /// @dev unclaimed rewards (gov tokens) are not counted.
  /// NOTE: `unclaimedFees` are not included in the contract value
  /// NOTE2: fees that *will* be taken (in the next _updateAccounting call) are counted
  function getContractValue() public override view returns (uint256) {
    address _strategyToken = strategyToken;
    uint256 strategyTokenDecimals = IERC20Detailed(_strategyToken).decimals();
    // TVL is the sum of unlent balance in the contract + the balance in lending - the reduction for harvested rewards - unclaimedFees
    // the balance in lending is the value of the interest bearing assets (strategyTokens) in this contract
    // TVL = (strategyTokens * strategy token price) + unlent balance - lockedRewards - unclaimedFees
    return (_contractTokenBalance(_strategyToken) * _strategyPrice() / (10**(strategyTokenDecimals))) +
            _contractTokenBalance(token) -
            _lockedRewards() -
            unclaimedFees;
  }

  /// @param _tranche tranche address
  /// @return apr at ideal ratio (trancheIdealWeightRatio) between AA and BB
  function getIdealApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, trancheIdealWeightRatio);
  }

  /// @param _tranche tranche address
  /// @return actual apr given current ratio between AA and BB tranches
  function getApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, getCurrentAARatio());
  }

  /// @notice calculates the current AA tranches ratio
  /// @dev _virtualBalance is used to have a more accurate/recent value for the AA ratio
  /// because it calculates the balance after splitting the accrued interest since the
  /// last depositXX/withdrawXX/harvest
  /// @return AA tranches ratio (in underlying value) considering all interest
  function getCurrentAARatio() public view returns (uint256) {
    uint256 AABal = _virtualBalance(AATranche);
    uint256 contractVal = AABal + _virtualBalance(BBTranche);
    if (contractVal == 0) {
      return 0;
    }
    // Current AA tranche split ratio = AABal * FULL_ALLOC / (AABal + BBBal)
    return AABal * FULL_ALLOC / contractVal;
  }

  /// @notice calculates the current tranches price considering the interest that is yet to be splitted
  /// ie the interest generated since the last update of priceAA and priceBB (done on depositXX/withdrawXX/harvest)
  /// useful for showing updated gains on frontends
  /// @dev this should always be >= of _tranchePrice(_tranche)
  /// @param _tranche address of the requested tranche
  /// @return _virtualPrice tranche price considering all interest
  function virtualPrice(address _tranche) public view returns (uint256 _virtualPrice) {
    // get both NAVs, because we need the total NAV anyway
    uint256 _lastNAVAA = lastNAVAA;
    uint256 _lastNAVBB = lastNAVBB;

    (_virtualPrice, ) = _virtualPricesAux(
      _tranche,
      getContractValue(), // nav
      _lastNAVAA + _lastNAVBB, // lastNAV
      _tranche == AATranche ? _lastNAVAA : _lastNAVBB, // lastTrancheNAV
      trancheAPRSplitRatio
    );
  }

  /// @notice returns an array of tokens used to incentive tranches via IIdleCDOTrancheRewards
  /// @return array with addresses of incentiveTokens (can be empty)
  function getIncentiveTokens() external view returns (address[] memory) {
    return incentiveTokens;
  }

  // ###############
  // Internal
  // ###############

  /// @notice method used to deposit `token` and mint tranche tokens
  /// Ideally users should deposit right after an `harvest` call to maximize profit
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// automatically reverts on lending provider default (_strategyPrice decreased)
  /// @param _amount amount of underlyings (`token`) to deposit
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _deposit(uint256 _amount, address _tranche) internal whenNotPaused returns (uint256 _minted) {
    if (_amount == 0) {
      return _minted;
    }
    // check that we are not depositing more than the contract available limit
    _guarded(_amount);
    // set _lastCallerBlock hash
    _updateCallerBlock();
    // check if _strategyPrice decreased
    _checkDefault();
    // interest accrued since last depositXX/withdrawXX/harvest is splitted between AA and BB
    // according to trancheAPRSplitRatio. NAVs of AA and BB are updated and tranche
    // prices adjusted accordingly
    _updateAccounting();
    // get underlyings from sender
    IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
    // mint tranche tokens according to the current tranche price
    _minted = _mintShares(_amount, msg.sender, _tranche);
  }

  /// @notice this method is called on depositXX/withdrawXX/harvest and
  /// updates the accounting of the contract and effectively splits the yield between the
  /// AA and BB tranches
  /// @dev this method:
  /// - update tranche prices (priceAA and priceBB)
  /// - update net asset value for both tranches (lastNAVAA and lastNAVBB)
  /// - update fee accounting (unclaimedFees)
  function _updateAccounting() internal {
    uint256 _lastNAVAA = lastNAVAA;
    uint256 _lastNAVBB = lastNAVBB;
    uint256 _lastNAV = _lastNAVAA + _lastNAVBB;
    uint256 nav = getContractValue();
    uint256 _aprSplitRatio = trancheAPRSplitRatio;

    // If gain is > 0, then collect some fees in `unclaimedFees`
    if (nav > _lastNAV) {
      unclaimedFees += (nav - _lastNAV) * fee / FULL_ALLOC;
    }

    (uint256 _priceAA, uint256 _totalAAGain) = _virtualPricesAux(AATranche, nav, _lastNAV, _lastNAVAA, _aprSplitRatio);
    (uint256 _priceBB, uint256 _totalBBGain) = _virtualPricesAux(BBTranche, nav, _lastNAV, _lastNAVBB, _aprSplitRatio);

    lastNAVAA += _totalAAGain;
    lastNAVBB += _totalBBGain;
    priceAA = _priceAA;
    priceBB = _priceBB;
  }

  /// @notice calculates the NAV for a tranche considering the interest that is yet to be splitted
  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche considering all nav
  function _virtualBalance(address _tranche) internal view returns (uint256) {
    // balance is: tranche supply * virtual tranche price
    return IdleCDOTranche(_tranche).totalSupply() * virtualPrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice calculates the current tranches price considering the interest that is yet to be splitted and the
  /// total gain for a specific tranche
  /// @param _tranche address of the requested tranche
  /// @param _nav current NAV
  /// @param _lastNAV last saved NAV
  /// @param _lastTrancheNAV last saved tranche NAV
  /// @param _trancheAPRSplitRatio APR split ratio for AA tranche
  /// @return _virtualPrice tranche price considering all interest
  /// @return _totalTrancheGain tranche gain since last update
  function _virtualPricesAux(
    address _tranche,
    uint256 _nav,
    uint256 _lastNAV,
    uint256 _lastTrancheNAV,
    uint256 _trancheAPRSplitRatio
  ) internal view returns (uint256 _virtualPrice, uint256 _totalTrancheGain) {
    // If there is no gain return the current price
    if (_nav <= _lastNAV) {
      return (_tranchePrice(_tranche), 0);
    }

    // Check if there are tranche holders
    uint256 trancheSupply = IdleCDOTranche(_tranche).totalSupply();
    if (_lastNAV == 0 || trancheSupply == 0) {
      return (oneToken, 0);
    }
    // In order to correctly split the interest generated between AA and BB tranche holders
    // (according to the trancheAPRSplitRatio) we need to know how much interest we gained
    // since the last price update (during a depositXX/withdrawXX/harvest)
    // To do that we need to get the current value of the assets in this contract
    // and the last saved one (always during a depositXX/withdrawXX/harvest)

    // Calculate the total gain
    uint256 totalGain = _nav - _lastNAV;
    // Remove performance fee
    totalGain -= totalGain * fee / FULL_ALLOC;

    address _AATranche = AATranche;
    bool _isAATranche = _tranche == _AATranche;
    // Get the supply of the other tranche and
    // if it's 0 then give all gain to the current `_tranche` holders
    if (IdleCDOTranche(_isAATranche ? BBTranche : _AATranche).totalSupply() == 0) {
      _totalTrancheGain = totalGain;
    } else {
      // Split the net gain, with precision loss favoring the AA tranche.
      uint256 totalBBGain = totalGain * (FULL_ALLOC - _trancheAPRSplitRatio) / FULL_ALLOC;
      // The new NAV for the tranche is old NAV + total gain for the tranche
      _totalTrancheGain = _isAATranche ? (totalGain - totalBBGain) : totalBBGain;
    }
    // Split the new NAV (_lastTrancheNAV + _totalTrancheGain) per tranche token
    _virtualPrice = (_lastTrancheNAV + _totalTrancheGain) * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @notice mint tranche tokens and updates tranche last NAV
  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _mintShares(uint256 _amount, address _to, address _tranche) internal returns (uint256 _minted) {
    // calculate # of tranche token to mint based on current tranche price: _amount / tranchePrice
    _minted = _amount * ONE_TRANCHE_TOKEN / _tranchePrice(_tranche);
    IdleCDOTranche(_tranche).mint(_to, _minted);
    // update NAV with the _amount of underlyings added
    if (_tranche == AATranche) {
      lastNAVAA += _amount;
    } else {
      lastNAVBB += _amount;
    }
  }

  /// @notice convert fees (`unclaimedFees`) in tranche tokens
  /// the tranche token minted is based on the current AA ratio, so to mint the tranche
  /// that it's needed most to reach the trancheIdealWeightRatio. The tranche tokens
  /// are then automatically staked in the relative IdleCDOTrancheRewards contact if present
  /// @dev this will be called only during harvests
  /// @return _currAARatio current AA ratio
  function _depositFees() internal returns (uint256 _currAARatio) {
    uint256 _amount = unclaimedFees;
    if (_amount > 0) {
      _currAARatio = getCurrentAARatio();
      bool shouldMintBB = _currAARatio >= trancheIdealWeightRatio;
      address stakingRewards = shouldMintBB ? BBStaking : AAStaking;
      bool isStakingRewardsActive = stakingRewards != address(0);
      address _feeReceiver = feeReceiver;

      // mint tranches tokens to this contract
      uint256 _minted = _mintShares(_amount,
        isStakingRewardsActive ? address(this) : _feeReceiver,
        // Choose the right tranche to mint based on getCurrentAARatio
        shouldMintBB ? BBTranche : AATranche
      );
      // reset unclaimedFees counter
      unclaimedFees = 0;

      // auto stake fees in staking contract for feeReceiver
      if (isStakingRewardsActive) {
        IIdleCDOTrancheRewards(stakingRewards).stakeFor(_feeReceiver, _minted);
      }
    }
  }

  /// @notice It allows users to burn their tranche token and redeem their principal + interest back
  /// @dev automatically reverts on lending provider default (_strategyPrice decreased).
  /// @param _amount in tranche tokens
  /// @param _tranche tranche address
  /// @return toRedeem number of underlyings redeemed
  function _withdraw(uint256 _amount, address _tranche) internal nonReentrant returns (uint256 toRedeem) {
    // check if a deposit is made in the same block from the same user
    _checkSameTx();
    // check if _strategyPrice decreased
    _checkDefault();
    // accrue interest to tranches and updates tranche prices
    _updateAccounting();
    // redeem all user balance if 0 is passed as _amount
    if (_amount == 0) {
      _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
    }
    require(_amount > 0, '0');
    address _token = token;
    // get current available unlent balance
    uint256 balanceUnderlying = _contractTokenBalance(_token);
    // Calculate the amount to redeem
    toRedeem = _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    if (toRedeem > balanceUnderlying) {
      // if the unlent balance is not enough we try to redeem what's missing directly from the strategy
      // and then add it to the current unlent balance
      // NOTE: A difference of up to 100 wei due to rounding is tolerated
      toRedeem = _liquidate(toRedeem - balanceUnderlying, revertIfTooLow) + balanceUnderlying;
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);
    // send underlying to msg.sender
    IERC20Detailed(_token).safeTransfer(msg.sender, toRedeem);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= toRedeem;
    } else {
      lastNAVBB -= toRedeem;
    }
  }

  /// @dev check if _strategyPrice is decreased since last update and updates last saved strategy price
  function _checkDefault() internal {
    uint256 currPrice = _strategyPrice();
    if (!skipDefaultCheck) {
      require(lastStrategyPrice <= currPrice, "4");
    }
    lastStrategyPrice = currPrice;
  }

  /// @return strategy price, in underlyings
  function _strategyPrice() internal view returns (uint256) {
    return IIdleCDOStrategy(strategy).price();
  }

  /// @dev this should liquidate at least _amount of `token` from the lending provider or revertIfNeeded
  /// @param _amount in underlying tokens
  /// @param _revertIfNeeded flag whether to revert or not if the redeemed amount is not enough
  /// @return _redeemedTokens number of underlyings redeemed
  function _liquidate(uint256 _amount, bool _revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (_revertIfNeeded) {
      // keep 100 wei as margin for rounding errors
      require(_redeemedTokens + 100 >= _amount, '5');
    }
  }

  /// @notice sends rewards to the tranche rewards staking contracts
  /// @dev this method is called only during harvests
  /// @param currAARatio current AA tranche ratio
  function _updateIncentives(uint256 currAARatio) internal {
    // Read state variables only once to save gas
    uint256 _trancheIdealWeightRatio = trancheIdealWeightRatio;
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    uint256 _idealRange = idealRange;
    address _BBStaking = BBStaking;
    address _AAStaking = AAStaking;
    bool _isBBStakingActive = _BBStaking != address(0);
    bool _isAAStakingActive = _AAStaking != address(0);

    // Check if BB tranches should be rewarded (if AA ratio is too high)
    if (_isBBStakingActive && (currAARatio > (_trancheIdealWeightRatio + _idealRange))) {
      // give more rewards to BB holders, ie send some rewards to BB Staking contract
      return _depositIncentiveToken(_BBStaking, FULL_ALLOC);
    }
    // Check if AA tranches should be rewarded (id AA ratio is too low)
    if (_isAAStakingActive && (currAARatio < (_trancheIdealWeightRatio - _idealRange))) {
      // give more rewards to AA holders, ie send some rewards to AA Staking contract
      return _depositIncentiveToken(_AAStaking, FULL_ALLOC);
    }

    // Split rewards according to trancheAPRSplitRatio in case the ratio between
    // AA and BB is already ideal
    if (_isAAStakingActive) {
      // NOTE: the order is important here, first there must be the deposit for AA rewards,
      // if staking contract for AA is present
      _depositIncentiveToken(_AAStaking, _trancheAPRSplitRatio);
    }

    if (_isBBStakingActive) {
      // NOTE: here we should use FULL_ALLOC directly and not (FULL_ALLOC - _trancheAPRSplitRatio)
      // because contract balance for incentive tokens is fetched at each _depositIncentiveToken
      // and the balance for AA is already transferred
      _depositIncentiveToken(_BBStaking, FULL_ALLOC);
    }
  }

  /// @notice sends requested ratio of reward to a specific IdleCDOTrancheRewards contract
  /// @param _stakingContract address which will receive incentive Rewards
  /// @param _ratio ratio of the incentive token balance to send
  function _depositIncentiveToken(address _stakingContract, uint256 _ratio) internal {
    address[] memory _incentiveTokens = incentiveTokens;
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      address _incentiveToken = _incentiveTokens[i];
      // calculates the requested _ratio of the current contract balance of
      // _incentiveToken to be sent to the IdleCDOTrancheRewards contract
      uint256 _reward = _contractTokenBalance(_incentiveToken) * _ratio / FULL_ALLOC;
      if (_reward > 0) {
        // call depositReward to actually let the IdleCDOTrancheRewards get the reward
        IIdleCDOTrancheRewards(_stakingContract).depositReward(_incentiveToken, _reward);
      }
    }
  }

  /// @notice method used to sell `_rewardToken` for `_token` on uniswap
  /// @param _rewardToken address of the token to sell
  /// @param _path uniswap path for the trade
  /// @param _amount of `_rewardToken` to sell
  /// @param _minAmount min amount of `_token` to buy
  /// @return _amount of _rewardToken sold
  /// @return _amount received for the sell
  function _sellReward(address _rewardToken, address[] memory _path, uint256 _amount, uint256 _minAmount)
    internal
    returns (uint256, uint256) {
    // If 0 is passed as sell amount, we get the whole contract balance
    if (_amount == 0) {
      _amount = _contractTokenBalance(_rewardToken);
    }
    if (_amount == 0) {
      return (0, 0);
    }

    IUniswapV2Router02 _uniRouter = uniswapRouterV2;
    // approve the uniswap router to spend our reward
    IERC20Detailed(_rewardToken).safeIncreaseAllowance(address(_uniRouter), _amount);
    // do the trade with all `_rewardToken` in this contract
    uint256[] memory _amounts = _uniRouter.swapExactTokensForTokens(
      _amount,
      _minAmount,
      _path,
      address(this),
      block.timestamp + 1
    );
    // return the amount swapped and the amount received
    return (_amounts[0], _amounts[_amounts.length - 1]);
  }

  /// @notice method used to sell all sellable rewards for `_token` on uniswap
  /// @param _token to buy with rewards
  /// @param _sellAmounts array with amounts of rewards to sell
  /// @param _minAmount array with amounts of _token buy for each reward sold. (should have the same length as _sellAmounts)
  /// @param _skipReward array of flags for skipping the market sell of specific rewards (should have the same length as _sellAmounts)
  /// @return _soldAmounts array with amounts of rewards actually sold
  /// @return _swappedAmounts array with amounts of _token actually bought
  /// @return _totSold total rewards sold in `_token`
  function _sellAllRewards(address _token, uint256[] memory _sellAmounts, uint256[] memory _minAmount, bool[] memory _skipReward)
    internal
    returns (uint256[] memory _soldAmounts, uint256[] memory _swappedAmounts, uint256 _totSold) {
    // Fetch state variables once to save gas
    address[] memory _incentiveTokens = incentiveTokens;
    // get all rewards addresses
    address[] memory _rewards = IIdleCDOStrategy(strategy).getRewardTokens();
    address _rewardToken;
    // Prepare path for uniswap trade
    address[] memory _path = new address[](3);
    // _path[0] will be the reward token to sell
    _path[1] = weth;
    _path[2] = _token;
    // Initialize the return array, containing the amounts received after swapping reward tokens
    _soldAmounts = new uint256[](_rewards.length);
    _swappedAmounts = new uint256[](_rewards.length);
    // loop through all reward tokens
    for (uint256 i = 0; i < _rewards.length; i++) {
      _rewardToken = _rewards[i];
      // check if it should be sold or not
      if (_skipReward[i] || _includesAddress(_incentiveTokens, _rewardToken)) { continue; }
      // do not sell stkAAVE but only AAVE if present
      if (_rewardToken == stkAave) {
        _rewardToken = AAVE;
      }
      // set token to sell in the uniswap path
      _path[0] = _rewardToken;
      // Market sell _rewardToken in this contract for _token
      (_soldAmounts[i], _swappedAmounts[i]) = _sellReward(_rewardToken, _path, _sellAmounts[i], _minAmount[i]);
      _totSold += _swappedAmounts[i];
    }
  }

  /// @param _tranche tranche address
  /// @return last saved tranche price, in underlyings
  function _tranchePrice(address _tranche) internal view returns (uint256) {
    if (IdleCDOTranche(_tranche).totalSupply() == 0) {
      return oneToken;
    }
    return _tranche == AATranche ? priceAA : priceBB;
  }

  /// @notice returns the current apr for a tranche based on trancheAPRSplitRatio and the provided AA ratio
  /// @dev the apr for a tranche can be higher than the strategy apr
  /// @param _tranche tranche token address
  /// @param _AATrancheSplitRatio AA split ratio used for calculations
  /// @return apr for the specific tranche
  function _getApr(address _tranche, uint256 _AATrancheSplitRatio) internal view returns (uint256) {
    uint256 stratApr = IIdleCDOStrategy(strategy).getApr();
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    bool isAATranche = _tranche == AATranche;
    if (_AATrancheSplitRatio == 0) {
      // if there are no AA tranches, apr for AA is 0 (all apr to BB and it will be equal to stratApr)
      return isAATranche ? 0 : stratApr;
    }
    return isAATranche ?
      // AA apr is: stratApr * AAaprSplitRatio / AASplitRatio
      stratApr * _trancheAPRSplitRatio / _AATrancheSplitRatio :
      // BB apr is: stratApr * BBaprSplitRatio / BBSplitRatio -> where
      // BBaprSplitRatio is: (FULL_ALLOC - _trancheAPRSplitRatio) and
      // BBSplitRatio is: (FULL_ALLOC - _AATrancheSplitRatio)
      stratApr * (FULL_ALLOC - _trancheAPRSplitRatio) / (FULL_ALLOC - _AATrancheSplitRatio);
  }

  /// @return _locked amount of harvested rewards that are still not available to be redeemed
  function _lockedRewards() internal view returns (uint256 _locked) {
    uint256 _releaseBlocksPeriod = releaseBlocksPeriod;
    uint256 _blocksSinceLastHarvest = block.number - latestHarvestBlock;
    uint256 _harvestedRewards = harvestedRewards;

    if (_harvestedRewards > 0 && _blocksSinceLastHarvest < _releaseBlocksPeriod) {
      // progressively release harvested rewards
      _locked = _harvestedRewards * (_releaseBlocksPeriod - _blocksSinceLastHarvest) / _releaseBlocksPeriod;
    }
  }

  /// @notice used to start the cooldown for unstaking stkAAVE and claiming AAVE rewards (for the contract itself)
  function _claimStkAave() internal {
    if (!isStkAAVEActive) {
      return;
    }

    IStakedAave _stkAave = IStakedAave(stkAave);
    uint256 _stakersCooldown = _stkAave.stakersCooldowns(address(this));
    // If there is a pending cooldown:
    if (_stakersCooldown > 0) {
      // If it is over, redeem stkAave and begin new cooldown
      if (_stakersCooldown + _stkAave.COOLDOWN_SECONDS() < block.timestamp) {
        _stkAave.redeem(address(this), type(uint256).max);
      } else {
        // If it is not over, do nothing
        return;
      }
    }

    // Pull new stkAAVE rewards
    IIdleCDOStrategy(strategy).pullStkAAVE();

    // If there's no pending cooldown or we just redeem the prev locked rewards,
    // then begin a new cooldown
    if (_stkAave.balanceOf(address(this)) > 0) {
      // start a new cooldown
      _stkAave.cooldown();
    }
  }

  // ###################
  // Protected
  // ###################

  /// @notice This method is used to lend user funds in the lending provider through the IIdleCDOStrategy and update tranches incentives.
  /// The method:
  /// - redeems rewards (if any) from the lending provider
  /// - converts the rewards NOT present in the `incentiveTokens` array, in underlyings through uniswap v2
  /// - calls _updateAccounting to update the accounting of the system with the new underlyings received
  /// - it then convert fees in tranche tokens and stake tranche tokens in the IdleCDOTrancheRewards if any
  /// - sends the correct amount of `incentiveTokens` to the each of the IdleCDOTrancheRewards contracts
  /// - Finally it deposits the (initial unlent balance + the underlyings get from uniswap - fees) in the
  ///   lending provider through the IIdleCDOStrategy `deposit` call
  /// The method will be called by an external, whitelisted, keeper bot which will call the method sistematically (eg once a day)
  /// @dev can be called only by the rebalancer or the owner
  /// @param _skipRedeem whether to redeem rewards from strategy or not (for gas savings)
  /// @param _skipIncentivesUpdate whether to update incentives or not
  /// @param _skipFeeDeposit whether to convert fees in tranche tokens or not
  /// @param _skipReward array of flags for skipping the market sell of specific rewards. Lenght should be equal to the `IIdleCDOStrategy(strategy).getRewardTokens()` array
  /// @param _minAmount array of min amounts for uniswap trades. Lenght should be equal to the _skipReward array
  /// @param _sellAmounts array of amounts (of reward tokens) to sell on uniswap. Lenght should be equal to the _minAmount array
  /// if a sellAmount is 0 the whole contract balance for that token is swapped
  /// @return _soldAmounts array with amounts of rewards actually sold
  /// @return _swappedAmounts array with amounts of _token actually bought
  function harvest(
    bool _skipRedeem,
    bool _skipIncentivesUpdate,
    bool _skipFeeDeposit,
    bool[] calldata _skipReward,
    uint256[] calldata _minAmount,
    uint256[] calldata _sellAmounts
  ) external
    returns (uint256[] memory _soldAmounts, uint256[] memory _swappedAmounts, uint256[] memory _redeemedRewards) {
    require(msg.sender == rebalancer || msg.sender == owner(), "6");
    // Fetch state variable once to save gas
    address _token = token;
    address _strategy = strategy;
    // Check whether to redeem rewards from strategy or not
    if (!_skipRedeem || !_skipIncentivesUpdate || !_skipFeeDeposit) {
      uint256 _totSold;

      if (!_skipRedeem) {
        // Redeem all rewards associated with the strategy
        _redeemedRewards = IIdleCDOStrategy(_strategy).redeemRewards();
        // Redeem unlocked AAVE if any and start a new cooldown for stkAAVE
        _claimStkAave();
        // Sell rewards
        (_soldAmounts, _swappedAmounts, _totSold) = _sellAllRewards(_token, _sellAmounts, _minAmount, _skipReward);
      }
      // update last saved harvest block number
      latestHarvestBlock = block.number;
      // update harvested rewards value
      harvestedRewards = _totSold;
      // split converted rewards if any and update tranche prices
      // NOTE: harvested rewards won't be counted directly but released over time
      _updateAccounting();

      uint256 currAARatio;
      if (!_skipFeeDeposit) {
        // Get fees in the form of totalSupply diluition
        // NOTE we return currAARatio to reuse it in _updateIncentives and so to save some gas
        currAARatio = _depositFees();
      }

      if (!_skipIncentivesUpdate) {
        // Update tranche incentives distribution and send rewards to staking contracts
        _updateIncentives(currAARatio == 0 ? getCurrentAARatio() : currAARatio);
      }
    }

    // Keep some unlent balance for cheap redeems and as reserve of last resort
    uint256 underlyingBal = _contractTokenBalance(_token);
    uint256 idealUnlent = getContractValue() * unlentPerc / FULL_ALLOC;
    if (underlyingBal > idealUnlent) {
      // Put unlent balance at work in the lending provider
      IIdleCDOStrategy(_strategy).deposit(underlyingBal - idealUnlent);
    }
  }

  /// @notice method used to redeem underlyings from the lending provider
  /// @dev can be called only by the rebalancer or the owner
  /// @param _amount in underlyings to liquidate from lending provider
  /// @param _revertIfNeeded flag to revert if amount liquidated is too low
  /// @return liquidated amount in underlyings
  function liquidate(uint256 _amount, bool _revertIfNeeded) external returns (uint256) {
    require(msg.sender == rebalancer || msg.sender == owner(), "6");
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

  /// @param _allowed flag to enable the 'default' check (whether _strategyPrice decreased or not)
  function setSkipDefaultCheck(bool _allowed) external onlyOwner {
    skipDefaultCheck = _allowed;
  }

  /// @param _allowed flag to enable the check if redeemed amount during liquidations is enough
  function setRevertIfTooLow(bool _allowed) external onlyOwner {
    revertIfTooLow = _allowed;
  }

  /// @notice updates the strategy used (potentially changing the lending protocol used)
  /// @dev it's REQUIRED to liquidate / redeem everything from the lending provider before changing strategy
  /// if the leding provider of the new strategy is different from the current one
  /// it's also REQUIRED to transfer out any incentive tokens accrued if those are changed from the current ones
  /// if the lending provider is changed
  /// @param _strategy new strategy address
  /// @param _incentiveTokens array of incentive tokens addresses
  function setStrategy(address _strategy, address[] memory _incentiveTokens) external onlyOwner {
    require(_strategy != address(0), '0');
    IERC20Detailed _token = IERC20Detailed(token);
    // revoke allowance for the current strategy
    address _currStrategy = strategy;
    _removeAllowance(address(_token), _currStrategy);
    _removeAllowance(strategyToken, _currStrategy);
    // Updated strategy variables
    strategy = _strategy;
    // Update incentive tokens
    incentiveTokens = _incentiveTokens;
    // Update strategyToken
    address _newStrategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    strategyToken = _newStrategyToken;
    // Approve underlyingToken
    _allowUnlimitedSpend(address(_token), _strategy);
    // Approve the new strategy to transfer strategyToken out from this contract
    _allowUnlimitedSpend(_newStrategyToken, _strategy);
    // Update last strategy price
    lastStrategyPrice = _strategyPrice();
  }

  /// @param _rebalancer new rebalancer address
  function setRebalancer(address _rebalancer) external onlyOwner {
    require((rebalancer = _rebalancer) != address(0), '0');
  }

  /// @param _feeReceiver new fee receiver address
  function setFeeReceiver(address _feeReceiver) external onlyOwner {
    require((feeReceiver = _feeReceiver) != address(0), '0');
  }

  /// @param _guardian new guardian (pauser) address
  function setGuardian(address _guardian) external onlyOwner {
    require((guardian = _guardian) != address(0), '0');
  }

  /// @param _fee new fee
  function setFee(uint256 _fee) external onlyOwner {
    require((fee = _fee) <= MAX_FEE, '7');
  }

  /// @param _unlentPerc new unlent percentage
  function setUnlentPerc(uint256 _unlentPerc) external onlyOwner {
    require((unlentPerc = _unlentPerc) <= FULL_ALLOC, '7');
  }

  /// @param _releaseBlocksPeriod new # of blocks after an harvest during which
  /// harvested rewards gets progressively redistriburted to users
  function setReleaseBlocksPeriod(uint256 _releaseBlocksPeriod) external onlyOwner {
    releaseBlocksPeriod = _releaseBlocksPeriod;
  }

  /// @param _isStkAAVEActive whether the contract receive stkAAVE or not
  function setIsStkAAVEActive(bool _isStkAAVEActive) external onlyOwner {
    isStkAAVEActive = _isStkAAVEActive;
  }

  /// @param _idealRange new ideal range
  function setIdealRange(uint256 _idealRange) external onlyOwner {
    require((idealRange = _idealRange) <= FULL_ALLOC, '7');
  }

  /// @dev it's REQUIRED to transfer out any incentive tokens accrued before
  /// @param _incentiveTokens array with new incentive tokens
  function setIncentiveTokens(address[] memory _incentiveTokens) external onlyOwner {
    incentiveTokens = _incentiveTokens;
  }

  /// @notice Set tranche Rewards contract addresses (for tranches incentivization)
  /// @param _AAStaking IdleCDOTrancheRewards contract address for AA tranches
  /// @param _BBStaking IdleCDOTrancheRewards contract address for BB tranches
  function setStakingRewards(address _AAStaking, address _BBStaking) external onlyOwner {
    // Read state variable once
    address _AATranche = AATranche;
    address _BBTranche = BBTranche;
    address[] memory _incentiveTokens = incentiveTokens;
    address _currAAStaking = AAStaking;
    address _currBBStaking = BBStaking;
    bool _isAAStakingActive = _currAAStaking != address(0);
    bool _isBBStakingActive = _currBBStaking != address(0);
    address _incentiveToken;
    // Remove allowance for incentive tokens for current staking contracts
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      _incentiveToken = _incentiveTokens[i];
      if (_isAAStakingActive) {
        _removeAllowance(_incentiveToken, _currAAStaking);
      }
      if (_isBBStakingActive) {
        _removeAllowance(_incentiveToken, _currBBStaking);
      }
    }
    // Remove allowace for tranche tokens (used for staking fees)
    if (_isAAStakingActive && _AATranche != address(0)) {
      _removeAllowance(_AATranche, _currAAStaking);
    }
    if (_isBBStakingActive && _BBTranche != address(0)) {
      _removeAllowance(_BBTranche, _currBBStaking);
    }

    // Update staking contract addresses
    AAStaking = _AAStaking;
    BBStaking = _BBStaking;

    _isAAStakingActive = _AAStaking != address(0);
    _isBBStakingActive = _BBStaking != address(0);

    // Increase allowance for incentiveTokens
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      _incentiveToken = _incentiveTokens[i];
      // Approve each staking contract to spend each incentiveToken on beahlf of this contract
      if (_isAAStakingActive) {
        _allowUnlimitedSpend(_incentiveToken, _AAStaking);
      }
      if (_isBBStakingActive) {
        _allowUnlimitedSpend(_incentiveToken, _BBStaking);
      }
    }

    // Increase allowance for tranche tokens (used for staking fees)
    if (_isAAStakingActive && _AATranche != address(0)) {
      _allowUnlimitedSpend(_AATranche, _AAStaking);
    }
    if (_isBBStakingActive && _BBTranche != address(0)) {
      _allowUnlimitedSpend(_BBTranche, _BBStaking);
    }
  }

  /// @notice pause deposits and redeems for all classes of tranches
  /// @dev can be called by both the owner and the guardian
  function emergencyShutdown() external {
    require(msg.sender == guardian || msg.sender == owner(), "6");
    // prevent deposits
    _pause();
    // prevent withdraws
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    // Allow deposits/withdraws (once selectively re-enabled, eg for AA holders)
    // without checking for lending protocol default
    skipDefaultCheck = true;
    revertIfTooLow = true;
  }

  /// @notice Pauses deposits and redeems
  /// @dev can be called by both the owner and the guardian
  function pause() external  {
    require(msg.sender == guardian || msg.sender == owner(), "6");
    _pause();
  }

  /// @notice Unpauses deposits and redeems
  /// @dev can be called by both the owner and the guardian
  function unpause() external {
    require(msg.sender == guardian || msg.sender == owner(), "6");
    _unpause();
  }

  // ###################
  // Helpers
  // ###################

  /// @notice returns the current balance of this contract for a specific token
  /// @param _token token address
  /// @return balance of `_token` for this contract
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
  }

  /// @dev Set allowance for _token to 0 for _spender
  /// @param _token token address
  /// @param _spender spender address
  function _removeAllowance(address _token, address _spender) internal {
    IERC20Detailed(_token).safeApprove(_spender, 0);
  }

  /// @dev Set allowance for _token to unlimited for _spender
  /// @param _token token address
  /// @param _spender spender address
  function _allowUnlimitedSpend(address _token, address _spender) internal {
    IERC20Detailed(_token).safeIncreaseAllowance(_spender, type(uint256).max);
  }

  /// @dev Set last caller and block.number hash. This should be called at the beginning of the first function to protect
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  /// @dev Check that the second function is not called in the same tx from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "8");
  }

  /// @dev this method is only used to check whether a token is an incentive tokens or not
  /// in the harvest call. The maximum number of element in the array will be a small number (eg at most 3-5)
  /// @param _array array of addresses to search for an element
  /// @param _val address of an element to find
  /// @return flag if the _token is an incentive token or not
  function _includesAddress(address[] memory _array, address _val) internal pure returns (bool) {
    for (uint256 i = 0; i < _array.length; i++) {
      if (_array[i] == _val) {
        return true;
      }
    }
    // explicit return to fix linter
    return false;
  }

  /// @notice concat 2 strings in a single one
  /// @param a first string
  /// @param b second string
  /// @return new string with a and b concatenated
  function _concat(string memory a, string memory b) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b));
  }
}
