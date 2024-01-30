// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "morpho-urd/src/interfaces/IUniversalRewardsDistributor.sol";

import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/morpho/IMetamorphoSnippets.sol";
import "../../interfaces/morpho/IRewardsEmissions.sol";
import "../../interfaces/morpho/IMorpho.sol";
import "../../interfaces/morpho/IMMVault.sol";
import "../../interfaces/IStaticQuoter.sol";
import "../ERC4626Strategy.sol";

contract MetaMorphoStrategy is ERC4626Strategy {
  using SafeERC20Upgradeable for IERC20Detailed;

  //// @notice MORPHO governance token
  address internal constant MORPHO = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
  IMorpho internal constant MORPHO_BLUE = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
  address internal constant MORPHO_REWARDS_EMISSION = 0xf27fa85b6748c8a64d4b0D3D6083Eb26f18BDE8e;
  // https://github.com/eden-network/uniswap-v3-static-quoter/blob/master/contracts/UniV3Quoter/UniswapV3StaticQuoter.sol
  address internal constant UNI_V3_STATIC_QUOTER = 0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE;
  uint256 internal constant EXP_SCALE = 1e18;

  /// @notice reward token address (e.g. MORPHO, COMP, ...)
  address[] public rewardTokens;

  /// @notice MORPHO transferability
  bool public morphoTransferable;

  /// @notice Metamorpho snippets contract, used for apr
  address public mmSnippets;

  struct RewardData {
    address sender;
    address urd;
    address rewardToken;
    bytes32 marketId;
    bytes uniV3Path;
  }

  struct AprData {
    uint256 add;
    uint256 sub;
    uint256 marketsLen;
    uint256 totalAssets;
  }

  /// @notice reward token data
  mapping(address => RewardData) public rewardsData;

  /// Initialization

  /// @notice initialize the strategy
  /// @param _strategyToken strategy token address
  /// @param _token underlying token address
  /// @param _owner owner address
  /// @param _mmSnippets snippets contract address
  /// @param _rewardTokens array of reward tokens
  function initialize(
    address _strategyToken,
    address _token,
    address _owner,
    address _mmSnippets,
    address[] memory _rewardTokens
  ) public {
    _initialize(_strategyToken, _token, _owner);

    // used to fetch apr
    mmSnippets = _mmSnippets;

    for (uint256 i = 0; i < _rewardTokens.length; i++) {
      rewardTokens.push(_rewardTokens[i]);
    }
  }

  /// External and public methods

  /// @notice redeem the rewards
  /// @return rewards amount of reward that is deposited to the ` strategy`
  function redeemRewards(bytes calldata data)
    public
    virtual
    override
    onlyIdleCDO
    nonReentrant
    returns (uint256[] memory rewards)
  {
    address[] memory _rewardTokens = rewardTokens;
    uint256 _rewardsLen = _rewardTokens.length;
    if (_rewardsLen == 0 || data.length == 0) {
      return rewards;
    }

    rewards = new uint256[](_rewardsLen);
    bytes[] memory claimDatas = abi.decode(data, (bytes[]));
    address reward;
    address rewardDistributor;
    uint256 claimable; 
    bytes32[] memory proof;

    for (uint256 i = 0; i < _rewardsLen; i++) {
      if (claimDatas[i].length == 0) {
        continue;
      }
      (reward, rewardDistributor, claimable, proof) = abi.decode(claimDatas[i], (address, address, uint256, bytes32[]));
      rewards[i] = _claimReward(IUniversalRewardsDistributor(rewardDistributor), reward, claimable, proof);
    }
  }

  /// @notice transfer rewards to IdleCDO, used if someone claims on behalf of the strategy
  /// or to transfer MORPHO once it's transferable
  /// @dev Anyone can call this function
  function transferRewards() external {
    address[] memory _rewardTokens = rewardTokens;
    address cdo = address(idleCDO);
    uint256 _rewardsLen = _rewardTokens.length;
    IERC20Detailed _reward;
    for (uint256 i = 0; i < _rewardsLen; i++) {
      _reward = IERC20Detailed(_rewardTokens[i]);
      uint256 bal = _reward.balanceOf(address(this));
      if (bal > 0 && (address(_reward) != MORPHO || morphoTransferable)) {
        _reward.safeTransfer(cdo, bal);
      }
    }
  }

  /// onlyOwner methods

  /// @dev set to array(0) to skip `redeemRewards`
  /// @param _rewardTokens array of reward tokens
  function setRewardTokens(address[] memory _rewardTokens) external onlyOwner {
    rewardTokens = _rewardTokens;
  }

  /// @dev used to upgrade mmSnippets contract
  /// @param _mmSnippets new snippets contract address
  function setMMSnippets(address _mmSnippets) external onlyOwner {
    mmSnippets = _mmSnippets;
  }

  /// @dev set morpho transferability
  /// @param _isTransferable true if MORPHO is transferable
  function setMorphoTransferable(bool _isTransferable) external onlyOwner {
    morphoTransferable = _isTransferable;
  }

  /// @dev set reward data for a reward token
  /// @param sender who submitted rewards data
  /// @param urd Universal Rewards Distributor address
  /// @param rewardToken reward token address
  /// @param marketId market id
  /// @param uniV3Path uni v3 path
  function setRewardData(address sender, address urd, address rewardToken, bytes32 marketId, bytes calldata uniV3Path) external onlyOwner {
    rewardsData[rewardToken] = RewardData(sender, urd, rewardToken, marketId, uniV3Path);
  }

  /// Internal methods

  /// @notice claim and transfer reward to idleCDO by verifying a merkle root
  /// @param distributor contract for distributing rewards
  /// @param reward reward address to claim
  /// @param claimable amount of reward to claim
  /// @param proof merkle proof
  function _claimReward(
    IUniversalRewardsDistributor distributor,
    address reward,
    uint256 claimable,
    bytes32[] memory proof
  ) internal returns (uint256 claimed) {
    uint256 balBefore = IERC20Detailed(reward).balanceOf(address(this));
    distributor.claim(address(this), reward, claimable, proof);
    claimed = IERC20Detailed(reward).balanceOf(address(this)) - balBefore;
    // MORPHO is not transferable atm
    if (reward != MORPHO || morphoTransferable) {
      IERC20Detailed(reward).safeTransfer(address(idleCDO), claimed);
    }
  }

  /// View methods

  /// @notice return the reward tokens
  function getRewardTokens() external override view returns (address[] memory) {
    return rewardTokens;  
  }

  /// @dev return always a value which is multiplied by 1e18
  /// eg for 2% apr -> 2*1e18
  function getApr() external view override returns (uint256 apr) {
    apr = getAprWithLiquidityChange(0, 0);
  }

  /// @dev return always a value which is multiplied by 1e18
  /// eg for 2% apr -> 2*1e18. Add and sub params are used off-chain
  /// to calculate the variation of the apr based on the liquidity added/removed
  function getAprWithLiquidityChange(uint256 add, uint256 sub) public view returns (uint256 apr) {
    // TODO update mm snippet to include add and sub
    // uint256 ratePerSecond = IMetamorphoSnippets(mmSnippets).supplyAPYVault(strategyToken, add, sub);

    uint256 ratePerSecond = IMetamorphoSnippets(mmSnippets).supplyAPYVault(strategyToken);
    // ratePerSecond is the rate per second scaled by 18 decimals
    // (eg 32943060 -> 32943060 * 24 * 3600 * 365 * 100 / 1e18 = 0.103% apr)
    apr = ratePerSecond * 365 days * 100 + getRewardsApr(add, sub);
  }

  /// @notice return the additional rewards apr
  /// @param add liquidity to add
  /// @param sub liquidity to remove
  /// @dev return a value multiplied by 1e18 eg for 2% apr -> 2*1e18. Add and sub params
  /// are used off-chain to calculate the variation of the apr based on the liquidity added/removed
  function getRewardsApr(uint256 add, uint256 sub) public view returns (uint256 apr) {
    IMMVault _mmVault = IMMVault(address(strategyToken));
    AprData memory _aprData = AprData(add, sub, _mmVault.withdrawQueueLength(), _mmVault.totalAssets());
    address[] memory _rewardTokens = rewardTokens;
    RewardData memory _rewardData;

    for (uint256 i = 0; i < _rewardTokens.length; i++) {
      _rewardData = rewardsData[_rewardTokens[i]];
      if (_rewardData.sender == address(0) || (_rewardData.rewardToken == MORPHO && !morphoTransferable)) {
        continue;
      }
      // for each market find the correct market associated the current rewardToken and calculate the apr 
      apr += _getRewardApr(_mmVault, _aprData, _rewardData.marketId, _quoteRewards(_rewardData));
    }
  }

  /// @notice return the additional rewards apr for a specific market
  /// @param _mmVault metamorpho vault
  /// @param _aprData apr data
  /// @param _targetMarketId target market id
  /// @param _rewardsInUnderlyings amount of rewards for the market, in underlyings
  /// @dev return a value multiplied by 1e18 eg for 2% apr -> 2*1e18
  /// @return apr additional rewards apr
  function _getRewardApr(
    IMMVault _mmVault, 
    AprData memory _aprData,
    bytes32 _targetMarketId,
    uint256 _rewardsInUnderlyings
  ) internal view returns (uint256 apr) {
    IMorpho.Market memory _market;
    IMorpho.Position memory _pos;
    bytes32 _marketId;
    uint256 _vaultShare;
    uint256 _assetsSuppliedByVault;
    uint256 _currPercOfAssetsForMarket;
    uint256 _newTotalSupplyAssets;

    // find the correct market associated with the current rewardToken and calculate the apr 
    for (uint256 m = 0; m < _aprData.marketsLen; m++) {
      _marketId = _mmVault.withdrawQueue(m);
      if (_marketId != _targetMarketId) {
        continue;
      }
      // get Morpho Blue market data
      _market = MORPHO_BLUE.market(_marketId);
      // get vault position data in the target market
      _pos = MORPHO_BLUE.position(_marketId, address(_mmVault));
      // get underlyings supplied by the vault in the target market
      // totalSupplyShares : totalSupplyAssets = supplyShares : assetsSuppliedByVault
      // => assetsSuppliedByVault = supplyShares * totalSupplyAssets / totalSupplyShares
      _assetsSuppliedByVault = _pos.supplyShares * _market.totalSupplyAssets / _market.totalSupplyShares;
      // get % (in EXP_SCALE) of vault assets that will go in this specific market once deposited (not all assets will go in the same market)
      _currPercOfAssetsForMarket = _assetsSuppliedByVault * EXP_SCALE / _aprData.totalAssets;
      // and scale add and sub values to maintain the proportion, calculates with vault totalAssets and assets supplied by vault
      _aprData.add = _aprData.add * _currPercOfAssetsForMarket / EXP_SCALE;
      _aprData.sub = _aprData.sub * _currPercOfAssetsForMarket / EXP_SCALE;
      // calculate new totalSupplyAssets with liquidity added/removed
      _newTotalSupplyAssets = _market.totalSupplyAssets + _aprData.add - _aprData.sub;
      // calculate vaultShare (% in EXP_SCALE) of the total market and simulate change of liquidity by using add and sub
      _vaultShare = (_assetsSuppliedByVault + _aprData.add - _aprData.sub) * EXP_SCALE / _newTotalSupplyAssets;
      // calculate vault rewards apr
      apr = _rewardsInUnderlyings * _currPercOfAssetsForMarket * _vaultShare * 100 / (_newTotalSupplyAssets * EXP_SCALE);
    }
  }

  /// @notice quote rewards per year to underlyings
  /// @param _rewardData reward data
  function _quoteRewards(RewardData memory _rewardData) internal view returns (uint256) {
    uint256 _oneReward = 10 ** uint256(IERC20Detailed(_rewardData.rewardToken).decimals());
    // quote 1 reward to underlyings then multiply by supplyRewardTokensPerYear
    return IStaticQuoter(UNI_V3_STATIC_QUOTER).quoteExactInput(_rewardData.uniV3Path, _oneReward) * 
      IRewardsEmissions(MORPHO_REWARDS_EMISSION).rewardsEmissions(
        _rewardData.sender,
        _rewardData.urd,
        _rewardData.rewardToken, 
        _rewardData.marketId
      ).supplyRewardTokensPerYear / _oneReward;
  }
}