// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";

import "./GuardedLaunchUpgradable.sol";
import "./IdleCDOTranche.sol";
import "./IdleCDOStorage.sol";

/// @title IdleCDO fork for credit vaults
/// @author Idle Labs Inc.
/// @notice Credit vault specific CDO runtime without legacy tranche/reward methods.
/// @dev Storage layout intentionally matches IdleCDO so existing epoch-vault proxies can upgrade safely.
contract IdleCDOCreditVault is PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  // ERROR MESSAGES:
  error AlreadyInitialized();
  error Default();
  error AmountTooHigh();

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
  /// @param _strategy strategy address
  /// @param _trancheAPRSplitRatio trancheAPRSplitRatio value
  function initialize(
    uint256 _limit, 
    address _guardedToken, 
    address _governanceFund, 
    address _owner, // GuardedLaunch args
    address,
    address _strategy,
    uint256 _trancheAPRSplitRatio// for AA tranches, so eg 10000 means 10% interest to AA and 90% BB
  ) external virtual initializer {
    if (token != address(0)) revert AlreadyInitialized();
    _checkIs0(_strategy == address(0) || _guardedToken == address(0));
    _checkAmountTooHigh(_trancheAPRSplitRatio > FULL_ALLOC);
    // Initialize contracts
    PausableUpgradeable.__Pausable_init();
    // check for _governanceFund and _owner != address(0) are inside GuardedLaunchUpgradable
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _governanceFund, _owner);
    // Deploy Tranches tokens
    address _strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    // get strategy token symbol (eg. idleDAI)
    string memory _symbol = IERC20Detailed(_strategyToken).symbol();
    // create tranche tokens (concat strategy token symbol in the name and symbol of the tranche tokens)
    AATranche = _deployTranche(string("Pareto "), string("p"), _symbol);
    BBTranche = _deployTranche(string("Pareto BB "), string("pBB_"), _symbol);
    // Set CDO params
    token = _guardedToken;
    strategy = _strategy;
    strategyToken = _strategyToken;
    trancheAPRSplitRatio = _trancheAPRSplitRatio;
    uint256 _oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    oneToken = _oneToken;
    priceAA = _oneToken;
    priceBB = _oneToken;
    // skipDefaultCheck = false is the default value
    // Set allowance for strategy
    _allowUnlimitedSpend(_guardedToken, _strategy);
    _allowUnlimitedSpend(_strategyToken, _strategy);
    guardian = _owner;
    isAYSActive = true; // adaptive yield split
    minAprSplitAYS = AA_RATIO_LIM_DOWN; // AA tranche will get min 50% of the yield
    // Credit vaults reuse this legacy slot as the management-fee checkpoint timestamp.
    latestHarvestBlock = block.timestamp;
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
    return _deposit(_amount, AATranche);
  }

  /// @notice pausable in _deposit
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return BB tranche tokens minted
  function depositBB(uint256 _amount) external returns (uint256) {
    return _deposit(_amount, BBTranche);
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
  /// @dev `unclaimedFees` are not counted.
  function getContractValue() public override view returns (uint256) {
    // Credit vault strategy tokens are minted 1:1 with underlyings and use the same decimals.
    return _contractTokenBalance(strategyToken) + _contractTokenBalance(token) - unclaimedFees;
  }

  /// @notice Calculates the current managed net TVL.
  /// @dev Raw underlyings held by the CDO are excluded because unsolicited transfers are skimmed on interactions.
  /// @return Strategy-token-backed TVL net of accrued fees.
  function _managedContractValue() internal virtual view returns (uint256) {
    uint256 strategyTokenBalance = _contractTokenBalance(strategyToken);
    uint256 fees = unclaimedFees;
    return strategyTokenBalance > fees ? strategyTokenBalance - fees : 0;
  }

  /// @param _tranche tranche address
  /// @return actual apr given current ratio between AA and BB tranches
  function getApr(address _tranche) external view returns (uint256) {
    uint256 _AATrancheSplitRatio = _getAARatio(false);
    uint256 stratApr = _getStrategyApr();
    if (_AATrancheSplitRatio == 0 || _AATrancheSplitRatio == FULL_ALLOC) {
      // with only one initialized tranche, it receives all apr and the empty tranche receives zero
      return (_tranche == AATranche) == (_AATrancheSplitRatio == 0) ? 0 : stratApr;
    }
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    if (_tranche != AATranche) {
      // BB apr is: stratApr * BBaprSplitRatio / BBSplitRatio -> where
      // BBaprSplitRatio is: (FULL_ALLOC - _trancheAPRSplitRatio) and
      // BBSplitRatio is: (FULL_ALLOC - _AATrancheSplitRatio)
      return stratApr * (FULL_ALLOC - _trancheAPRSplitRatio) / (FULL_ALLOC - _AATrancheSplitRatio);
    }
    // AA apr is: stratApr * AAaprSplitRatio / AASplitRatio
    return stratApr * _trancheAPRSplitRatio / _AATrancheSplitRatio;
  }

  /// @notice calculates the current AA tranches ratio
  /// @dev _virtualBalance is used to have a more accurate/recent value for the AA ratio
  /// because it calculates the balance after splitting the accrued interest since the
  /// last depositXX/withdrawXX
  /// @return AA tranches ratio (in underlying value) considering all interest
  function getCurrentAARatio() external view returns (uint256) {
    return _getAARatio(false);
  }

  /// @notice calculates the current tranches price considering the interest/loss that is yet to be splitted
  /// ie the interest/loss generated since the last update of priceAA and priceBB (done on depositXX/withdrawXX)
  /// @param _tranche address of the requested tranche
  /// @return _virtualPrice tranche price considering all interest/losses
  function virtualPrice(address _tranche) public virtual view returns (uint256 _virtualPrice) {
    (_virtualPrice, ) = _virtualPriceAux(
      _tranche,
      _managedContractValue(), // nav
      lastNAVAA + lastNAVBB, // lastNAV
      _lastSavedNAV(_tranche), // lastTrancheNAV
      trancheAPRSplitRatio
    );
  }

  // ###############
  // Internal
  // ###############

  /// @notice method used to deposit `token` and mint tranche tokens
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// @param _amount amount of underlyings (`token`) to deposit
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _deposit(uint256 _amount, address _tranche) internal virtual whenNotPaused returns (uint256 _minted) {
    if (_amount == 0) {
      return _minted;
    }
    // check that we are not depositing more than the contract available limit
    _guarded(_amount);
    // interest accrued since last depositXX/withdrawXX is splitted between AA and BB
    // according to trancheAPRSplitRatio. NAVs of AA and BB are updated and tranche
    // prices adjusted accordingly
    _updateAccounting();
    // get underlyings from sender
    address _token = token;
    uint256 _preBal = _contractTokenBalance(_token);
    _transferUnderlyingsFrom(msg.sender, address(this), _amount);
    // mint tranche tokens according to the current tranche price
    _minted = _mintSharesAtCurrPrice(_contractTokenBalance(_token) - _preBal, msg.sender, _tranche);
    // update trancheAPRSplitRatio
    _updateSplitRatio(_getAARatio(true));

    // direct deposit in the strategy
    IIdleCDOStrategy(strategy).deposit(_amount);
  }

  /// @notice this method is called on depositXX/withdrawXX and
  /// updates the accounting of the contract and effectively splits the yield/loss between the
  /// AA and BB tranches
  /// @dev this method:
  /// - update tranche prices (priceAA and priceBB)
  /// - update net asset value for both tranches (lastNAVAA and lastNAVBB)
  /// - update fee accounting (unclaimedFees)
  /// @return shutdown true when a loss exhausted BB or fully wiped an AA-only vault
  function _updateAccounting() internal virtual returns (bool shutdown) {
    _accrueManagementFee();
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
    lastNAVBB = uint256(int256(_lastNAVBB) + _totalBBGain);

    // Ordinary losses exhaust BB before reducing AA. Stop normal interactions once BB is wiped,
    // or when an AA-only vault is fully wiped, so the loss must be crystallized explicitly.
    if ((_totalBBGain < 0 && -_totalBBGain >= int256(_lastNAVBB)) || (_lastNAV != 0 && nav == 0)) {
      shutdown = true;
      if (!skipDefaultCheck) revert Default();
      // Keep a total wipe distinguishable from an uninitialized vault when no BB NAV existed.
      if (nav == 0) _priceAA = 0;
      _emergencyShutdown(true);
    }
    priceAA = _priceAA;
    priceBB = _priceBB;
  }

  /// @notice calculates the NAV for a tranche considering the interest that is yet to be splitted
  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche considering all nav
  function _virtualBalance(address _tranche) internal view returns (uint256) {
    // balance is: tranche supply * virtual tranche price
    return _trancheSupply(_tranche) * virtualPrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice calculates the NAV for a tranche without considering the interest that is yet to be splitted
  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche
  function _instantBalance(address _tranche) internal view returns (uint256) {
    return _trancheSupply(_tranche) * _tranchePrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @notice gets total supply for a specific tranche
  /// @param _tranche address of the requested tranche
  function _trancheSupply(address _tranche) internal view returns (uint256) {
    return IdleCDOTranche(_tranche).totalSupply();
  }

  /// @notice gets last saved NAV for a specific tranche
  /// @param _tranche address of the requested tranche
  function _lastSavedNAV(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? lastNAVAA : lastNAVBB;
  }

  /// @notice Calculates the current tranche price and gain or loss since the last accounting update.
  /// @dev Gains follow `trancheAPRSplitRatio`; ordinary losses exhaust BB before reducing AA.
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
    // A zero supply identifies a tranche that was never initialized. A non-zero supply with
    // zero NAV is an economically wiped tranche and must keep its saved zero price.
    uint256 trancheSupply = _trancheSupply(_tranche);
    if (trancheSupply == 0) return (oneToken, 0);
    if (_lastNAV == 0 && _nav == 0) return (0, 0);

    // In order to correctly split the interest generated between AA and BB tranche holders
    // (according to the trancheAPRSplitRatio) we need to know how much interest/loss we gained
    // since the last price update (during a depositXX/withdrawXX)
    // To do that we need to get the current value of the assets in this contract
    // and the last saved one (always during a depositXX/withdrawXX)
    // Calculate the total gain/loss
    int256 totalGain = int256(_nav) - int256(_lastNAV);
    // Ordinary zero-delta interactions keep their saved price for compatibility. Forced
    // accounting recomputes NAV per share, which is required after discounted mid-epoch deposits.
    if (totalGain == 0 && !skipDefaultCheck) return (_tranchePrice(_tranche), 0);

    // Remove performance fee for gains
    if (totalGain > 0) {
      totalGain -= totalGain * int256(fee) / int256(FULL_ALLOC);
    }

    bool _isAATranche = _tranche == AATranche;
    // A class with no saved NAV cannot be revived by later gains. If only this class has saved
    // NAV, it receives the full gain or loss; otherwise both classes participate.
    if (_lastTrancheNAV == 0) {
      _totalTrancheGain = 0;
    } else if (_lastNAV == _lastTrancheNAV) {
      _totalTrancheGain = totalGain;
    } else {
      if (totalGain > 0) {
        // Split the net gain, according to _trancheAPRSplitRatio, with precision loss favoring the AA tranche.
        int256 totalBBGain = totalGain * int256(FULL_ALLOC - _trancheAPRSplitRatio) / int256(FULL_ALLOC);
        // The new NAV for the tranche is old NAV + total gain for the tranche
        _totalTrancheGain = _isAATranche ? (totalGain - totalBBGain) : totalBBGain;
      } else {
        int256 maxBBLoss = -int256(lastNAVBB);
        int256 totalBBLoss = totalGain > maxBBLoss ? totalGain : maxBBLoss;
        _totalTrancheGain = _isAATranche ? totalGain - totalBBLoss : totalBBLoss;
      }
    }
    // Split the new NAV (_lastTrancheNAV + _totalTrancheGain) per tranche token
    _virtualPrice = uint256(int256(_lastTrancheNAV) + _totalTrancheGain) * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @notice mint tranche tokens at current price and updates tranche last NAV
  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _mintSharesAtCurrPrice(uint256 _amount, address _to, address _tranche) internal virtual returns (uint256 _minted) {
    // calculate # of tranche token to mint based on current tranche price: _amount / tranchePrice
    _minted = _amount * ONE_TRANCHE_TOKEN / _tranchePrice(_tranche);
    _mintShares(_tranche, _to, _minted, _amount);
  }

  /// @notice mint tranche tokens and updates tranche last NAV
  /// @param _tranche tranche address
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _shares number of tranche tokens to mint
  /// @param _underlyings amount of underlyings added to the tranche
  function _mintShares(address _tranche, address _to, uint256 _shares, uint256 _underlyings) internal {
    IdleCDOTranche(_tranche).mint(_to, _shares);
    // update NAV with the _amount of underlyings added
    if (_tranche == AATranche) {
      lastNAVAA += _underlyings;
    } else {
      lastNAVBB += _underlyings;
    }
  }

  /// @notice Burn tranche tokens and update NAV and trancheAPRSplitRatio
  /// @param _amount Amount of tranche tokens
  /// @param _underlyings Amount of underlyings
  /// @param _tranche Tranche to withdraw from
  function _withdrawOps(uint256 _amount, uint256 _underlyings, address _tranche) internal {
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= _underlyings;
    } else {
      lastNAVBB -= _underlyings;
    }

    // update trancheAPRSplitRatio
    _updateSplitRatio(_getAARatio(true));
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
  /// depositXX/withdrawXX only if _instant flag is true
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

  /// @param _tranche tranche address
  /// @return last saved tranche price, in underlyings
  function _tranchePrice(address _tranche) internal view returns (uint256) {
    if (_trancheSupply(_tranche) == 0) {
      return oneToken;
    }
    return _tranche == AATranche ? priceAA : priceBB;
  }

  /// @notice internal method used to deploy a new tranche token
  /// @param _namePrefix prefix for the name of the tranche token
  /// @param _symbolPrefix prefix for the symbol of the tranche token
  /// @param _symbol suffix for the symbol of the tranche token
  /// @return address of the newly deployed tranche token
  function _deployTranche(string memory _namePrefix, string memory _symbolPrefix, string memory _symbol) internal returns (address) {
    return address(new IdleCDOTranche(_concat(_namePrefix, _symbol), _concat(_symbolPrefix, _symbol)));
  }

  // ###################
  // onlyOwner
  // ###################

  /// @param _active flag to allow Adaptive Yield Split
  function setIsAYSActive(bool _active) external virtual {
    _checkOnlyOwner();
    isAYSActive = _active;
  }

  /// @param _feeReceiver fee receiver address. It gets the portion of fees specified by `_feeSplit`.
  /// The remaining fee portion goes to `owner()`.
  /// @dev Reverts if `_feeReceiver` is address(0). Use `_feeSplit = 0` to route all fees to `owner()`.
  /// @param _fee new performance fee value (in % with 100000 = 100%)
  /// @param _feeSplit portion of collected fees sent to `_feeReceiver` (100000 = 100%)
  /// @param _managementFee annualized management fee (in % with 100000 = 100%)
  function setFeeParams(address _feeReceiver, uint256 _fee, uint256 _feeSplit, uint256 _managementFee) external {
    _checkOnlyOwner();
    _checkAmountTooHigh(_fee > MAX_FEE || _feeSplit > FULL_ALLOC || _managementFee > MAX_FEE / 10);
    _checkIs0((feeReceiver = _feeReceiver) == address(0));

    _accrueManagementFee();
    fee = _fee;
    feeSplit = _feeSplit;
    managementFee = _managementFee;
  }

  /// @param _guardian new guardian (pauser) address
  function setGuardian(address _guardian) external {
    _checkOnlyOwner();
    _checkIs0((guardian = _guardian) == address(0));
  }

  /// @param _aprSplit min apr split for AA, considering FULL_ALLOC = 100%
  function setMinAprSplitAYS(uint256 _aprSplit) external virtual {
    _checkOnlyOwner();
    _checkAmountTooHigh((minAprSplitAYS = _aprSplit) > FULL_ALLOC);
  }

  /// @notice this method updates the accounting of the contract and effectively splits the yield/loss between the
  /// AA and BB tranches. This can be called at any time as is called automatically on each deposit/redeem. It's here
  /// just to be called when a loss exhausted BB, as deposits/redeems are paused, but we need to
  /// crystallize the BB-first loss.
  function updateAccounting() external virtual {
    _checkOnlyOwnerOrGuardian();
    _forceUpdateAccounting();
  }

  /// @notice force accounting update without reverting on default path
  function _forceUpdateAccounting() internal {
    bool wasSkippingDefaultCheck = skipDefaultCheck;
    skipDefaultCheck = true;
    // Preserve an existing emergency shutdown and any wipe reported by accounting.
    if (!_updateAccounting()) {
      skipDefaultCheck = wasSkippingDefaultCheck;
    }
  }

  /// @notice pause deposits and redeems for all classes of tranches
  /// @dev can be called by both the owner and the guardian
  function emergencyShutdown() external {
    _checkOnlyOwnerOrGuardian();
    _emergencyShutdown(false);
  }

  function _emergencyShutdown(bool) internal virtual {}

  /// @notice allow deposits and redeems for all classes of tranches
  /// @dev can be called by the owner only
  function restoreOperations() external virtual {}

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
    _beforeUnpause();
    _unpause();
  }

  /// @notice Hook executed before external unpause.
  function _beforeUnpause() internal view virtual {}

  // ###################
  // Helpers
  // ###################

  /// @dev Check that the msg.sender is the either the owner or the guardian
  function _checkOnlyOwnerOrGuardian() internal view {
    _checkNotAuthorized(msg.sender != guardian && msg.sender != owner());
  }

  /// @notice returns the current balance of this contract for a specific token
  /// @param _token token address
  /// @return balance of `_token` for this contract
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
  }

  /// @notice Checkpoint accrued management fees into `unclaimedFees`.
  /// @dev Raw underlyings are excluded because unsolicited transfers are skimmed instead of managed.
  function _accrueManagementFee() internal {
    unclaimedFees += _calculateManagementFee(_managedContractValue(), block.timestamp - latestHarvestBlock);
    latestHarvestBlock = block.timestamp;
  }

  /// @notice calculate annualized management fee for a balance over a duration
  function _calculateManagementFee(uint256 _nav, uint256 _duration) internal view returns (uint256) {
    // 3153600000000 == FULL_ALLOC * 365 days
    return _nav * managementFee * _duration / 3153600000000;
  }

  /// @notice returns the user tranche balance for a specific tranche
  /// @param _user user address
  /// @param _tranche tranche address
  function _userTrancheBal(address _user, address _tranche) internal view returns (uint256) {
    return IERC20Detailed(_tranche).balanceOf(_user);
  }

  /// @dev Set allowance for _token to unlimited for _spender
  /// @param _token token address
  /// @param _spender spender address
  function _allowUnlimitedSpend(address _token, address _spender) internal {
    IERC20Detailed(_token).safeIncreaseAllowance(_spender, type(uint256).max);
  }

  /// @dev transfer underlyings to a specific address
  /// @param _to receiver address
  /// @param _amount amount to transfer
  function _transferUnderlyings(address _to, uint256 _amount) internal {
    if (_amount == 0) return;
    IERC20Detailed(token).safeTransfer(_to, _amount);
  }

  /// @notice transfer fee to feeReceiver and owner according to feeSplit
  /// @param _amount total fee amount to split and transfer (in underlyings)
  function _transferFeeUnderlyings(uint256 _amount) internal {
    uint256 feeReceiverAmount = _feeReceiverAmount(_amount);
    _transferUnderlyings(feeReceiver, feeReceiverAmount);
    _transferUnderlyings(owner(), _amount - feeReceiverAmount);
  }

  /// @notice calculates the amount to transfer to feeReceiver based on the feeSplit
  /// @param _amount total fee amount to split
  function _feeReceiverAmount(uint256 _amount) internal view returns (uint256) {
    if (feeReceiver == address(0)) return 0;
    return _amount * feeSplit / FULL_ALLOC;
  }

  /// @dev transfer underlyings from a specific address to another address
  /// @param _from sender address
  /// @param _to receiver address
  /// @param _amount amount to transfer
  function _transferUnderlyingsFrom(address _from, address _to, uint256 _amount) internal {
    if (_amount == 0) return;
    IERC20Detailed(token).safeTransferFrom(_from, _to, _amount);
  }

  /// @dev Get the current strategy apr
  function _getStrategyApr() internal view returns (uint256) {
    return IIdleCDOStrategy(strategy).getApr();
  }

  /// @notice concat 2 strings in a single one
  /// @param a first string
  /// @param b second string
  /// @return new string with a and b concatenated
  function _concat(string memory a, string memory b) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b));
  }

  /// @notice check revert condition and revert with AmountTooHigh error
  /// @param _revertCondition condition to check
  function _checkAmountTooHigh(bool _revertCondition) internal pure {
    if (_revertCondition) revert AmountTooHigh();
  }
}
