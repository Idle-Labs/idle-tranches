// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IOracle {
  function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
interface IUSD0pp {
  function getFloorPrice() external view returns (uint256);
}

contract IdleUsualStrategy is
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

  /// @notice price of 1 usd0++ in $ (18 decimals)
  uint256 public oraclePrice;

  address public constant USUAL = 0xC4441c2BE5d8fA8126822B9929CA0b81Ea0DE38E;
  address public constant USD0pp = 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0;
  address public constant USD0ppOracle = 0xFC9e30Cf89f8A00dba3D34edf8b65BCDAdeCC1cB;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    token = address(1);
  }

  /// @notice can be only called once
  /// @param _underlyingToken address of the underlying token
  /// @param _owner address of the owner
  function initialize(
    address _underlyingToken,
    address _owner
  ) public virtual initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    require(token == address(0), "Token is already initialized");

    //----- // -------//
    token = _underlyingToken;
    underlyingToken = IERC20Detailed(token);
    tokenDecimals = underlyingToken.decimals();
    oneToken = 10**(tokenDecimals);
    oraclePrice = getChainlinkPrice();

    ERC20Upgradeable.__ERC20_init(
      "Idle Usual Strategy Token",
      string(abi.encodePacked("idle_", IERC20Detailed(_underlyingToken).symbol()))
    );

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

  /// @notice return strategy token price which is equal to the oracle price
  /// @return price
  function price() public view virtual override returns (uint256) {
    return oneToken;
  }

  /// @notice Redeem Tokens
  /// @param _amount amount of strategyTokens to redeem
  /// @return Amount of underlying tokens received
  function redeem(uint256 _amount)
    external
    override
    onlyIdleCDO
    returns (uint256)
  {
    if (_amount > 0) {
      // burn strategyTokens 
      _burn(msg.sender, _amount);
      // transfer underlying tokens (1:1 with strategyTokens)
      underlyingToken.safeTransfer(msg.sender, _amount);
      return _amount;
    }
    return 0;
  }

  /// @notice Redeem Tokens
  /// @param _amount amount of underlying tokens to redeem
  /// @return Amount of underlying tokens received
  function redeemUnderlying(uint256 _amount)
    external
    onlyIdleCDO
    returns (uint256)
  {
    if (_amount > 0) {
      // burn strategyTokens (same decimals as underlying tokens, 1:1 with underlyings)
      _burn(msg.sender, _amount);
      // transfer underlying tokens
      underlyingToken.safeTransfer(msg.sender, _amount);
      return _amount;
    }
    return 0;
  }

  /// @notice Deposit the underlying token to vault
  /// @param _amount number of tokens to deposit
  /// @return minted number of strategyTokens minted
  function deposit(uint256 _amount)
    external
    override
    onlyIdleCDO
    returns (uint256 minted)
  {
    if (_amount > 0) {
      underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
      // 1:1 with underlying tokens
      minted = _amount;
      _mint(msg.sender, minted);
    }
  }

  /// @notice allow to update the oracle price
  /// @param _price new oracle price (18 decimals -> ie 1$ = 1e18)
  function setOraclePrice(uint256 _price) external {
    require(msg.sender == owner() || msg.sender == idleCDO, "!AUTH");
    // check that submitted price is not less than the floor price
    // and set oraclePrice
    uint256 floorPrice = IUSD0pp(USD0pp).getFloorPrice();
    oraclePrice = _price >= floorPrice ? _price : floorPrice;
  }

  /// @notice get the chainlink price of usd0++ and scale it to 18 decimals
  function getChainlinkPrice() public view returns (uint256) {
    (,int256 answer,,,) = IOracle(USD0ppOracle).latestRoundData();
    // scale the answer to 18 decimals
    return uint256(answer) * 1e10;
  }

  /// @notice allow to update whitelisted address
  /// @param _cdo new address of the IdleCDO
  function setWhitelistedCDO(address _cdo) external onlyOwner {
    require(_cdo != address(0), "IS_0");
    idleCDO = _cdo;
  }

  /// @notice Modifier to make sure that caller os only the idleCDO contract
  modifier onlyIdleCDO() {
    require(idleCDO == msg.sender, "Only IdleCDO can call");
    _;
  }

  /// @notice Emergency method to rescue funds
  /// @param _token address of the token to transfer
  /// @param value amount of `_token` to transfer
  /// @param _to receiver address
  function transferToken(address _token, uint256 value, address _to) external onlyOwner {
    IERC20Detailed(_token).safeTransfer(_to, value);
  }

  /// @notice Not used
  function redeemRewards(bytes calldata) external onlyIdleCDO override returns (uint256[] memory) {}

  /// @notice Not used
  function pullStkAAVE() external pure override returns (uint256) {}

  /// @notice Not used
  function getRewardTokens() external pure override returns (address[] memory rewards) {
    rewards = new address[](1);
    rewards[0] = USUAL;
  }

  /// @notice Apr is calculated off-chain
  function getApr() external pure returns (uint256) {
    return 0;
  }
}
