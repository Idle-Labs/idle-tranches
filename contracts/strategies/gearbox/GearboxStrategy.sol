// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../ERC4626Strategy.sol";
import "../../interfaces/gearbox/DToken.sol";
import "../../interfaces/gearbox/IFarmingPool.sol";
import "../../interfaces/IStaticQuoter.sol";
import "../../interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract GearboxStrategy is ERC4626Strategy, ERC20Upgradeable {
  using SafeERC20Upgradeable for IERC20Detailed;

  address public constant GEAR = 0xBa3335588D9403515223F109EdC4eB7269a9Ab5D;
  uint256 internal constant REF_CODE = 104353;
  // uniswap path to quote GEAR rewards
  bytes public uniV3Path;
  // https://github.com/eden-network/uniswap-v3-static-quoter/blob/master/contracts/UniV3Quoter/UniswapV3StaticQuoter.sol
  address internal constant UNI_V3_STATIC_QUOTER = 0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE;
  address public stakedStrategyToken;

  function initialize(address _vault, address _underlying, address _owner, address _stakedStrategyToken, bytes calldata _uniV3Path) public {
    _initialize(_vault, _underlying, _owner);
    stakedStrategyToken = _stakedStrategyToken;
    uniV3Path = _uniV3Path;
    // approve farming contract to spend strategyToken (ie _vault which is a ERC4626 token)
    IERC20Detailed(_vault).safeApprove(_stakedStrategyToken, type(uint256).max);
  }

  /// @notice can be only called once
  /// @dev This method is copied from ERC4626Strategy and modified to tokenize the position
  /// @param _strategyToken address of the vault token
  /// @param _token address of the underlying token
  /// @param _owner owner of this contract
  function _initialize(
    address _strategyToken,
    address _token,
    address _owner
  ) internal override initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    require(token == address(0), "Token is already initialized");

    //----- // -------//
    strategyToken = _strategyToken;
    token = _token;
    underlyingToken = IERC20Detailed(token);
    tokenDecimals = underlyingToken.decimals();
    oneToken = 10**(tokenDecimals); // underlying decimals
    //------//-------//

    transferOwnership(_owner);

    IERC20Detailed(_token).safeApprove(_strategyToken, type(uint256).max);

    // Added ERC20 init here as it needs to be inside the _initialize function
    ERC20Upgradeable.__ERC20_init(
      "Idle Gearbox Strategy Token",
      string(abi.encodePacked("idle_", IERC20Detailed(_strategyToken).symbol()))
    );
  }

  /// @dev this is not safe from manipulations, should only be used off-chain
  /// @return apr in scaled by 1e18 where 1e18 means 1% apr
  function getApr() external view override returns (uint256 apr) {
    // base apr is in 1e27 format, so we div by 1e9 and then multiply by 100 (ie div 1e7)
    apr = DToken(strategyToken).supplyRate() / 1e7;
    // add GEAR apr
    apr += _rewardsApr();
  }

  /// @return apr of GEAR rewards in scaled by 1e18 where 1e18 means 1% apr
  function _rewardsApr() internal view returns (uint256) {
    address _stakedStrategyToken = stakedStrategyToken;
    uint256 _oneReward = 10 ** uint256(IERC20Detailed(GEAR).decimals());
    uint256 _oneStakedToken = 10 ** uint256(IERC20Detailed(_stakedStrategyToken).decimals());

    // quote 1 reward to underlyings
    uint256 _quote = IStaticQuoter(UNI_V3_STATIC_QUOTER).quoteExactInput(uniV3Path, _oneReward);
    // get farming info (ie duration and amount of rewards)
    IFarmingPool.Info memory _info = IFarmingPool(_stakedStrategyToken).farmInfo();
    // scale to rewards per year
    uint256 _rewardsPerYear = uint256(_info.reward) * 365 days / uint256(_info.duration);
    // total deposited assets
    uint256 _totalDeposited = IERC20Detailed(_stakedStrategyToken).totalSupply();
    // calculate rewards apr (in 1e18 format). We multiply total deposited asset by price 
    // to convert from staked strategy token to underlying as _quote is in underlyings
    return _quote * _rewardsPerYear * 100 / (_totalDeposited * price() / _oneStakedToken);
  }

  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return shares strategyTokens minted
  function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 shares) {
    if (_amount != 0) {
      // Send underlyings to the strategy
      IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
      // Calls deposit function and get dTokens
      shares = DToken(strategyToken).depositWithReferral(_amount, address(this), REF_CODE);
      // stake dTokens and get sdTokens
      IFarmingPool(stakedStrategyToken).deposit(shares);
      // mint strategyTokens (that should have 18 decimals) to msg.sender
      _mint(msg.sender, shares * 10**18 / oneToken);
    }
  }

  function _redeem(uint256 _shares) internal override returns (uint256 redeemed) {
    if (_shares != 0) {
      // tokenized position (ie this contract) has 18 decimals
      _burn(msg.sender, (_shares * 1e18) / oneToken);
      // unstake sdToken
      IFarmingPool(stakedStrategyToken).withdraw(_shares);
      // redeem dTokens to underlying and send underlyings to IdleCDO
      redeemed = IERC4626(strategyToken).redeem(_shares, msg.sender, address(this));
    }
  }

  /// @notice redeem the rewards
  /// @return rewards amount of reward that is deposited to the `strategy`
  function redeemRewards(bytes calldata)
    public
    override
    onlyIdleCDO
    nonReentrant
    returns (uint256[] memory rewards)
  {
    // claim rewards
    IFarmingPool(stakedStrategyToken).claim();
    rewards = new uint256[](1);
    rewards[0] = IERC20Detailed(GEAR).balanceOf(address(this));
    // send rewards to IdleCDO
    if (rewards[0] > 0) {
      IERC20Detailed(GEAR).safeTransfer(msg.sender, rewards[0]);
    }
  }

  /// @notice list rewards tokens
  /// @return rewards list of reward tokens
  function getRewardTokens() external override pure returns (address[] memory rewards) {
    rewards = new address[](1);
    rewards[0] = GEAR;
  }

  /// @notice set the uniswap path to quote GEAR rewards
  /// @param _uniV3Path uniswap path to quote GEAR rewards
  function setUniV3Path(bytes calldata _uniV3Path) external onlyOwner {
    uniV3Path = _uniV3Path;
  }
}