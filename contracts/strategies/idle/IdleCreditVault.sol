// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IIdleCDOEpochVariant {
  function isEpochRunning() external view returns (bool);
}

error NotAllowed();

contract IdleCreditVault is
  Initializable,
  OwnableUpgradeable,
  ERC20Upgradeable,
  ReentrancyGuardUpgradeable,
  IIdleCDOStrategy
{
  using SafeERC20Upgradeable for IERC20Detailed;

  /// @notice underlying token address (pool currency for Clearpool)
  address public override token;
  /// @notice decimals of the underlying asset
  uint256 public override tokenDecimals;
  /// @notice one underlying token
  uint256 public override oneToken;
  /// @notice underlying ERC20 token contract (pool currency for Clearpool)
  IERC20Detailed public underlyingToken;
  /// @notice address of the IdleCDO
  address public idleCDO;
  /// @notice one year, used to calculate the APR
  uint256 public constant YEAR = 365 days;
  /// @notice latest saved apr
  uint256 public lastApr;
  /// @notice address of the borrower
  address public borrower;
  /// @notice address of the manager
  address public manager;
  /// @notice user withdraw requests
  mapping (address => uint256) public withdrawsRequests;
  /// @notice user instant withdraw requests
  mapping (address => uint256) public instantWithdrawsRequests;
  /// @notice total withdraw requests
  uint256 public pendingWithdraws;
  /// @notice pending instant withdraw requests
  uint256 public pendingInstantWithdraws;
  /// @notice counter for epoch deposits
  uint256 public totEpochDeposits;
  /// @notice flag to allow transfers
  bool public canTransfer;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    token = address(1);
  }

  /// @notice can be only called once
  /// @param _underlyingToken address of the underlying token (pool currency)
  function initialize(
    address _underlyingToken,
    address _owner,
    address _manager,
    address _borrower,
    string memory borrowerName,
    uint256 _apr
  ) public virtual initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    require(token == address(0), "Token is already initialized");

    //----- // -------//
    token = _underlyingToken;
    underlyingToken = IERC20Detailed(token);
    tokenDecimals = underlyingToken.decimals();
    oneToken = 10**(tokenDecimals);
    borrower = _borrower;
    manager = _manager;
    lastApr = _apr;

    ERC20Upgradeable.__ERC20_init(
      string(abi.encodePacked("Idle Credit Vault ", borrowerName)),
      string(abi.encodePacked("idle_", borrowerName))
    );
    //------//-------//

    transferOwnership(_owner);
  }

  /// @notice strategy token decimals
  /// @dev equal to underlying token decimals
  /// @return number of decimals
  function decimals() public view override returns (uint8) {
    return uint8(tokenDecimals);
  }

  /// @notice strategy token address
  function strategyToken() external view override returns (address) {
    return address(this);
  }

  /// @notice return strategy token price which is always 1
  /// @return price in underlyings
  function price() public view virtual override returns (uint256) {
    return oneToken;
  }

  /// @notice current fixed apr for the epoch
  function getApr() external view returns (uint256) {
    return lastApr;
  }

  /// @notice set manager address
  /// @param _manager address of the new manager
  function setManager(address _manager) external onlyOwner {
    manager = _manager;
  }

  /// @notice set the fixed apr
  /// @dev only cdo and manager can set the apr. If manager manually set apr from 
  /// here it will not be scaled to include the buffer period
  function setApr(uint256 _apr) external {
    address _cdo = idleCDO;

    // if cdo is not yet set we skip the check (this can happen only during the setup)
    if (_cdo != address(0)) {
      if (msg.sender != _cdo && msg.sender != manager) {
        revert NotAllowed();
      }
    }
    lastApr = _apr;
  }

  /// @notice request withdraw of underlying token from the vault
  /// @dev we don't burn strategy tokens here, but we increase the withdraw requests
  /// @param _amount number of tokens to withdraw
  /// @param _user address of the user
  /// @param _netInterest net interest gained in the next epoch
  function requestWithdraw(uint256 _amount, address _user, uint256 _netInterest) external {
    _onlyIdleCDO();
    // burn strategy tokens from cdo (we don't burn interest here, only the principal)
    _burn(msg.sender, _amount - _netInterest);
    // mint equal amount of strategy tokens to the user as receipt (interest included), useful in case of default
    _mint(_user, _amount);

    // increase the withdraw requests for the user
    withdrawsRequests[_user] += _amount;
    // increase the total withdraw requests
    pendingWithdraws += _amount;
  }

  /// @notice claim the withdraw request
  /// @dev we burn the strategy tokens and transfer the underlying tokens
  /// @param _user address of the user
  /// @return amount number of tokens claimed
  function claimWithdrawRequest(address _user) external returns (uint256 amount) {
    _onlyIdleCDO();
    // get amount of underlyings
    amount = withdrawsRequests[_user];
    // burn strategy tokens 1:1 with the amount of underlyings
    _burn(_user, amount);
    withdrawsRequests[_user] = 0;
    underlyingToken.safeTransfer(_user, amount);
  }

  /// @notice request instant withdraw of underlying token from the vault
  /// @dev we burn strategy tokens here, and we increase the instant withdraw requests
  /// @param _amount number of tokens to withdraw
  /// @param _user address of the user
  function requestInstantWithdraw(uint256 _amount, address _user) external {
    _onlyIdleCDO();
    // burn strategy tokens from cdo
    _burn(msg.sender, _amount);
  
    // mint equal amount of strategy tokens to the user as receipt, useful in case of default
    _mint(_user, _amount);

    // increase the instant withdraw requests for the user
    instantWithdrawsRequests[_user] += _amount;
    // increase the total instant withdraw requests
    pendingInstantWithdraws += _amount;
  }

  /// @notice claim the instant withdraw request
  /// @dev we transfer the underlying tokens
  /// @param _user address of the user
  function claimInstantWithdrawRequest(address _user) external {
    _onlyIdleCDO();
    uint256 amount = instantWithdrawsRequests[_user];
    // burn strategy tokens from user
    _burn(_user, amount);

    instantWithdrawsRequests[_user] = 0;
    underlyingToken.safeTransfer(_user, amount);
  }

  /// @notice collect the instant withdraw funds
  /// @dev only IdleCDO can call this function
  /// @param _amount number of tokens to collect
  function collectInstantWithdrawFunds(uint256 _amount) external {
    _onlyIdleCDO();
    pendingInstantWithdraws -= _amount;
    underlyingToken.safeTransferFrom(idleCDO, address(this), _amount);
  }

  /// @notice collect the withdraw funds
  /// @dev only IdleCDO can call this function
  /// @param _amount number of tokens to collect
  function collectWithdrawFunds(uint256 _amount) external {
    _onlyIdleCDO();
    pendingWithdraws -= _amount;
    underlyingToken.safeTransferFrom(idleCDO, address(this), _amount);
  }

  /// @notice Send funds to the IdleCDO
  /// @param _amount number of underlyings to transfer
  function sendInterestAndDeposits(uint256 _amount) external {
    _onlyIdleCDO();
    IERC20Detailed(token).safeTransfer(idleCDO, _amount);
  }

  /// @notice Get funds from IdleCDO and mint strategy tokens. Funds are not sent to the borrower here
  /// @param _amount number of underlyings to transfer
  function deposit(uint256 _amount)
    external
    virtual
    override
    returns (uint256) {
    _onlyIdleCDO();
    underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
    _mint(msg.sender, _amount);

    if (IIdleCDOEpochVariant(idleCDO).isEpochRunning()) {
      // deposit done on stopEpoch (before setting the var to false) so we reset the counter
      totEpochDeposits = 0;
    } else {
      // deposit done between epochs so we increase the counter
      totEpochDeposits += _amount;
    }

    return _amount;
  }
  
  /// @inheritdoc ERC20Upgradeable
  /// @dev we don't allow transfers of strategy tokens normally, transfers are allowed only after a default
  function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
    if (msg.sender != idleCDO && !canTransfer) {
      revert NotAllowed();
    }
    super._transfer(sender, recipient, amount);
  }

  /// @notice allow transfers of strategy tokens
  function allowTransfers() external {
    _onlyIdleCDO();
    canTransfer = true;
  }

  /// @notice allow to update whitelisted address
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    idleCDO = _cdo;
  }

  /// @notice Emergency method to rescue funds
  /// @param _token address of the token to transfer
  /// @param value amount of `_token` to transfer
  /// @param _to receiver address
  function transferToken(address _token, uint256 value, address _to) external onlyOwner {
    IERC20Detailed(_token).safeTransfer(_to, value);
  }

  /// @notice Modifier to make sure that caller os only the idleCDO contract
  function _onlyIdleCDO() internal view {
    if (msg.sender != idleCDO) {
      revert NotAllowed();
    }
  }

  /// @notice Not used as redeems happens only via requestWithdraw and requestInstantWithdraw
  function redeem(uint256 _amount)
    external
    override
    returns (uint256) {}

  /// @notice Not used as redeems happens only via requestWithdraw and requestInstantWithdraw
  function redeemUnderlying(uint256)
    external
    returns (uint256) {}

  /// @notice not used in this strategy
  function pullStkAAVE() 
    external 
    pure 
    override 
    returns (uint256) {}

  /// @notice not used for this strategy
  function getRewardTokens()
    external
    view
    override
    returns (address[] memory) {}

  /// @notice not used for this strategy
  function redeemRewards(bytes calldata)
    external
    override
    returns (uint256[] memory rewards) {}
}
