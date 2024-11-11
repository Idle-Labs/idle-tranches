// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";

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
  // 9 = Invalid

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
  function initialize(
    uint256 _limit, 
    address _guardedToken, 
    address _governanceFund, 
    address _owner, // GuardedLaunch args
    address _rebalancer,
    address _strategy,
    uint256 _trancheAPRSplitRatio // for AA tranches, so eg 10000 means 10% interest to AA and 90% BB
  ) external initializer {
    require(token == address(0), '1');
    require(_rebalancer != address(0), '0');
    require(_strategy != address(0), '0');
    require(_guardedToken != address(0), '0');
    require( _trancheAPRSplitRatio <= FULL_ALLOC, '7');
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
    uint256 _oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    oneToken = _oneToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // incentiveTokens = _incentiveTokens; [DEPRECATED]
    priceAA = _oneToken;
    priceBB = _oneToken;
    unlentPerc = 2000; // 2%
    // # blocks, after an harvest, during which harvested rewards gets progressively unlocked
    releaseBlocksPeriod = 6400; // about 1 day
    // Set flags
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;
    // skipDefaultCheck = false is the default value
    // Set allowance for strategy
    _allowUnlimitedSpend(_guardedToken, _strategy);
    _allowUnlimitedSpend(_strategyToken, _strategy);
    // Save current strategy price
    lastStrategyPrice = _strategyPrice();
    // Fee params
    fee = 15000; // 15% performance fee
    feeReceiver = address(0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814); // treasury multisig
    guardian = _owner;
    // feeSplit = 0; // default all to feeReceiver
    isAYSActive = true; // adaptive yield split
    minAprSplitAYS = AA_RATIO_LIM_DOWN; // AA tranche will get min 50% of the yield

    maxDecreaseDefault = 5000; // 5% decrease for triggering a default
    _additionalInit();
  }

  /// @notice used by child contracts (cdo variants) if anything needs to be done on/after init
  function _additionalInit() internal virtual {}

  // ###############
  // Public methods
  // ###############

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return AA tranche tokens minted
  function depositAA(uint256 _amount) external returns (uint256) {
    return _deposit(_amount, AATranche, address(0));
  }

  /// @notice pausable in _deposit
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return BB tranche tokens minted
  function depositBB(uint256 _amount) external returns (uint256) {
    return _deposit(_amount, BBTranche, address(0));
  }

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @param _referral address of the referral
  /// @return AA tranche tokens minted
  function depositAARef(uint256 _amount, address _referral) external virtual returns (uint256) {
    return _deposit(_amount, AATranche, _referral);
  }

  /// @notice pausable in _deposit
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @param _referral address of the referral
  /// @return BB tranche tokens minted
  function depositBBRef(uint256 _amount, address _referral) external virtual returns (uint256) {
    return _deposit(_amount, BBTranche, _referral);
  }

  /// @notice pausable in _deposit
  /// @param _amount amount of AA tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawAA(uint256 _amount) external virtual returns (uint256) {
    require(!paused() || allowAAWithdraw, '3');
    return _withdraw(_amount, AATranche);
  }

  /// @notice pausable
  /// @param _amount amount of BB tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawBB(uint256 _amount) external virtual returns (uint256) {
    require(!paused() || allowBBWithdraw, '3');
    return _withdraw(_amount, BBTranche);
  }

  // ###############
  // Views
  // ###############

  /// @param _tranche tranche address
  /// @return tranche price, in underlyings, at the last interaction (not considering interest earned 
  /// since last interaction)
  function tranchePrice(address _tranche) external view returns (uint256) {
    return _tranchePrice(_tranche);
  }

  /// @notice calculates the current net TVL (in `token` terms)
  /// @dev unclaimed rewards (gov tokens) and `unclaimedFees` are not counted. 
  /// Harvested rewards are counted only if enough blocks have passed (`_lockedRewards`)
  function getContractValue() public override view returns (uint256) {
    address _strategyToken = strategyToken;
    uint256 strategyTokenDecimals = IERC20Detailed(_strategyToken).decimals();
    // TVL is the sum of unlent balance in the contract + the balance in lending - harvested but locked rewards - unclaimedFees
    // Balance in lending is the value of the interest bearing assets (strategyTokens) in this contract
    // TVL = (strategyTokens * strategy token price) + unlent balance - lockedRewards - unclaimedFees
    return (_contractTokenBalance(_strategyToken) * _strategyPrice() / (10**(strategyTokenDecimals))) +
            _contractTokenBalance(token) -
            _lockedRewards() -
            unclaimedFees;
  }

  /// @param _tranche tranche address
  /// @return actual apr given current ratio between AA and BB tranches
  function getApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, _getAARatio(false));
  }

  /// @notice calculates the current AA tranches ratio
  /// @dev _virtualBalance is used to have a more accurate/recent value for the AA ratio
  /// because it calculates the balance after splitting the accrued interest since the
  /// last depositXX/withdrawXX/harvest
  /// @return AA tranches ratio (in underlying value) considering all interest
  function getCurrentAARatio() external view returns (uint256) {
    return _getAARatio(false);
  }

  /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted
  /// ie the interest/loss generated since the last update of priceAA and priceBB (done on depositXX/withdrawXX/harvest)
  /// @param _tranche address of the requested tranche
  /// @return _virtualPrice tranche price considering all interest/losses
  function virtualPrice(address _tranche) public virtual view returns (uint256 _virtualPrice) {
    // get both NAVs, because we need the total NAV anyway
    uint256 _lastNAVAA = lastNAVAA;
    uint256 _lastNAVBB = lastNAVBB;

    (_virtualPrice, ) = _virtualPriceAux(
      _tranche,
      getContractValue(), // nav
      _lastNAVAA + _lastNAVBB, // lastNAV
      _tranche == AATranche ? _lastNAVAA : _lastNAVBB, // lastTrancheNAV
      trancheAPRSplitRatio
    );
  }

  // ###############
  // Internal
  // ###############

  /// @notice method used to check if depositor has enough stkIDLE per unit of underlying to access the vault.
  /// This can be used to give priority access to new vaults to stkIDLE holders. 
  /// @dev This check is only intended for "regular" users as it does not strictly enforce the _stkIDLEPerUnderlying 
  /// ratio (eg: deposit+transfer). This will be mitigated by the fee rebate mechanism (airdrop) as otherwise those
  /// rebates will be lost.
  /// @param _amount amount of underlying to deposit
  function _checkStkIDLEBal(address _tranche, uint256 _amount) internal view virtual {
    uint256 _stkIDLEPerUnderlying = stkIDLEPerUnderlying;
    // check if stkIDLE requirement is active for _tranche
    if (_stkIDLEPerUnderlying == 0 || 
      (_tranche == BBTranche && BBStaking == address(0)) || 
      (_tranche == AATranche && AAStaking == address(0))) {
      return;
    }

    uint256 trancheBal = IERC20Detailed(_tranche).balanceOf(msg.sender);
    // We check if sender deposited in the same tranche previously and add the bal to _amount
    uint256 bal = _amount + (trancheBal > 0 ? (trancheBal * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN) : 0);
    require(
      IERC20(STK_IDLE).balanceOf(msg.sender) >= 
      bal * _stkIDLEPerUnderlying / oneToken, 
      '7'
    );
  }

  /// @notice method used to deposit `token` and mint tranche tokens
  /// Ideally users should deposit right after an `harvest` call to maximize profit
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// automatically reverts on lending provider default (_strategyPrice decreased)
  /// @param _amount amount of underlyings (`token`) to deposit
  /// @param _tranche tranche address
  /// @param _referral referral address
  /// @return _minted number of tranche tokens minted
  function _deposit(uint256 _amount, address _tranche, address _referral) internal virtual whenNotPaused returns (uint256 _minted) {
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
    // check if depositor has enough stkIDLE for the amount to be deposited
    _checkStkIDLEBal(_tranche, _amount);
    // get underlyings from sender
    address _token = token;
    uint256 _preBal = _contractTokenBalance(_token);
    IERC20Detailed(_token).safeTransferFrom(msg.sender, address(this), _amount);
    // mint tranche tokens according to the current tranche price
    _minted = _mintShares(_contractTokenBalance(_token) - _preBal, msg.sender, _tranche);
    // update trancheAPRSplitRatio
    _updateSplitRatio(_getAARatio(true));

    if (directDeposit) {
      IIdleCDOStrategy(strategy).deposit(_amount);
    }

    if (_referral != address(0)) {
      emit Referral(_amount, _referral);
    }
  }

  /// @notice this method is called on depositXX/withdrawXX/harvest and
  /// updates the accounting of the contract and effectively splits the yield/loss between the
  /// AA and BB tranches
  /// @dev this method:
  /// - update tranche prices (priceAA and priceBB)
  /// - update net asset value for both tranches (lastNAVAA and lastNAVBB)
  /// - update fee accounting (unclaimedFees)
  function _updateAccounting() internal virtual {
    uint256 _lastNAVAA = lastNAVAA;
    uint256 _lastNAVBB = lastNAVBB;
    uint256 _lastNAV = _lastNAVAA + _lastNAVBB;
    uint256 nav = getContractValue();
    uint256 _aprSplitRatio = trancheAPRSplitRatio;
    // If gain is > 0, then collect some fees in `unclaimedFees`
    if (nav > _lastNAV) {
      unclaimedFees += (nav - _lastNAV) * fee / FULL_ALLOC;
    }
    (uint256 _priceAA, int256 _totalAAGain) = _virtualPriceAux(AATranche, nav, _lastNAV, _lastNAVAA, _aprSplitRatio);
    (uint256 _priceBB, int256 _totalBBGain) = _virtualPriceAux(BBTranche, nav, _lastNAV, _lastNAVBB, _aprSplitRatio);
    lastNAVAA = uint256(int256(_lastNAVAA) + _totalAAGain);

    // if we have a loss and it's gte last junior NAV we trigger a default
    if (_totalBBGain < 0 && -_totalBBGain >= int256(_lastNAVBB)) {
      // revert with 'default' error (4) if skipDefaultCheck is false, as seniors will have a loss too not covered. 
      // `updateAccounting` should be manually called to distribute loss
      require(skipDefaultCheck, "4");
      // This path will be called when a default happens and guardian calls
      // `updateAccounting` after setting skipDefaultCheck or when skipDefaultCheck is already set to true
      lastNAVBB = 0;
      // if skipDefaultCheck is set to true prior a default (eg because AA is used as collateral and needs to be liquid), 
      // emergencyShutdown won't prevent the current deposit/redeem (the one that called this _updateAccounting) and is 
      // still correct because:
      // - depositBB will revert as priceBB is 0
      // - depositAA won't revert (unless the loss is 100% of TVL) and user will get 
      //   correct number of share at a priceAA already post junior default
      // - withdrawBB will redeem 0 and burn BB tokens because priceBB is 0
      // - withdrawAA will redeem the correct amount of underlyings post junior default
      // We pass true as we still want AA to be redeemable in any case even after a junior default
      _emergencyShutdown(true);
    } else {
      // we add the gain to last saved NAV
      lastNAVBB = uint256(int256(_lastNAVBB) + _totalBBGain);
    }
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

  /// @notice calculates the NAV for a tranche without considering the interest that is yet to be splitted
  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche
  function _instantBalance(address _tranche) internal view returns (uint256) {
    return IdleCDOTranche(_tranche).totalSupply() * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted and the
  /// total gain/loss for a specific tranche
  /// @dev Main scenarios covered:
  /// - if there is a loss on the lending protocol (ie strategy price decrease) up to maxDecreaseDefault (_checkDefault method), the loss is
  ///     - totally absorbed by junior holders if they have enough TVL and deposits/redeems work as normal
  ///     - otherwise a 'default' error (4) is raised and deposits/redeems are blocked
  /// - if there is a loss on the lending protocol (ie strategy price decrease) more than maxDecreaseDefault all deposits and redeems
  ///   are blocked and a 'default' error (4) is raised
  /// - if there is a loss somewhere not in the lending protocol (ie in our contracts) and the TVL decreases then the same process as above
  ///   applies, the only difference is that maxDecreaseDefault is not considered
  /// In any case, once a loss happens, it only gets accounted when new deposits/redeems are made, but those are blocked.
  /// For this reason a protected updateAccounting method has been added which should be used to distributed the loss after a default event
  /// @param _tranche address of the requested tranche
  /// @param _nav current NAV
  /// @param _lastNAV last saved NAV
  /// @param _lastTrancheNAV last saved tranche NAV
  /// @param _trancheAPRSplitRatio APR split ratio for AA tranche
  /// @return _virtualPrice tranche price considering all interest
  /// @return _totalTrancheGain (int256) tranche gain/loss since last update
  function _virtualPriceAux(
    address _tranche,
    uint256 _nav,
    uint256 _lastNAV,
    uint256 _lastTrancheNAV,
    uint256 _trancheAPRSplitRatio
  ) internal virtual view returns (uint256 _virtualPrice, int256 _totalTrancheGain) {
    // Check if there are tranche holders
    uint256 trancheSupply = IdleCDOTranche(_tranche).totalSupply();
    if (_lastNAV == 0 || trancheSupply == 0) {
      return (oneToken, 0);
    }

    // In order to correctly split the interest generated between AA and BB tranche holders
    // (according to the trancheAPRSplitRatio) we need to know how much interest/loss we gained
    // since the last price update (during a depositXX/withdrawXX/harvest)
    // To do that we need to get the current value of the assets in this contract
    // and the last saved one (always during a depositXX/withdrawXX/harvest)
    // Calculate the total gain/loss
    int256 totalGain = int256(_nav) - int256(_lastNAV);
    // If there is no gain/loss return the current price
    if (totalGain == 0) {
      return (_tranchePrice(_tranche), 0);
    }

    // Remove performance fee for gains
    if (totalGain > 0) {
      totalGain -= totalGain * int256(fee) / int256(FULL_ALLOC);
    }

    address _AATranche = AATranche;
    address _BBTranche = BBTranche;
    bool _isAATranche = _tranche == _AATranche;
    // Get the supply of the other tranche and
    // if it's 0 then give all gain to the current `_tranche` holders
    if (IdleCDOTranche(_isAATranche ? _BBTranche : _AATranche).totalSupply() == 0) {
      _totalTrancheGain = totalGain;
    } else {
      // if we gained something or the loss is between 0 and lossToleranceBps then we socialize the gain/loss
      if (totalGain > 0) {
        // Split the net gain, according to _trancheAPRSplitRatio, with precision loss favoring the AA tranche.
        int256 totalBBGain = totalGain * int256(FULL_ALLOC - _trancheAPRSplitRatio) / int256(FULL_ALLOC);
        // The new NAV for the tranche is old NAV + total gain for the tranche
        _totalTrancheGain = _isAATranche ? (totalGain - totalBBGain) : totalBBGain;
      } else if (uint256(-totalGain) <= (lossToleranceBps * _lastNAV) / FULL_ALLOC) {
        // Split the loss, according to TVL ratio instead of _trancheAPRSplitRatio (loss socialized between all tranches)
        uint256 _lastNAVBB = lastNAVBB;
        int256 totalBBLoss = totalGain * int256(_lastNAVBB) / int256(lastNAVAA + _lastNAVBB);
        // The new NAV for the tranche is old NAV - loss for the tranche
        _totalTrancheGain = _isAATranche ? (totalGain - totalBBLoss) : totalBBLoss;
      } else { // totalGain is negative here
        // Redirect the whole loss (which should be < maxDecreaseDefault) to junior holders
        int256 _juniorTVL = int256(_isAATranche ? _lastNAV - _lastTrancheNAV : _lastTrancheNAV);
        int256 _newJuniorTVL = _juniorTVL + totalGain; 
        // if junior holders have enough TVL to cover
        if (_newJuniorTVL > 0) {
          // then juniors get all loss (totalGain) and senior gets 0 loss
          _totalTrancheGain = _isAATranche ? int256(0) : totalGain;
        } else {
          // otherwise all loss minus junior tvl to senior
          if (!_isAATranche) {
            // juniors have no more claims, price is set to 0, gain is set to -juniorTVL
            return (0, -_juniorTVL);
          }
          // seniors get the loss - old junior TVL
          _totalTrancheGain = _newJuniorTVL;
        }
      }
    }
    // Split the new NAV (_lastTrancheNAV + _totalTrancheGain) per tranche token
    _virtualPrice = uint256(int256(_lastTrancheNAV) + _totalTrancheGain) * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @notice mint tranche tokens and updates tranche last NAV
  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _mintShares(uint256 _amount, address _to, address _tranche) internal virtual returns (uint256 _minted) {
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

  /// @notice convert fees (`unclaimedFees`) in AA tranche tokens
  /// @dev this will be called only during harvests
  function _depositFees() internal virtual {
    uint256 _amount = unclaimedFees;
    if (_amount != 0) {
      // mint tranches tokens (always AA) to this contract
      _mintShares(_amount, feeReceiver, AATranche);
      // reset unclaimedFees counter
      unclaimedFees = 0;
      // update trancheAPRSplitRatio using instant balance
      _updateSplitRatio(_getAARatio(true));
    }
  }

  /// @notice It allows users to burn their tranche token and redeem their principal + interest back
  /// @dev automatically reverts on lending provider default (_strategyPrice decreased).
  /// @param _amount in tranche tokens
  /// @param _tranche tranche address
  /// @return toRedeem number of underlyings redeemed
  function _withdraw(uint256 _amount, address _tranche) virtual internal nonReentrant returns (uint256 toRedeem) {
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
    require(_amount != 0, '0');
    address _token = token;
    // get current available unlent balance
    uint256 balanceUnderlying = _contractTokenBalance(_token);
    // Calculate the amount to redeem
    toRedeem = _amount * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
    uint256 _want = toRedeem;
    if (toRedeem > balanceUnderlying) {
      // if the unlent balance is not enough we try to redeem what's missing directly from the strategy
      // and then add it to the current unlent balance
      // NOTE: A difference of up to 100 wei due to rounding is tolerated
      toRedeem = _liquidate(toRedeem - balanceUnderlying, revertIfTooLow) + balanceUnderlying;
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= _want;
    } else {
      lastNAVBB -= _want;
    }

    // update trancheAPRSplitRatio
    _updateSplitRatio(_getAARatio(true));
  
    // send underlying to msg.sender. Keep this at the end of the function to avoid 
    // potential read only reentrancy on cdo variants that have hooks (eg with nfts)
    IERC20Detailed(_token).safeTransfer(msg.sender, toRedeem);
  }

  /// @notice updates trancheAPRSplitRatio based on the current tranches TVL ratio between AA and BB
  /// @dev the idea here is to limit the min and max APR that the senior tranche can get
  function _updateSplitRatio(uint256 tvlAARatio) internal virtual {
    uint256 _minSplit = minAprSplitAYS;
    _minSplit = _minSplit == 0 ? AA_RATIO_LIM_DOWN : _minSplit;

    if (isAYSActive) {
      uint256 aux;
      if (tvlAARatio >= AA_RATIO_LIM_UP) {
        aux = tvlAARatio == FULL_ALLOC ? FULL_ALLOC : AA_RATIO_LIM_UP;
      } else if (tvlAARatio > _minSplit) {
        aux = tvlAARatio;
      } else {
        aux = _minSplit;
      }
      trancheAPRSplitRatio = aux * tvlAARatio / FULL_ALLOC;
    }
  }

  /// @notice calculates the current AA tranches ratio
  /// @dev it does count accrued interest not yet split since last
  /// depositXX/withdrawXX/harvest only if _instant flag is true
  /// @param _instant if true, it returns the current ratio without accrued interest
  /// @return AA tranches ratio (in underlying value) considering all interest
  function _getAARatio(bool _instant) internal view returns (uint256) {
    function(address) internal view returns (uint256) _getNAV =
      _instant ? _instantBalance : _virtualBalance;
    uint256 AABal = _getNAV(AATranche);
    uint256 contractVal = AABal + _getNAV(BBTranche);
    if (contractVal == 0) {
      return 0;
    }
    // Current AA tranche split ratio = AABal * FULL_ALLOC / (AABal + BBBal)
    return AABal * FULL_ALLOC / contractVal;
  }

  /// @dev check if _strategyPrice is decreased more than X% with X configurable since last update 
  /// and updates last saved strategy price
  function _checkDefault() virtual internal {
    uint256 currPrice = _strategyPrice();
    if (!skipDefaultCheck) {
      // calculate if % of decrease of strategyPrice is within maxDecreaseDefault
      require(lastStrategyPrice * (FULL_ALLOC - maxDecreaseDefault) / FULL_ALLOC <= currPrice, "4");
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
  function _liquidate(uint256 _amount, bool _revertIfNeeded) internal virtual returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (_revertIfNeeded) {
      uint256 _tolerance = liquidationTolerance;
      if (_tolerance == 0) {
        _tolerance = 100;
      }
      // keep `_tolerance` wei as margin for rounding errors
      require(_redeemedTokens + _tolerance >= _amount, '5');
    }

    if (_redeemedTokens > _amount) {
      _redeemedTokens = _amount;
    }
  }

  /// @notice method used to sell `_rewardToken` for `_token` on uniswap
  /// @param _rewardToken address of the token to sell
  /// @param _path to buy
  /// @param _amount of `_rewardToken` to sell
  /// @param _minAmount min amount of `_token` to buy
  /// @return _amount of _rewardToken sold
  /// @return _amount received for the sell
  function _sellReward(address _rewardToken, bytes memory _path, uint256 _amount, uint256 _minAmount)
    internal virtual
    returns (uint256, uint256) {
    // If 0 is passed as sell amount, we get the whole contract balance
    if (_amount == 0) {
      _amount = _contractTokenBalance(_rewardToken);
    }
    if (_amount == 0) {
      return (0, 0);
    }
  
    if (_path.length != 0) {
      // Uni v3 swap
      ISwapRouter _swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
      IERC20Detailed(_rewardToken).safeIncreaseAllowance(address(_swapRouter), _amount);
      // multi hop swap params
      ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
        path: _path,
        recipient: address(this),
        deadline: block.timestamp + 100,
        amountIn: _amount,
        amountOutMinimum: _minAmount
      });
      // do the swap and return the amount swapped and the amount received
      return (_amount, _swapRouter.exactInput(params));
    } else {
      // Uni v2 swap
      IUniswapV2Router02 _uniRouter = uniswapRouterV2;
      // approve the uniswap router to spend our reward
      IERC20Detailed(_rewardToken).safeIncreaseAllowance(address(_uniRouter), _amount);
      // do the trade with all `_rewardToken` in this contract
      address[] memory _pathUniv2 = new address[](3);
      _pathUniv2[0] = _rewardToken;
      _pathUniv2[1] = weth;
      _pathUniv2[2] = token;
      uint256[] memory _amounts = _uniRouter.swapExactTokensForTokens(
        _amount,
        _minAmount,
        _pathUniv2,
        address(this),
        block.timestamp + 100
      );
      // return the amount swapped and the amount received
      return (_amounts[0], _amounts[_amounts.length - 1]);
    }
  }

  /// @notice method used to sell all sellable rewards for `_token` on uniswap
  /// @param _strategy IIdleCDOStrategy stategy instance
  /// @param _sellAmounts array with amounts of rewards to sell
  /// @param _minAmount array with amounts of _token buy for each reward sold. (should have the same length as _sellAmounts)
  /// @param _skipReward array of flags for skipping the market sell of specific rewards (should have the same length as _sellAmounts)
  /// @return _soldAmounts array with amounts of rewards actually sold
  /// @return _swappedAmounts array with amounts of _token actually bought
  /// @return _totSold total rewards sold in `_token`
  function _sellAllRewards(IIdleCDOStrategy _strategy, uint256[] memory _sellAmounts, uint256[] memory _minAmount, bool[] memory _skipReward, bytes memory _extraData)
    internal virtual
    returns (uint256[] memory _soldAmounts, uint256[] memory _swappedAmounts, uint256 _totSold) {
    // Fetch state variables once to save gas
    // get all rewards addresses
    address[] memory _rewards = _strategy.getRewardTokens();
    address _rewardToken;
    bytes[] memory _paths = new bytes[](_rewards.length);
    if (_extraData.length > 0) {
      _paths = abi.decode(_extraData, (bytes[]));
    }
    uint256 rewardsLen = _rewards.length;
    // Initialize the return array, containing the amounts received after swapping reward tokens
    _soldAmounts = new uint256[](rewardsLen);
    _swappedAmounts = new uint256[](rewardsLen);
    // loop through all reward tokens
    for (uint256 i; i < rewardsLen; ++i) {
      _rewardToken = _rewards[i];
      // check if it should be sold or not
      if (_skipReward[i]) { continue; }
      // do not sell stkAAVE but only AAVE if present
      if (_rewardToken == stkAave) {
        _rewardToken = AAVE;
      }
      // Market sell _rewardToken in this contract for _token
      (_soldAmounts[i], _swappedAmounts[i]) = _sellReward(_rewardToken, _paths[i], _sellAmounts[i], _minAmount[i]);
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
  function _lockedRewards() internal view virtual returns (uint256 _locked) {
    uint256 _releaseBlocksPeriod = releaseBlocksPeriod;
    uint256 _blocksSinceLastHarvest = block.number - latestHarvestBlock;
    uint256 _harvestedRewards = harvestedRewards;

    // NOTE: _harvestedRewards is never set to 0, but rather to 1 to save some gas
    if (_harvestedRewards > 1 && _blocksSinceLastHarvest < _releaseBlocksPeriod) {
      // progressively release harvested rewards
      _locked = _harvestedRewards * (_releaseBlocksPeriod - _blocksSinceLastHarvest) / _releaseBlocksPeriod;
    }
  }

  // ###################
  // Protected
  // ###################

  /// @notice This method is used to lend user funds in the lending provider through an IIdleCDOStrategy
  /// The method:
  /// - redeems rewards (if any) from the lending provider
  /// - converts the rewards in underlyings through uniswap v2 or v3
  /// - calls _updateAccounting to update the accounting of the system with the new underlyings received
  /// - it then convert fees in tranche tokens
  /// - finally it deposits the (initial unlent balance + the underlyings get from uniswap - fees) in the
  ///   lending provider through the IIdleCDOStrategy `deposit` call
  /// The method will be called by an external, whitelisted, keeper bot which will call the method sistematically (eg once a day)
  /// @dev can be called only by the rebalancer or the owner
  /// @param _skipFlags array of flags, [0] = skip reward redemption, [1] = skip incentives update, [2] = skip fee deposit, [3] = skip all
  /// @param _skipReward array of flags for skipping the market sell of specific rewards. Length should be equal to the `IIdleCDOStrategy(strategy).getRewardTokens()` array
  /// @param _minAmount array of min amounts for uniswap trades. Lenght should be equal to the _skipReward array
  /// @param _sellAmounts array of amounts (of reward tokens) to sell on uniswap. Lenght should be equal to the _minAmount array
  /// if a sellAmount is 0 the whole contract balance for that token is swapped
  /// @param _extraData bytes to be passed to the redeemRewards call
  /// @return _res array of arrays with the following elements:
  ///   [0] _soldAmounts array with amounts of rewards actually sold
  ///   [1] _swappedAmounts array with amounts of _token actually bought
  ///   [2] _redeemedRewards array with amounts of rewards redeemed
  function harvest(
    // _skipFlags[0] _skipRedeem,
    // _skipFlags[1] _skipIncentivesUpdate, [DEPRECATED]
    // _skipFlags[2] _skipFeeDeposit,
    // _skipFlags[3] _skipRedeem && _skipIncentivesUpdate && _skipFeeDeposit,
    bool[] calldata _skipFlags,
    bool[] calldata _skipReward,
    uint256[] calldata _minAmount,
    uint256[] calldata _sellAmounts,
    bytes[] calldata _extraData
  ) public
    virtual
    returns (uint256[][] memory _res) {
    _checkOnlyOwnerOrRebalancer();
    // initalize the returned array (elements will be [_soldAmounts, _swappedAmounts, _redeemedRewards])
    _res = new uint256[][](3);
    // Fetch state variable once to save gas
    IIdleCDOStrategy _strategy = IIdleCDOStrategy(strategy);
    // Check whether to redeem rewards from strategy or not
    if (!_skipFlags[3]) {
      uint256 _totSold;

      if (!_skipFlags[0]) {
        // Redeem all rewards associated with the strategy
        _res[2] = _strategy.redeemRewards(_extraData[0]);
        // Sell rewards
        (_res[0], _res[1], _totSold) = _sellAllRewards(_strategy, _sellAmounts, _minAmount, _skipReward, _extraData[1]);
      }
      // update last saved harvest block number
      latestHarvestBlock = block.number;
      // update harvested rewards value (avoid setting it to 0 to save some gas)
      harvestedRewards = _totSold == 0 ? 1 : _totSold;

      // split converted rewards if any and update tranche prices
      // NOTE: harvested rewards won't be counted directly but released over time
      _updateAccounting();

      if (!_skipFlags[2]) {
        // Get fees in the form of totalSupply diluition
        _depositFees();
      }
    }

    // Deposit the remaining balance in the lending provider and 
    // keep some unlent balance for cheap redeems and as reserve of last resort
    uint256 underlyingBal = _contractTokenBalance(token);
    uint256 idealUnlent = getContractValue() * unlentPerc / FULL_ALLOC;
    if (underlyingBal > idealUnlent) {
      // Put unlent balance at work in the lending provider
      _strategy.deposit(underlyingBal - idealUnlent);
    }
  }

  /// @notice method used to redeem underlyings from the lending provider
  /// @dev can be called only by the rebalancer or the owner
  /// @param _amount in underlyings to liquidate from lending provider
  /// @param _revertIfNeeded flag to revert if amount liquidated is too low
  /// @return liquidated amount in underlyings
  function liquidate(uint256 _amount, bool _revertIfNeeded) external virtual returns (uint256) {
    _checkOnlyOwnerOrRebalancer();
    return _liquidate(_amount, _revertIfNeeded);
  }

  // ###################
  // onlyOwner
  // ###################

  /// @dev automatically reverts if strategyPrice decreased more than `_maxDecreaseDefault`
  /// @param _maxDecreaseDefault max value, in % where `100000` = 100%, of accettable price decrease for the strategy
  function setMaxDecreaseDefault(uint256 _maxDecreaseDefault) external virtual {
    _checkOnlyOwner();
    require(_maxDecreaseDefault < FULL_ALLOC, '7');
    maxDecreaseDefault = _maxDecreaseDefault;
  }

  /// @param _active flag to allow Adaptive Yield Split
  function setIsAYSActive(bool _active) external {
    _checkOnlyOwner();
    isAYSActive = _active;
  }

  /// @param _allowed flag to allow AA withdraws
  function setAllowAAWithdraw(bool _allowed) external virtual {
    _checkOnlyOwner();
    allowAAWithdraw = _allowed;
  }

  /// @param _allowed flag to allow BB withdraws
  function setAllowBBWithdraw(bool _allowed) external virtual {
    _checkOnlyOwner();
    allowBBWithdraw = _allowed;
  }

  /// @param _allowed flag to enable the 'default' check (whether _strategyPrice decreased or not)
  function setSkipDefaultCheck(bool _allowed) external virtual {
    _checkOnlyOwner();
    skipDefaultCheck = _allowed;
  }

  /// @param _allowed flag to enable the check if redeemed amount during liquidations is enough
  function setRevertIfTooLow(bool _allowed) external virtual {
    _checkOnlyOwner();
    revertIfTooLow = _allowed;
  }

  /// @param _rebalancer new rebalancer address
  function setRebalancer(address _rebalancer) external {
    _checkOnlyOwner();
    require((rebalancer = _rebalancer) != address(0), '0');
  }

  /// @param _feeReceiver new fee receiver address
  function setFeeReceiver(address _feeReceiver) external {
    _checkOnlyOwner();
    require((feeReceiver = _feeReceiver) != address(0), '0');
  }

  /// @param _guardian new guardian (pauser) address
  function setGuardian(address _guardian) external {
    _checkOnlyOwner();
    require((guardian = _guardian) != address(0), '0');
  }

  /// @param _diff max liquidation diff tolerance in underlyings
  function setLiquidationTolerance(uint256 _diff) external virtual {
    _checkOnlyOwner();
    liquidationTolerance = _diff;
  }

  /// @param _val stkIDLE per underlying required for deposits
  function setStkIDLEPerUnderlying(uint256 _val) external virtual {
    _checkOnlyOwner();
    stkIDLEPerUnderlying = _val;
  }

  /// @param _aprSplit min apr split for AA, considering FULL_ALLOC = 100%
  function setMinAprSplitAYS(uint256 _aprSplit) external {
    _checkOnlyOwner();
    require((minAprSplitAYS = _aprSplit) <= FULL_ALLOC, '7');
    minAprSplitAYS = _aprSplit;
  }

  /// @param _fee new fee
  function setFee(uint256 _fee) external {
    _checkOnlyOwner();
    require((fee = _fee) <= MAX_FEE, '7');
  }

  /// @param _unlentPerc new unlent percentage
  function setUnlentPerc(uint256 _unlentPerc) external virtual {
    _checkOnlyOwner();
    require((unlentPerc = _unlentPerc) <= FULL_ALLOC, '7');
  }

  /// @notice set new release block period. WARN: this should be called only when there 
  /// are no active rewards being unlocked
  /// @param _releaseBlocksPeriod new # of blocks after an harvest during which
  /// harvested rewards gets progressively redistriburted to users
  function setReleaseBlocksPeriod(uint256 _releaseBlocksPeriod) external virtual {
    _checkOnlyOwner();
    releaseBlocksPeriod = _releaseBlocksPeriod;
  }

  /// @param _trancheAPRSplitRatio new apr split ratio
  function setTrancheAPRSplitRatio(uint256 _trancheAPRSplitRatio) external virtual {
    _checkOnlyOwner();
    require((trancheAPRSplitRatio = _trancheAPRSplitRatio) <= FULL_ALLOC, '7');
  }

  /// @param _diffBps tolerance in % (FULL_ALLOC = 100%) for socializing small losses 
  function setLossToleranceBps(uint256 _diffBps) external {
    _checkOnlyOwner();
    lossToleranceBps = _diffBps;
  }

  /// @dev toggle stkIDLE requirement for tranche
  /// @param _tranche address
  function toggleStkIDLEForTranche(address _tranche) external virtual {
    _checkOnlyOwner();
    address aa = AATranche;
    require(_tranche == BBTranche || _tranche == aa, '9');
    if (_tranche == aa) {
      AAStaking = AAStaking == address(0) ? address(1) : address(0);
      return;
    }

    BBStaking = BBStaking == address(0) ? address(1) : address(0);
  }

  /// @notice this method updates the accounting of the contract and effectively splits the yield/loss between the
  /// AA and BB tranches. This can be called at any time as is called automatically on each deposit/redeem. It's here
  /// just to be called when a default happened, as deposits/redeems are paused, but we need to update
  /// the loss for junior holders
  function updateAccounting() external {
    _checkOnlyOwnerOrGuardian();
    skipDefaultCheck = true;
    _updateAccounting();
    // _updateAccounting can set `skipDefaultCheck` to true in case of default
    // but this can be manually be reset to true if needed
    skipDefaultCheck = false;
  }

  /// @notice pause deposits and redeems for all classes of tranches
  /// @dev can be called by both the owner and the guardian
  function emergencyShutdown() external {
    _checkOnlyOwnerOrGuardian();
    _emergencyShutdown(false);
  }

  function _emergencyShutdown(bool isAAWithdrawAllowed) internal virtual {
    // prevent deposits
    if (!paused()) {
      _pause();
    }
    // prevent withdraws
    allowAAWithdraw = isAAWithdrawAllowed;
    allowBBWithdraw = false;
    // Allow deposits/withdraws (once selectively re-enabled, eg for AA holders)
    // without checking for lending protocol default
    skipDefaultCheck = true;
    revertIfTooLow = true;
  }

  /// @notice allow deposits and redeems for all classes of tranches
  /// @dev can be called by the owner only
  function restoreOperations() external virtual {
    _checkOnlyOwner();
    // restore deposits
    if (paused()) {
      _unpause();
    }
    // restore withdraws
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    // Allow deposits/withdraws but checks for lending protocol default
    skipDefaultCheck = false;
    revertIfTooLow = true;
  }

  /// @notice Pauses deposits
  /// @dev can be called by both the owner and the guardian
  function pause() external  {
    _checkOnlyOwnerOrGuardian();
    _pause();
  }

  /// @notice Unpauses deposits
  /// @dev can be called by both the owner and the guardian
  function unpause() external {
    _checkOnlyOwnerOrGuardian();
    _unpause();
  }

  // ###################
  // Helpers
  // ###################

  /// @dev Check that the msg.sender is the either the owner or the guardian
  function _checkOnlyOwnerOrGuardian() internal view {
    require(msg.sender == guardian || msg.sender == owner(), "6");
  }

  /// @dev Check that the msg.sender is the either the owner or the rebalancer
  function _checkOnlyOwnerOrRebalancer() internal view {
    require(msg.sender == rebalancer || msg.sender == owner(), "6");
  }

  /// @notice returns the current balance of this contract for a specific token
  /// @param _token token address
  /// @return balance of `_token` for this contract
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
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

  /// @notice concat 2 strings in a single one
  /// @param a first string
  /// @param b second string
  /// @return new string with a and b concatenated
  function _concat(string memory a, string memory b) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b));
  }
}