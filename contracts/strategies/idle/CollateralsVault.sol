// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../../interfaces/IPriceFeed.sol";
import "../../interfaces/IERC20Detailed.sol";

interface IIdleCreditVault {
  function borrower() external view returns (address);
  function manager() external view returns (address);
}

interface IIdleCDOEpochVariant {
  function strategy() external view returns (address);
  function getContractValue() external view returns (uint256);
  function token() external view returns (address);
}

interface ILiquidationAdapter {
  /// @notice Liquidate `collateralAmount` of `collateral` into `borrowedToken`.
  /// @param collateral collateral token to sell
  /// @param collateralAmount amount of collateral to sell
  /// @param borrowedToken token to receive
  /// @param minOut minimum amount of borrowedToken expected
  /// @param data adapter-specific payload (e.g. Uniswap path, 1inch calldata)
  /// @return borrowedOut amount of borrowedToken received
  function liquidateCollateral(
    address collateral,
    uint256 collateralAmount,
    address borrowedToken,
    uint256 minOut,
    bytes calldata data
  ) external returns (uint256 borrowedOut);
}

/// @title CollateralsVault - Contract that holds collaterals for a Credit Vault.
contract CollateralsVault is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20Metadata;

  /////////////////
  /// Constants ///
  /////////////////

  /// ERRORS
  error NotAllowed();
  error InvalidData();
  error CollateralNotAllowed();
  error InvalidOraclePrice();
  error NotLiquidatable();
  error NotEnoughCollaterals();
  error LengthMismatch();

  /// EVENTS
  event CollateralAdded(
    address indexed token,
    address priceFeed,
    uint8 tokenDecimals,
    uint8 priceFeedDecimals,
    uint256 validityPeriod
  );
  event CollateralRemoved(address indexed token);
  event MarginCall(uint256 timestamp);
  event DepositCollateral(address indexed collateral, uint256 amount);
  event RedeemCollateral(address indexed collateral, uint256 amount);
  event Liquidation(uint256 liquidatedValueUsd, uint256 borrowedTokenOut);
  // event LiquidateCollateral(address indexed collateral, uint256 amount);

  /// @notice Information about each allowed collateral token.
  struct CollateralInfo {
    bool allowed;
    address priceFeed;               // Primary oracle address
    uint8 tokenDecimals;             // Collateral token decimals (e.g., 6 for USDC, 18 for DAI)
    uint8 priceFeedDecimals;         // Primary oracle decimals (e.g., 8 for many Chainlink feeds)
    uint256 validityPeriod;          // Validity period in seconds
  }

  /// @notice Maximum LTV ratio (100%)
  uint256 constant public MAX_LTV = 1000; // 1000 means 100%
  /// @notice Maximum liquidation delay
  uint256 constant public MAX_LIQUIDATION_DELAY = 10 days;
  /// @notice Maximum liquidation penalty (100%)
  uint256 constant public MAX_LIQUIDATION_PENALTY = 1000; // 1000 means 100%
  /// @notice Address of the Treasury League multisig
  address constant public TREASURY_LEAGUE_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814; // Replace with actual address

  /////////////////////////
  /// Storage variables ///
  /////////////////////////

  /// @notice Mapping from collateral token address to its info.
  mapping(address => CollateralInfo) public collateralInfo;
  /// @notice Collateral token list.
  address[] public collaterals;

  /// @notice Delay before liquidation can be executed (in seconds).
  uint256 public liquidationDelay;
  /// @notice Percentage of collateral to be liquidated in case of liquidation
  uint256 public liquidationPenalty;
  /// @notice Last timestamp when a margin call was triggered.
  uint256 public lastMarginCallTimestamp;
  /// @notice Loan to value ratio (LTV) threshold for margin calls.
  uint256 public ltv;

  /// @notice Address of the penalty receiver 
  address public penaltyReceiver;
  /// @notice Address of the borrower
  address public borrower;
  /// @notice Address of the manager
  address public manager;
  /// @notice Pauser address
  address public pauser;
  /// @notice Credit Vault address
  IIdleCDOEpochVariant public creditVault;
  /// @notice Token that is borrowed in the credit vault
  IERC20Metadata public borrowedToken;
  /// @notice Cached decimals for the borrowed token (must be <= 18)
  uint8 public borrowedTokenDecimals;
  /// @notice Oracle for the borrowed token (needed if not USD-pegged)
  address public borrowedTokenPriceFeed;
  /// @notice Decimals for the borrowed token oracle
  uint8 public borrowedTokenPriceFeedDecimals;
  /// @notice Validity period for the borrowed token oracle price (in seconds)
  uint256 public borrowedTokenPriceFeedValidityPeriod;
  /// @notice Allowlist of liquidation adapters
  mapping(address => bool) public liquidationAdapters;

  struct LiquidationData {
    address[] collaterals;
    uint256[] minBorrowedOut;
    address[] adapters;
    bytes[] swapDatas;
    uint256 borrowedTokenPrice;
  }

  struct LiquidationLocals {
    uint256 maxBorrowable;
    uint256 borrowed;
    uint256 shortfall;
    uint256 penalty;
    uint256 targetToLiquidate;
    uint256 remainingToLiquidate;
  }

  //////////////////////////
  /// Initialize methods ///
  //////////////////////////

  /// Used to prevent initialization of the implementation contract
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    borrower = address(1);
  }

  /// @notice Initializer (replaces constructor for upgradeable contracts).
  /// @param _pauser The pauser address.
  /// @param _creditVault The address of the credit vault contract.
  /// @param _borrowedTokenPriceFeed Oracle for the borrowed token.
  /// @param _borrowedTokenPriceFeedDecimals Oracle decimals for the borrowed token.
  /// @param _borrowedTokenPriceFeedValidityPeriod Validity period for borrowed token oracle price.
  function initialize(
    address _pauser,
    address _creditVault,
    address _borrowedTokenPriceFeed,
    uint8 _borrowedTokenPriceFeedDecimals,
    uint256 _borrowedTokenPriceFeedValidityPeriod
  ) public initializer {
    if (borrower != address(0)) revert InvalidData(); // already initialized

    __Ownable_init();
    __Pausable_init();
    __ReentrancyGuard_init();

    if (_creditVault == address(0) || _borrowedTokenPriceFeed == address(0) || _borrowedTokenPriceFeedDecimals > 18) {
      revert InvalidData();
    }

    creditVault = IIdleCDOEpochVariant(_creditVault);
    IIdleCreditVault strategy = IIdleCreditVault(creditVault.strategy());
    borrowedToken = IERC20Metadata(creditVault.token());
    borrowedTokenDecimals = borrowedToken.decimals();
    // we rely on 18 decimal scaling across the contract, so borrowed token must be <= 18 decimals
    if (borrowedTokenDecimals > 18) revert InvalidData();
    borrower = strategy.borrower();
    manager = strategy.manager();
    pauser = _pauser;
    penaltyReceiver = TREASURY_LEAGUE_MULTISIG;
    borrowedTokenPriceFeed = _borrowedTokenPriceFeed;
    borrowedTokenPriceFeedDecimals = _borrowedTokenPriceFeedDecimals;
    borrowedTokenPriceFeedValidityPeriod = _borrowedTokenPriceFeedValidityPeriod;

    liquidationDelay = 3 days; // Default liquidation delay is 3 days
    liquidationPenalty = 50; // Default liquidation penalty is 5%
    ltv = 750; // Default LTV threshold for margin calls is 75%
  }

  ////////////////////////
  /// Public functions ///
  ////////////////////////

  /// @notice Deposit collateral tokens into the vault.
  /// @dev This function allows the borrower to deposit collateral tokens into the vault.
  /// @param collateral The address of the collateral token.
  /// @param amount The amount of collateral tokens to deposit.
  function depositCollateral(address collateral, uint256 amount) external nonReentrant whenNotPaused {
    _onlyBorrower();

    // check if the collateral is allowed
    CollateralInfo memory info = collateralInfo[collateral];
    if (!info.allowed) {
      revert CollateralNotAllowed();
    }
    // Transfer collateral tokens from the borrower to this contract
    IERC20Metadata(collateral).safeTransferFrom(msg.sender, address(this), amount);
    // If the position is now healthy, reset the last margin call timestamp
    if (!isLiquidatable() && lastMarginCallTimestamp > 0) {
      lastMarginCallTimestamp = 0;
    }
    emit DepositCollateral(collateral, amount);
  }

  /// @notice Withdraw collateral tokens from the vault.
  /// @dev This function allows the borrower to withdraw collateral tokens from the vault.
  /// @param collateral The address of the collateral token.
  /// @param amount The amount of collateral tokens to withdraw.
  function redeemCollateral(address collateral, uint256 amount) external nonReentrant whenNotPaused {
    _onlyBorrower();

    CollateralInfo memory info = collateralInfo[collateral];
    // here we do not check if the collateral is valid using the `allowed` flag
    // because when the collateral is removed, the borrower can still withdraw it
    if (info.priceFeed == address(0)) {
      revert CollateralNotAllowed();
    }
    // Transfer collateral tokens from this contract to the borrower
    IERC20Metadata(collateral).safeTransfer(msg.sender, amount);

    // check if the position becomes liquidatable
    if (isLiquidatable()) {
      revert NotAllowed();
    }
    emit RedeemCollateral(collateral, amount);
  }

  /// @notice Trigger a margin call if the collateral is insufficient
  function marginCall() external nonReentrant whenNotPaused {
    _onlyManager();

    // Check if the collateral is sufficient
    // If not, trigger a margin call
    if (!isLiquidatable()) {
      revert NotLiquidatable();
    }

    // set the last margin call timestamp
    lastMarginCallTimestamp = block.timestamp;
    emit MarginCall(block.timestamp);
  }

  /// @notice Liquidate the collateral if the liquidation delay has passed.
  /// @dev Manager supplies liquidation order; checks liquidatability+delay, sells collaterals, sends penalty, keeps proceeds in-vault for virtual repayment.
  /// @param collateralsToLiquidate ordered list of collateral tokens to liquidate
  /// @param minBorrowedOut minimum borrowed token expected per collateral (same length as collateralsToLiquidate)
  /// @param adapters liquidation adapters to use per collateral (same length as collateralsToLiquidate)
  /// @param swapDatas calldata payload per collateral for the selected adapter
  /// @return borrowedTokenOutPerCollateral borrowed tokens actually received per collateral in input order
  /// @return borrowedTokenOutTotal total borrowed tokens received from liquidation
  function liquidate(
    address[] calldata collateralsToLiquidate,
    uint256[] calldata minBorrowedOut,
    address[] calldata adapters,
    bytes[] calldata swapDatas
  ) external nonReentrant whenNotPaused returns (uint256[] memory borrowedTokenOutPerCollateral, uint256 borrowedTokenOutTotal) {
    _onlyManager();
    if (collateralsToLiquidate.length == 0) revert InvalidData();
    if (collateralsToLiquidate.length != minBorrowedOut.length) revert LengthMismatch();
    if (collateralsToLiquidate.length != adapters.length || collateralsToLiquidate.length != swapDatas.length) revert LengthMismatch();

    (borrowedTokenOutPerCollateral, borrowedTokenOutTotal) = _executeLiquidation(collateralsToLiquidate, minBorrowedOut, adapters, swapDatas);
  }

  function _executeLiquidation(
    address[] calldata collateralsToLiquidate,
    uint256[] calldata minBorrowedOut,
    address[] calldata adapters,
    bytes[] calldata swapDatas
  ) internal returns (uint256[] memory borrowedTokenOutPerCollateral, uint256 borrowedTokenOutTotal) {
    uint256 borrowedTokenOutTotalLocal;
    {
      LiquidationLocals memory loc;
      loc.maxBorrowable = getTotCollateralsScaled() * ltv / MAX_LTV;
      loc.borrowed = borrowedScaled();
      // Check if the liquidation delay has passed and if the position is liquidatable
      if (loc.maxBorrowable >= loc.borrowed || lastMarginCallTimestamp == 0 || block.timestamp < lastMarginCallTimestamp + liquidationDelay) {
        revert NotLiquidatable();
      }

      loc.shortfall = loc.borrowed - loc.maxBorrowable;
      loc.penalty = loc.shortfall * liquidationPenalty / MAX_LIQUIDATION_PENALTY;
      loc.targetToLiquidate = loc.shortfall * 105 / 100 + loc.penalty;
      loc.remainingToLiquidate = loc.targetToLiquidate;
      uint256 borrowedTokenPrice = getBorrowedTokenPrice();

      LiquidationData memory data = LiquidationData({
        collaterals: collateralsToLiquidate,
        minBorrowedOut: minBorrowedOut,
        adapters: adapters,
        swapDatas: swapDatas,
        borrowedTokenPrice: borrowedTokenPrice
      });

      (borrowedTokenOutPerCollateral, borrowedTokenOutTotalLocal, loc.remainingToLiquidate) = _processLiquidations(
        data,
        loc.remainingToLiquidate
      );

      // If the total liquidated is still less than the amount to liquidate, revert
      if (loc.remainingToLiquidate > 0) {
        revert NotEnoughCollaterals();
      }

      // transfer the liquidation penalty (scaled back to token decimals) to the penalty receiver
      uint256 penaltyInBorrowedToken = loc.penalty * 10 ** borrowedTokenDecimals / borrowedTokenPrice;
      borrowedToken.safeTransfer(penaltyReceiver, penaltyInBorrowedToken);
      // reset margin call timestamp after processing liquidation
      lastMarginCallTimestamp = 0;

      // Remaining borrowed tokens stay in this vault; they count as virtual repayment in borrowedScaled().
      emit Liquidation(loc.targetToLiquidate - loc.remainingToLiquidate, borrowedTokenOutTotalLocal);
    }
    return (borrowedTokenOutPerCollateral, borrowedTokenOutTotalLocal);
  }

  /// @notice Liquidate the collateral token.
  /// @param collateral The address of the collateral token.
  /// @param collAmount The amount of collateral tokens to liquidate
  /// @param minOut Minimum borrowed tokens accepted for this liquidation (slippage control)
  /// @param adapter Adapter to execute the swap.
  /// @param data Adapter-specific calldata (e.g. UniV3 path, 1inch data).
  function _liquidateCollateral(address collateral, uint256 collAmount, uint256 minOut, address adapter, bytes memory data) internal {
    if (!liquidationAdapters[adapter]) revert NotAllowed();
    IERC20Metadata(collateral).safeApprove(adapter, 0);
    IERC20Metadata(collateral).safeApprove(adapter, collAmount);
    uint256 received = ILiquidationAdapter(adapter).liquidateCollateral(collateral, collAmount, address(borrowedToken), minOut, data);
    IERC20Metadata(collateral).safeApprove(adapter, 0);
    if (received < minOut) revert NotEnoughCollaterals();
  }

  /// @notice Helper to liquidate a single collateral token and return actual borrowed received.
  /// @dev Enforces allowed collateral, oracle freshness, per-collateral minOut, and calls `_liquidateCollateral`.
  /// @param collateral Collateral token address to sell.
  /// @param maxValueToLiquidate Max USD value (1e18 scaled) to cover from this collateral.
  /// @param minOut Minimum borrowed tokens expected from this collateral (for slippage checks in `_liquidateCollateral`).
  /// @param adapter Adapter to use for this collateral.
  /// @param data Adapter-specific calldata.
  /// @return valueLiquidated USD value actually liquidated (1e18 scaled).
  /// @return actualBorrowedOut Borrowed tokens actually received from the liquidation.
  function _liquidateSingleCollateral(
    address collateral,
    uint256 maxValueToLiquidate,
    uint256 minOut,
    address adapter,
    bytes memory data
  ) internal returns (uint256 valueLiquidated, uint256 actualBorrowedOut) {
    CollateralInfo memory info = collateralInfo[collateral];
    if (!info.allowed) revert CollateralNotAllowed();

    uint256 tokenBalance = IERC20Metadata(collateral).balanceOf(address(this));
    if (tokenBalance == 0) {
      return (0, 0);
    }
    uint256 priceScaled = getOraclePrice(collateral);
    uint256 collateralValueScaled = tokenBalance * priceScaled / 10 ** info.tokenDecimals;
    if (collateralValueScaled == 0) {
      return (0, 0);
    }

    valueLiquidated = maxValueToLiquidate < collateralValueScaled ? maxValueToLiquidate : collateralValueScaled;
    uint256 collAmount = valueLiquidated * 10 ** info.tokenDecimals / priceScaled;
    uint256 borrowedBefore = borrowedToken.balanceOf(address(this));
    _liquidateCollateral(collateral, collAmount, minOut, adapter, data);
    uint256 borrowedAfter = borrowedToken.balanceOf(address(this));
    actualBorrowedOut = borrowedAfter - borrowedBefore;
  }

  /// @notice Internal processor for liquidation loop to reduce stack usage in `liquidate`.
  function _processLiquidations(
    LiquidationData memory data,
    uint256 remainingToLiquidate
  )
    internal
    returns (uint256[] memory borrowedTokenOutPerCollateral, uint256 borrowedTokenOutTotal, uint256 remainingAfter)
  {
    uint256 collLen = data.collaterals.length;
    borrowedTokenOutPerCollateral = new uint256[](collLen);
    for (uint256 i = 0; i < collLen && remainingToLiquidate > 0; i++) {
      (uint256 valueLiquidated, uint256 actualOut) = _liquidateSingleCollateral(
        data.collaterals[i],
        remainingToLiquidate,
        data.minBorrowedOut[i],
        data.adapters[i],
        data.swapDatas[i]
      );
      if (valueLiquidated == 0) {
        continue;
      }
      borrowedTokenOutPerCollateral[i] = actualOut;
      borrowedTokenOutTotal += actualOut;
      // decrease remaining based on actual borrowedToken received valued in USD
      uint256 valueRecovered = actualOut * data.borrowedTokenPrice / 10 ** borrowedTokenDecimals;
      if (valueRecovered > remainingToLiquidate) {
        remainingToLiquidate = 0;
      } else {
        remainingToLiquidate -= valueRecovered;
      }
    }
    remainingAfter = remainingToLiquidate;
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @notice Check if the vault is liquidatable, ie a margin call can be triggered.
  /// @return bool True if the vault is liquidatable, false otherwise.
  function isLiquidatable() public view returns (bool) {
    // Check if max borrowable is below the credit vault tvl (ie borrowed amount)
    return getTotCollateralsScaled() * ltv / MAX_LTV < borrowedScaled();
  }

  /// @notice Retrieves the total value of all collateral tokens in the vault.
  /// @return The total value of all collateral tokens in the vault (scaled to 18 decimals).
  function getTotCollateralsScaled() public view returns (uint256) {
    // This function should return the total value of all collateral tokens in the vault (scaled to 18 decimals).
    address collateralToken;
    CollateralInfo memory info;
    uint256 totalCollateralValue;
    address[] memory _collaterals = collaterals;
    uint256 collateralsLen = _collaterals.length;

    // loop through all collaterals and scaled their value to 18 decimals
    for (uint256 i = 0; i < collateralsLen; i++) {
      collateralToken = _collaterals[i];
      info = collateralInfo[collateralToken];
      if (!info.allowed) continue;
      totalCollateralValue += IERC20Metadata(collateralToken).balanceOf(address(this)) * getOraclePrice(collateralToken) / 10 ** info.tokenDecimals;
    }

    return totalCollateralValue;
  }

  /// @notice Retrieves the total value locked (TVL) in the credit vault which is the borrowed amount.
  /// @return The total borrowed amount (scaled to 18 decimals).
  function borrowedScaled() public view returns (uint256) {
    // This function should return the total value of all assets in the credit vault (scaled to 18 decimals).
    // Virtual repayment: borrowed tokens held in this vault offset the debt up to zero.
    uint256 price = getBorrowedTokenPrice();
    uint256 borrowedValue = IIdleCDOEpochVariant(creditVault).getContractValue() * price / 10 ** borrowedTokenDecimals;
    uint256 borrowedHeldByVault = borrowedToken.balanceOf(address(this)) * price / 10 ** borrowedTokenDecimals;
    if (borrowedHeldByVault >= borrowedValue) {
      return 0;
    }
    return borrowedValue - borrowedHeldByVault;
  }

  /// @notice Retrieves the oracle price for collateral and normalizes it to 18 decimals.
  /// @param token The collateral token address.
  /// @return price The normalized price (18 decimals) in USD.
  function getOraclePrice(address token) public view returns (uint256 price) {
    CollateralInfo memory info = collateralInfo[token];
    if (!info.allowed) {
      revert CollateralNotAllowed();
    }
    // Fetch latest round data from the oracle
    (,int256 answer,,uint256 updatedAt,) = IPriceFeed(info.priceFeed).latestRoundData();
    // if validity period is 0, it means that we accept any price > 0
    // othwerwise, we check if the price is updated within the validity period
    if (answer > 0 && (info.validityPeriod == 0 || (updatedAt >= block.timestamp - info.validityPeriod))) {
      // scale the value to 18 decimals
      return uint256(answer) * 10 ** (18 - info.priceFeedDecimals);
    }
    revert InvalidOraclePrice();
  }

  /// @notice Retrieves the oracle price for the borrowed token and normalizes it to 18 decimals.
  /// @return price The normalized price (18 decimals) in USD.
  function getBorrowedTokenPrice() public view returns (uint256 price) {
    address _borrowedFeed = borrowedTokenPriceFeed;
    uint256 _borrowedFeedValidity = borrowedTokenPriceFeedValidityPeriod;
    if (_borrowedFeed == address(0)) revert InvalidData();
    (,int256 answer,,uint256 updatedAt,) = IPriceFeed(_borrowedFeed).latestRoundData();
    if (answer > 0 && (_borrowedFeedValidity == 0 || (updatedAt >= block.timestamp - _borrowedFeedValidity))) {
      return uint256(answer) * 10 ** (18 - borrowedTokenPriceFeedDecimals);
    }
    revert InvalidOraclePrice();
  }

  /// @notice Get collateral info for a specific token.
  /// @param token The collateral token address.
  /// @return info The collateral info.
  function getCollateralInfo(address token) external view returns (CollateralInfo memory) {
    return collateralInfo[token];
  }

  /// @notice Retrieve the list of collateral tokens.
  /// @return The list of collateral token addresses.
  function getCollaterals() external view returns (address[] memory) {
    return collaterals;
  }

  //////////////////////////
  /// Internal functions ///
  //////////////////////////

  /// @notice Check if the caller is the manager.
  function _onlyManager() internal view {
    if (msg.sender != manager) {
      revert NotAllowed();
    }
  }

  /// @notice Check if the caller is the borrower.
  function _onlyBorrower() internal view {
    if (msg.sender != borrower) {
      revert NotAllowed();
    }
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

  /// @notice Add new collateral
  /// @dev IMPORTANT: be sure that priceFeed has no min/max answer
  /// @dev This method can be used also to update collateral info by passing the same token address
  /// @param token The collateral token address.
  /// @param priceFeed The primary oracle address.
  /// @param validityPeriod The validity period for the oracle price (in seconds).
  function addCollateral(
    address token,
    address priceFeed,
    uint256 validityPeriod
  ) external {
    _checkOwner();

    if (token == address(0) || priceFeed == address(0)) revert InvalidData();
    // check if the token is already added
    bool isOverwriting = collateralInfo[token].allowed;
    uint8 tokenDecimals = IERC20Metadata(token).decimals();
    // priceFeed is not an ERC20 token, but has the decimals() method
    uint8 priceFeedDecimals = IERC20Metadata(priceFeed).decimals();
    if (tokenDecimals > 18 || priceFeedDecimals > 18) revert InvalidData();
    collateralInfo[token] = CollateralInfo({
      allowed: true,
      priceFeed: priceFeed,
      tokenDecimals: tokenDecimals,
      priceFeedDecimals: priceFeedDecimals,
      validityPeriod: validityPeriod
    });
    // add the token to the list of collaterals
    if (!isOverwriting) {
      collaterals.push(token);
    }
    emit CollateralAdded(token, priceFeed, tokenDecimals, priceFeedDecimals, validityPeriod);
  }

  /// @notice Disable collateral for minting
  /// @param token The collateral token address to remove.
  function removeCollateral(address token) external {
    _checkOwner();

    if (token == address(0)) revert InvalidData();
    CollateralInfo storage info = collateralInfo[token];
    info.allowed = false;
    emit CollateralRemoved(token);
  }

  /// @notice Set the Loan to Value (LTV) ratio.
  /// @dev LTV is a percentage value, so it should be between 0 and 100.
  /// @param _ltv The new LTV ratio (in percentage).
  function setLTV(uint256 _ltv) external {
    _checkOwner();

    if (_ltv > MAX_LTV) revert InvalidData(); // LTV cannot be more than 100%
    ltv = _ltv;
  }

  /// @notice Set the liquidation parameters.
  /// @param _liquidationDelay Liquidation delay is the time after which a liquidation can be executed.
  /// @param _liquidationPenalty Liquidation penalty is fee charged on the collateral during liquidation.
  function setLiquidationParams(uint256 _liquidationDelay, uint256 _liquidationPenalty) external {
    _checkOwner();

    if (_liquidationDelay > MAX_LIQUIDATION_DELAY || _liquidationPenalty > MAX_LIQUIDATION_PENALTY) revert InvalidData();
    liquidationDelay = _liquidationDelay;
    liquidationPenalty = _liquidationPenalty;
  }

  /// @notice Set the penalty receiver address.
  /// @dev This address will receive the liquidation penalty.
  /// @param _penaltyReceiver The address of the penalty receiver.
  function setPenaltyReceiver(address _penaltyReceiver) external {
    _checkOwner();

    if (_penaltyReceiver == address(0)) revert InvalidData();
    penaltyReceiver = _penaltyReceiver;
  }

  /// @notice Set or update the price feed for the borrowed token.
  /// @param _priceFeed The oracle address.
  /// @param _priceFeedDecimals Oracle decimals.
  /// @param _validityPeriod Validity period for the oracle price (in seconds).
  function setBorrowedTokenPriceFeed(address _priceFeed, uint8 _priceFeedDecimals, uint256 _validityPeriod) external {
    _checkOwner();
    if (_priceFeed == address(0) || _priceFeedDecimals > 18) revert InvalidData();
    borrowedTokenPriceFeed = _priceFeed;
    borrowedTokenPriceFeedDecimals = _priceFeedDecimals;
    borrowedTokenPriceFeedValidityPeriod = _validityPeriod;
  }

  /// @notice Allow or disallow a liquidation adapter.
  /// @param adapter Adapter address.
  /// @param allowed True to allow, false to disallow.
  function setLiquidationAdapter(address adapter, bool allowed) external {
    _checkOwner();
    if (adapter == address(0)) revert InvalidData();
    liquidationAdapters[adapter] = allowed;
  }

  /// @notice Disable a collateral and bypass its oracle in case of oracle failure.
  /// @dev Collateral is excluded from LTV calculations but can still be withdrawn by the borrower.
  /// @param token The collateral token address.
  function disableCollateralBypassOracle(address token) external {
    _checkOwner();
    if (token == address(0)) revert InvalidData();
    CollateralInfo storage info = collateralInfo[token];
    info.allowed = false;
    // set a non-zero sentinel to keep borrower withdrawals working while bypassing oracle usage
    info.priceFeed = address(1);
    emit CollateralRemoved(token);
  }

  /// @notice Emergency function for the owner to withdraw collateral tokens.
  /// @param token The collateral token address.
  /// @param amount The amount to withdraw.
  function emergencyWithdraw(address token, uint256 amount) public virtual {
    _checkOwner();
    IERC20Metadata(token).safeTransfer(msg.sender, amount);
  }

  /// @notice Pauser can pause the contract in emergencies.
  function pause() external {
    if (msg.sender != owner() && msg.sender != pauser) {
      revert NotAllowed();
    }
    _pause();
  }

  /// @notice Owner can unpause the contract.
  function unpause() external {
    _checkOwner();
    _unpause();
  }
}
