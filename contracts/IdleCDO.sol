// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";

import "./GuardedLaunchUpgradable.sol";
import "./IdleCDOTranche.sol";
import "./IdleCDOStorage.sol";

/// @title A continous tranche implementation
/// @author Idle Labs Inc.
/// @notice More info and high level overview in the README
/// @dev The contract is upgradable, to add storage slots, create IdleCDOStorageVX and inherit from IdleCDOStorage, then update the definitaion below
contract IdleCDO is Initializable, PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

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
  /// @param _owner guardian address
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
  ) public initializer {
    require(token == address(0), 'Initialized');
    // Initialize contracts
    PausableUpgradeable.__Pausable_init();
    // check for _governanceFund and _owner != address(0) are inside GuardedLaunchUpgradable
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _governanceFund, _owner);
    // Deploy Tranches tokens
    address _strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    // get strategy token symbol (eg. idleDAI)
    string memory _symbol = IERC20Detailed(_strategyToken).symbol();
    // create tranche tokens (concat strategy token symbol in the name and symbol of the tranche tokens)
    AATranche = address(new IdleCDOTranche(_concat(string("IdleCDO AA Tranche - "), _symbol), _concat(string("IDLECDO_AA_"), _symbol)));
    BBTranche = address(new IdleCDOTranche(_concat(string("IdleCDO BB Tranche - "), _symbol), _concat(string("IDLECDO_BB_"), _symbol)));
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
    lastAAPrice = _oneToken;
    lastBBPrice = _oneToken;
    unlentPerc = 2000; // 2%
    // Set flags
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;
    // skipDefaultCheck = false is the default value
    // Set allowance for strategy
    IERC20Detailed(_guardedToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    IERC20Detailed(strategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    // Save current strategy price
    lastStrategyPrice = strategyPrice();
    // Fee params
    fee = 10000; // 10% performance fee
    feeReceiver = address(0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4); // feeCollector
    guardian = _owner;
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
  function withdrawAA(uint256 _amount) external nonReentrant returns (uint256) {
    require(!paused() || allowAAWithdraw, 'IDLE:AA_!ALLOWED');
    return _withdraw(_amount, AATranche);
  }

  /// @notice pausable
  /// @param _amount amount of BB tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawBB(uint256 _amount) external nonReentrant returns (uint256) {
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

  /// @notice calculates the current total value locked (in `token` terms)
  /// @dev rewards (gov tokens) are not counted. It may include non accrued fees (in unclaimedFees)
  /// @return contract value in underlyings
  function getContractValue() public override view returns (uint256) {
    address _strategyToken = strategyToken;
    uint256 strategyTokenDecimals = IERC20Detailed(_strategyToken).decimals();
    // TVL is the sum of unlent balance in the contract + the balance in lending
    // which is the value of the interest bearing assets (strategyTokens) in this contract
    // TVL = (strategyTokens * strategy token price) + unlent balance
    return (_contractTokenBalance(_strategyToken) * strategyPrice() / (10**(strategyTokenDecimals))) + _contractTokenBalance(token);
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

  /// @return strategy net apr
  function strategyAPR() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).getApr();
  }

  /// @return strategy price, in underlyings
  function strategyPrice() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).price();
  }

  /// @return array of reward token addresses that the strategy gives during lending
  function getRewards() public view returns (address[] memory) {
    return IIdleCDOStrategy(strategy).getRewardTokens();
  }

  /// @notice calculates the current AA tranches ratio
  /// @dev virtualBalance is used to have a more accurate/recent value for the AA ratio
  /// because it calculates the balance after splitting the accrued interest since the
  /// last depositXX/withdrawXX/harvest
  /// @return AA tranches ratio (in underlying value) considering all interest
  function getCurrentAARatio() public view returns (uint256) {
    uint256 AABal = virtualBalance(AATranche);
    uint256 contractVal = AABal + virtualBalance(BBTranche);
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
  /// @return tranche price considering all interest
  function virtualPrice(address _tranche) public view returns (uint256) {
    // priceAA and priceBB are updated only on depositXX/withdrawXX/harvest
    // so to have the 'real', up-to-date price of a tranche we should also consider
    // the interest that we accrued since the last price update.
    // To do that we need to know the interest we get since the last update so
    // we get the current NAV and the last one (saved during a depositXX/withdrawXX/harvest)
    uint256 nav = getContractValue();
    uint256 lastNAV = _lastNAV();
    uint256 trancheSupply = IdleCDOTranche(_tranche).totalSupply();

    if (lastNAV == 0 || trancheSupply == 0) {
      return oneToken;
    }
    // The gain that should be splitted among the 2 tranches is: nav - lastNAV
    // If there is no gain return the current saved price
    if (nav <= lastNAV) {
      return _tranchePrice(_tranche);
    }
    // Calculate the gain
    uint256 gain = nav - lastNAV;
    // remove performance fee
    gain -= gain * fee / FULL_ALLOC;
    // we now have the net gain that should be splitted among the tranches according to trancheAPRSplitRatio
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    // the NAV of a single tranche is: lastNAV + trancheGain
    uint256 trancheNAV;
    if (_tranche == AATranche) {
      // calculate gain for AA tranche
      // trancheGain (AAGain) = gain * trancheAPRSplitRatio / FULL_ALLOC;
      trancheNAV = lastNAVAA + (gain * _trancheAPRSplitRatio / FULL_ALLOC);
    } else {
      // calculate gain for BB tranche
      // trancheGain (BBGain) = gain * (FULL_ALLOC - trancheAPRSplitRatio) / FULL_ALLOC;
      trancheNAV = lastNAVBB + (gain * (FULL_ALLOC - _trancheAPRSplitRatio) / FULL_ALLOC);
    }
    // tranche price is: trancheNAV * ONE_TRANCHE_TOKEN / trancheSupply
    return trancheNAV * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @notice calculates the NAV for a tranche considering the interest that is yet to be splitted
  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche considering all nav
  function virtualBalance(address _tranche) public view returns (uint256) {
    // balance is: tranche supply * virtual tranche price
    return IdleCDOTranche(_tranche).totalSupply() * virtualPrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice returns an array of tokens used to incentive tranches via IIdleCDOTrancheRewards
  /// @return array with addresses of incentiveTokens (can be empty)
  function getIncentiveTokens() public view returns (address[] memory) {
    return incentiveTokens;
  }

  // ###############
  // Internal
  // ###############

  /// @notice method used to deposit `token` and mint tranche tokens
  /// Ideally users should deposit right after an `harvest` call to maximize profit
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// automatically reverts on lending provider default (strategyPrice decreased)
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
    // interest accrued since last depositXX/withdrawXX/harvest is splitted between AA and BB
    // according to trancheAPRSplitRatio. NAVs of AA and BB are updated and tranche
    // prices adjusted accordingly
    _updatePrices();
    // mint tranche tokens according to the current tranche price
    _minted = _mintShares(_amount, msg.sender, _tranche);
    // get underlyings from sender
    IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  /// @notice this method is called on depositXX/withdrawXX/harvest and
  /// updates the accounting of the contract and effectively splits the yield between the
  /// AA and BB tranches
  /// @dev this method:
  /// - update tranche prices (priceAA and priceBB)
  /// - update net asset value for both tranches (lastNAVAA and lastNAVBB)
  /// - update fee accounting (unclaimedFees)
  function _updatePrices() internal {
    // In order to correctly split the interest generated between AA and BB tranche holders
    // (according to the trancheAPRSplitRatio) we need to know how much interest we gained
    // since the last price update (during a depositXX/withdrawXX/harvest)
    // To do that we need to get the current value of the assets in this contract
    // and the last saved one (always during a depositXX/withdrawXX/harvest)
    uint256 _oneToken = oneToken;
    // get last saved total net asset value
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0) {
      return;
    }
    // The gain that should be splitted among the 2 tranches is: nav - lastNAV
    uint256 nav = getContractValue();
    // If there is no gain do nothing
    if (nav <= lastNAV) {
      return;
    }
    // Calculate gain since last update
    uint256 gain = nav - lastNAV;
    // remove the performance fee
    uint256 performanceFee = gain * fee / FULL_ALLOC;
    gain -= performanceFee;
    // and add the performance fee amount to unclaimedFees variable
    // (those will be then converted in tranche tokens at the next harvest via _depositFees method)
    unclaimedFees += performanceFee;
    // we now have the net gain (`gain`) that should be splitted among the tranches according to trancheAPRSplitRatio
    // Get the current tranche supply for
    uint256 AATotSupply = IdleCDOTranche(AATranche).totalSupply();
    uint256 BBTotSupply = IdleCDOTranche(BBTranche).totalSupply();
    uint256 AAGain;
    uint256 BBGain;
    if (BBTotSupply == 0) {
      // if there are no BB holders, all gain to AA
      AAGain = gain;
    } else if (AATotSupply == 0) {
      // if there are no AA holders, all gain to BB
      BBGain = gain;
    } else {
      // split the gain between AA and BB holders according to trancheAPRSplitRatio
      AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
      BBGain = gain - AAGain;
    }
    // Update NAVs
    lastNAVAA += AAGain;
    // BBGain
    lastNAVBB += BBGain;
    // Update tranche prices
    // tranche price is: trancheNAV / trancheSupply
    priceAA = AATotSupply > 0 ? lastNAVAA * ONE_TRANCHE_TOKEN / AATotSupply : _oneToken;
    priceBB = BBTotSupply > 0 ? lastNAVBB * ONE_TRANCHE_TOKEN / BBTotSupply : _oneToken;
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
  /// that it's needed most to reach the trancheIdealWeightRatio
  /// @dev this will be called only during harvests
  /// @return _currAARatio current AA ratio
  function _depositFees() internal returns (uint256 _currAARatio) {
    uint256 _amount = unclaimedFees;
    if (_amount > 0) {
      _currAARatio = getCurrentAARatio();
      _mintShares(_amount, feeReceiver,
        // Choose the right tranche to mint based on getCurrentAARatio
        _currAARatio >= trancheIdealWeightRatio ? BBTranche : AATranche
      );
      // reset unclaimedFees counter
      unclaimedFees = 0;
    }
  }

  /// @notice updates last tranche prices with the current ones
  /// @dev last tranche prices are used on withdrawXX methods, instead of priceXX,
  /// to avoid theft of interest when calling harvest to market sell reward for `token`
  /// (which will increase priceAA and priceBB)
  function _updateLastTranchePrices() internal {
    lastAAPrice = priceAA;
    lastBBPrice = priceBB;
  }

  /// @notice It allows users to burn their tranche token and redeem their principal + interest back
  /// @dev automatically reverts on lending provider default (strategyPrice decreased).
  /// A user should wait at least one harvest before rededeming otherwise the redeemed amount
  /// would be less than the deposited one due to the use of a checkpointed price at last harvest (lastAAPrice and lastBBPrice)
  /// Ideally users should redeem right after an `harvest` call for maximum profits
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
    address _token = token;
    // get current unlent balance
    uint256 balanceUnderlying = _contractTokenBalance(_token);
    // Calculate the amount to redeem using the checkpointed price from last harvest
    // NOTE: if use _tranchePrice directly one can deposit a huge amount before an harvest
    // to steal interest generated when calling harvest and rewards are market sold
    toRedeem = _amount * _lastTranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
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

  /// @dev check if strategyPrice is decreased since last update and updates last saved strategy price
  function _checkDefault() internal {
    uint256 currPrice = strategyPrice();
    if (!skipDefaultCheck) {
      require(lastStrategyPrice <= currPrice, "IDLE:DEFAULT_WAIT_SHUTDOWN");
    }
    lastStrategyPrice = currPrice;
  }

  /// @dev this should liquidate at least _amount of `token` from the lending provider or revertIfNeeded
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

    // Check if BB tranches should be rewarded (if AA ratio is too high)
    if (_BBStaking != address(0) && (currAARatio > (_trancheIdealWeightRatio + _idealRange))) {
      // give more rewards to BB holders, ie send some rewards to BB Staking contract
      return _depositIncentiveToken(_BBStaking, FULL_ALLOC);
    }
    // Check if AA tranches should be rewarded (id AA ratio is too low)
    if (_AAStaking != address(0) && (currAARatio < (_trancheIdealWeightRatio - _idealRange))) {
      // give more rewards to AA holders, ie send some rewards to AA Staking contract
      return _depositIncentiveToken(_AAStaking, FULL_ALLOC);
    }

    // Split rewards according to trancheAPRSplitRatio in case the ratio between
    // AA and BB is already ideal
    // NOTE: the order is important here, first there must be the deposit for AA rewards
    _depositIncentiveToken(_AAStaking, _trancheAPRSplitRatio);
    // NOTE: here we should use FULL_ALLOC directly and not (FULL_ALLOC - _trancheAPRSplitRatio)
    // because contract balance for incentive tokens is fetched at each _depositIncentiveToken
    // and the balance for AA already transferred
    _depositIncentiveToken(_BBStaking, FULL_ALLOC);
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

  /// @notice returns the current apr for a tranche based on trancheAPRSplitRatio and the provided AA ratio
  /// @dev the apr for a tranche can be higher than the strategy apr
  /// @param _tranche tranche token address
  /// @param _AATrancheSplitRatio AA split ratio used for calculations
  /// @return apr for the specific tranche
  function _getApr(address _tranche, uint256 _AATrancheSplitRatio) internal view returns (uint256) {
    uint256 stratApr = strategyAPR();
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

  // ###################
  // Protected
  // ###################

  /// @notice This method is used to lend user funds in the lending provider through the IIdleCDOStrategy and update tranches incentives.
  /// The method:
  /// - redeems rewards (if any) from the lending provider
  /// - converts the rewards NOT present in the `incentiveTokens` array, in underlyings through uniswap v2
  /// - calls _updatePrices and _updateLastTranchePrices to update the accounting of the system with the new underlyings received
  /// - it then convert fees in tranche tokens
  /// - sends the correct amount of `incentiveTokens` to the each of the IdleCDOTrancheRewards contracts
  /// - Finally it deposits the (initial unlent balance + the underlyings get from uniswap - fees) in the
  ///   lending provider through the IIdleCDOStrategy `deposit` call
  /// The method will be called by an external, whitelisted, keeper bot which will call the method sistematically (eg once a day)
  /// @dev can be called only by the rebalancer or the owner
  /// @param _skipRedeem whether to redeem rewards from strategy or not (for gas savings)
  /// @param _skipIncentivesUpdate whether to update incentives or not
  /// @param _skipReward array of flags for skipping the market sell of specific rewards. Lenght should be equal to the `getRewards()` array
  /// @param _minAmount array of min amounts for uniswap trades. Lenght should be equal to the _skipReward array
  function harvest(bool _skipRedeem, bool _skipIncentivesUpdate, bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    // Fetch state variable once to save gas
    address _token = token;
    address _strategy = strategy;
    // Check whether to redeem rewards from strategy or not
    if (!_skipRedeem) {
      // Fetch state variables once to save gas
      address[] memory _incentiveTokens = incentiveTokens;
      address _weth = weth;
      IUniswapV2Router02 _uniRouter = uniswapRouterV2;
      // Redeem all rewards associated with the strategy
      IIdleCDOStrategy(_strategy).redeemRewards();
      // get all rewards addresses
      address[] memory rewards = getRewards();
      for (uint256 i = 0; i < rewards.length; i++) {
        address rewardToken = rewards[i];
        // get the balance of a specific reward
        uint256 _currentBalance = _contractTokenBalance(rewardToken);
        // check if it should be sold or not
        if (_skipReward[i] || _currentBalance == 0 || _includesAddress(_incentiveTokens, rewardToken)) { continue; }
        // Prepare path for uniswap trade
        address[] memory _path = new address[](3);
        _path[0] = rewardToken;
        _path[1] = _weth;
        _path[2] = _token;
        // approve the uniswap router to spend our reward
        IERC20Detailed(rewardToken).safeIncreaseAllowance(address(_uniRouter), _currentBalance);
        // do the uniswap trade
        _uniRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          _currentBalance,
          _minAmount[i],
          _path,
          address(this),
          block.timestamp + 1
        );
      }
      // split converted rewards and update tranche prices for mint
      // NOTE: that fee on gov tokens will be accumulated in unclaimedFees
      _updatePrices();
      // update last saved prices for redeems at this point
      // if we arrived here we assume all reward tokens with 'big' balance have been sold in the market
      // others could have been skipped (with flags set off chain) but it just means that
      // were not worth a lot so should be safe to assume that those wont' be siphoned from theft of interest attacks
      _updateLastTranchePrices();

      // Get fees in the form of totalSupply diluition
      // NOTE we return currAARatio to reuse it in _updateIncentives and so to save some gas
      uint256 currAARatio = _depositFees();

      if (!_skipIncentivesUpdate) {
        // Update tranche incentives distribution and send rewards to staking contracts
        _updateIncentives(currAARatio);
      }
    }
    // If we _skipRedeem we don't need to call _updatePrices because lastNAV is already updated

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
  /// if the leding provider of the new strategy is different from the current one
  /// it's also REQUIRED to transfer out any incentive tokens accrued if those are changed from the current ones
  /// if the lending provider is changed
  /// @param _strategy new strategy address
  /// @param _incentiveTokens array of incentive tokens addresses
  function setStrategy(address _strategy, address[] memory _incentiveTokens) external onlyOwner {
    require(_strategy != address(0), 'IDLE:IS_0');
    IERC20Detailed _token = IERC20Detailed(token);
    // revoke allowance for the current strategy
    address _currStrategy = strategy;
    _token.safeApprove(_currStrategy, 0);
    IERC20Detailed(strategyToken).safeApprove(_currStrategy, 0);
    // Updated strategy variables
    strategy = _strategy;
    // Update incentive tokens
    incentiveTokens = _incentiveTokens;
    // Update strategyToken
    address _newStrategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    strategyToken = _newStrategyToken;
    // Approve underlyingToken
    _token.safeIncreaseAllowance(_strategy, type(uint256).max);
    // Approve the new strategy to transfer strategyToken out from this contract
    IERC20Detailed(_newStrategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);
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

  /// @param _unlentPerc new unlent percentage
  function setUnlentPerc(uint256 _unlentPerc) external onlyOwner {
    require((unlentPerc = _unlentPerc) <= FULL_ALLOC, 'IDLE:TOO_HIGH');
  }

  /// @param _idealRange new ideal range
  function setIdealRange(uint256 _idealRange) external onlyOwner {
    require((idealRange = _idealRange) <= FULL_ALLOC, 'IDLE:TOO_HIGH');
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
    address[] memory _incentiveTokens = incentiveTokens;
    address _currAAStaking = AAStaking;
    address _currBBStaking = BBStaking;

    // Remove allowance for current contracts
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      IERC20Detailed _incentiveToken = IERC20Detailed(_incentiveTokens[i]);
      if (_currAAStaking != address(0)) {
        _incentiveToken.safeApprove(_currAAStaking, 0);
      }
      if (_currAAStaking != address(0)) {
        _incentiveToken.safeApprove(_currBBStaking, 0);
      }
    }

    // Update staking contract addresses
    AAStaking = _AAStaking;
    BBStaking = _BBStaking;

    // Increase allowance for new contracts
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      IERC20Detailed _incentiveToken = IERC20Detailed(_incentiveTokens[i]);
      // Approve each staking contract to spend each incentiveToken on beahlf of this contract
      _incentiveToken.safeIncreaseAllowance(_AAStaking, type(uint256).max);
      _incentiveToken.safeIncreaseAllowance(_BBStaking, type(uint256).max);
    }
  }

  /// @notice pause deposits and redeems for all classes of tranches
  /// @dev can be called by both the owner and the guardian
  function emergencyShutdown() external {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
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
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _pause();
  }

  /// @notice Unpauses deposits and redeems
  /// @dev can be called by both the owner and the guardian
  function unpause() external {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
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

  /// @dev Set last caller and block.number hash. This should be called at the beginning of the first function to protect
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  /// @dev Check that the second function is not called in the same tx from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "SAME_BLOCK");
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
