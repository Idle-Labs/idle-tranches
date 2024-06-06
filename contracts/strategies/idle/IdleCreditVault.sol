// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/clearpool/IPoolFactory.sol";
import "../../interfaces/clearpool/IPoolMaster.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

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

  /// @notice set the fixed apr
  /// @dev only manager can set the apr
  function setApr(uint256 _apr) external {
    if (msg.sender != idleCDO && msg.sender != manager) {
      revert NotAllowed();
    }
    lastApr = _apr;
  }

  /// @notice request withdraw of underlying token from the vault
  /// @dev we don't burn strategy tokens here, but we increase the withdraw requests
  /// @param _amount number of tokens to withdraw
  /// @param _user address of the user
  function requestWithdraw(uint256 _amount, address _user) external {
    _onlyIdleCDO();
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
    amount = withdrawsRequests[_user];
    // burn strategy tokens
    _burn(msg.sender, amount);
    withdrawsRequests[_user] = 0;
    pendingWithdraws -= amount;
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

  /// @notice Mint strategy tokens
  /// @param _amount number of underlyings to mint
  function mintStrategyTokens(uint256 _amount) external returns (uint256 minted) {
    _onlyIdleCDO();
    _mint(msg.sender, _amount);
    minted = _amount;
  }

  /// @notice allow to update whitelisted address
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    idleCDO = _cdo;
  }

  /// @notice Modifier to make sure that caller os only the idleCDO contract
  function _onlyIdleCDO() internal view {
    if (msg.sender != idleCDO) {
      revert NotAllowed();
    }
  }

  /// @notice Not used as deposits to borrower and mint of strategy tokens are done via IdleCDO
  function deposit(uint256 _amount)
    external
    virtual
    override
    returns (uint256 minted) {}

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
