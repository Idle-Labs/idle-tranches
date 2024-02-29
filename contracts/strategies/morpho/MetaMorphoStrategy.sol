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

error InvalidPosition();

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

  /// @notice [DEPRECATED] MORPHO transferability
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
    uint256 withdrawLen;
    uint256 supplyLen;
    uint256 totalAssets;
  }

  /// @notice reward token data
  mapping(address => RewardData[]) public rewardsData;

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
    address cdo = idleCDO;
    address reward;
    address rewardDistributor;
    uint256 claimable; 
    bytes32[] memory proof;

    for (uint256 i = 0; i < _rewardsLen; i++) {
      if (claimDatas[i].length == 0) {
        continue;
      }
      (reward, rewardDistributor, claimable, proof) = abi.decode(claimDatas[i], (address, address, uint256, bytes32[]));
      rewards[i] = _claimReward(IUniversalRewardsDistributor(rewardDistributor), cdo, reward, claimable, proof);
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

  /// @dev set reward data for a reward token
  /// @param sender who submitted rewards data
  /// @param urd Universal Rewards Distributor address
  /// @param rewardToken reward token address
  /// @param marketId market id
  /// @param uniV3Path uni v3 path
  function setRewardData(uint256 idx, address sender, address urd, address rewardToken, bytes32 marketId, bytes calldata uniV3Path) external onlyOwner {
    uint256 len = rewardsData[rewardToken].length;
    if (idx > len) {
      revert InvalidPosition();
    }

    RewardData memory _rewardData = RewardData(sender, urd, rewardToken, marketId, uniV3Path);

    // add new element
    if (idx == len) {
      rewardsData[rewardToken].push(_rewardData);
      return;
    }
    // replace existing element
    rewardsData[rewardToken][idx] = _rewardData;
  }

  /// Internal methods

  /// @notice claim and transfer reward to idleCDO by verifying a merkle root
  /// @param distributor contract for distributing rewards
  /// @param cdo idleCDO address
  /// @param reward reward address to claim
  /// @param claimable amount of reward to claim
  /// @param proof merkle proof
  function _claimReward(
    IUniversalRewardsDistributor distributor,
    address cdo,
    address reward,
    uint256 claimable,
    bytes32[] memory proof
  ) internal returns (uint256 claimed) {
    uint256 balBefore = IERC20Detailed(reward).balanceOf(cdo);
    distributor.claim(cdo, reward, claimable, proof);
    claimed = IERC20Detailed(reward).balanceOf(cdo) - balBefore;
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
    uint256 ratePerSecond = IMetamorphoSnippets(mmSnippets).supplyAPRVault(strategyToken, add, sub);
    // ratePerSecond is the rate per second scaled by 18 decimals
    // (eg 32943060 -> 32943060 * 24 * 3600 * 365 * 100 / 1e18 = 0.103% apr)
    apr = ratePerSecond * 365 days * 100 + getRewardsApr(add, sub);
  }

  /// @notice return the additional rewards apr
  /// @param add liquidity to add
  /// @param sub liquidity to remove
  /// @dev return a value multiplied by 1e18 eg for 2% apr -> 2*1e18. Add and sub params
  /// are used off-chain to calculate the variation of the apr based on the liquidity added/removed
  /// WARN: ensure that mmVault.maxWithdraw(idleCDO) + add < sub if sub > 0 before calling this method
  /// this is not done in this method to avoid gas costs and another loop made in maxWithdraw call
  function getRewardsApr(uint256 add, uint256 sub) public view returns (uint256 apr) {
    IMMVault _mmVault = IMMVault(address(strategyToken));
    uint256 _totalAssets = _mmVault.totalAssets();
    if (sub > 0 && _totalAssets + add < sub) {
      return 0;
    }
    _totalAssets = _totalAssets + add - sub;
    AprData memory _aprData = AprData(add, sub, _mmVault.withdrawQueueLength(), _mmVault.supplyQueueLength(), _totalAssets);
    address[] memory _rewardTokens = rewardTokens;
    RewardData[] memory _rewardDatas;
    RewardData memory _rewardData;

    // loop through all the reward tokens
    for (uint256 i = 0; i < _rewardTokens.length; i++) {
      // get all the rewards data for the current reward token
      _rewardDatas = rewardsData[_rewardTokens[i]];
      // loop through all the rewards data for the current reward token
      for (uint256 j = 0; j < _rewardDatas.length; j++) {
        _rewardData = _rewardDatas[j];
        if (_rewardData.sender == address(0) || (_rewardData.rewardToken == MORPHO && _rewardData.uniV3Path.length == 0)) {
          continue;
        }
        // for each market find the correct market associated the current rewardToken and calculate the apr 
        apr += _getRewardApr(_mmVault, _aprData, _rewardData.marketId, _quoteRewards(_rewardData));
      }
    }
  }

  /// @notice return the additional vault reward apr for a specific market
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
    uint256 _totalSupplyAssets;

    // find the correct market associated with the current rewardToken and calculate the apr 
    for (uint256 m = 0; m < _aprData.withdrawLen; m++) {
      _marketId = _mmVault.withdrawQueue(m);
      if (_marketId != _targetMarketId) {
        continue;
      }
      // get Morpho Blue market data
      _market = MORPHO_BLUE.market(_marketId);
      // get vault position data in the target market
      _pos = MORPHO_BLUE.position(_marketId, address(_mmVault));
      // calc how much of `add` will be added to this market
      if (_aprData.add > 0) {
        // we overwrite _aprData.add with the liquidity added as this path is touched only once for target market
        _aprData.add = _calcMarketAdd(_mmVault, _marketId, _aprData.supplyLen, _aprData.add);
      }
      // calc how much of `sub` will be removed from this market
      if (_aprData.sub > 0) {
        // we overwrite _aprData.sub with the liquidity removed as this path is touched only once for target market
        _aprData.sub = _calcMarketSub(_mmVault, _marketId, _aprData.withdrawLen, _aprData.sub);
      }
      // get underlyings supplied by the vault in the target market
      // totalSupplyShares : totalSupplyAssets = supplyShares : assetsSuppliedByVault
      // => assetsSuppliedByVault = supplyShares * totalSupplyAssets / totalSupplyShares
      _assetsSuppliedByVault = _pos.supplyShares * _market.totalSupplyAssets / _market.totalSupplyShares;
      // if the vault is removing more liquidity than it has or the market has, apr is 0
      if (_aprData.sub > 0 && (
        (_market.totalSupplyAssets + _aprData.add) <= _aprData.sub || 
        (_assetsSuppliedByVault + _aprData.add) <= _aprData.sub)
      ) {
        apr = 0;
        continue;
      }
      // simulate change of liquidity by using add and sub
      _assetsSuppliedByVault = _assetsSuppliedByVault + _aprData.add - _aprData.sub;
      // calculate new totalSupplyAssets with liquidity added/removed
      _totalSupplyAssets = _market.totalSupplyAssets + _aprData.add - _aprData.sub;
      // calculate vaultShare (% in EXP_SCALE) of the total market and simulate change of liquidity by using add and sub
      _vaultShare = _assetsSuppliedByVault * EXP_SCALE / _totalSupplyAssets;
      // calculate vault rewards apr
      apr = _rewardsInUnderlyings * _vaultShare * 100 / _aprData.totalAssets;
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

  /// @notice calculate how much of vault `_add` amount will be added to this market
  /// @param _mmVault metamorpho vault
  /// @param _targetMarketId target market id
  /// @param _supplyQueueLen supply queue length
  /// @param _add amount of liquidity to add
  function _calcMarketAdd(
    IMMVault _mmVault,
    bytes32 _targetMarketId,
    uint256 _supplyQueueLen,
    uint256 _add
  ) internal view returns (uint256) {
    uint256 _assetsSuppliedByVault;
    uint184 _marketCap;
    bytes32 _currMarketId;
    IMorpho.Market memory _market;
    IMorpho.Position memory _pos;

    // loop throuh supplyQueue, starting from the first market, and see how much will
    // be deposited in target market
    for (uint256 i = 0; i < _supplyQueueLen; i++) {
      _currMarketId = _mmVault.supplyQueue(i);
      _market = MORPHO_BLUE.market(_currMarketId);
      _pos = MORPHO_BLUE.position(_currMarketId, address(_mmVault));
      if (_market.totalSupplyShares == 0) {
        _assetsSuppliedByVault = 0;
      } else {
        _assetsSuppliedByVault = _pos.supplyShares * _market.totalSupplyAssets / _market.totalSupplyShares;
      }
      // get max depositable amount for this market
      (_marketCap,,) = _mmVault.config(_currMarketId);
      uint256 _maxDeposit;
      if (_assetsSuppliedByVault < uint256(_marketCap)) {
        _maxDeposit = uint256(_marketCap) - _assetsSuppliedByVault;
      }
      // If this is the target market, return the current _add value, eventually
      // reduced to the max depositable amount
      if (_currMarketId == _targetMarketId) {
        if (_add > _maxDeposit) {
          _add = _maxDeposit;
        }
        break;
      }
      // If this is not the target market, check if we can deposit all the _add amount
      // in this market, otherwise continue the loop and subtract the max depositable
      if (_add > _maxDeposit) {
        _add -= _maxDeposit;
      } else {
        _add = 0;
        break;
      }
    }

    return _add;
  }

  /// @notice calculate how much of vault `_sub` amount will be removed from target market
  /// @param _mmVault metamorpho vault
  /// @param _targetMarketId target market id
  /// @param _withdrawQueueLen withdraw queue length
  /// @param _sub liquidity to remove
  function _calcMarketSub(
    IMMVault _mmVault, 
    bytes32 _targetMarketId,
    uint256 _withdrawQueueLen,
    uint256 _sub
  ) internal view returns (uint256) {
    IMorpho.Market memory _market;
    IMorpho.Position memory _position;
    bytes32 _currMarketId;
    uint256 _availableLiquidity;
    uint256 _vaultAssets;
    uint256 _withdrawable;
    // loop throuh withdrawQueue, and see how much will be redeemed in target market
    for (uint256 i = 0; i < _withdrawQueueLen; i++) {
      _currMarketId = _mmVault.withdrawQueue(i);
      _market = MORPHO_BLUE.market(_currMarketId);
      _position = MORPHO_BLUE.position(_currMarketId, address(_mmVault));
      // get available liquidity for this market
      _availableLiquidity = _market.totalSupplyAssets - _market.totalBorrowAssets;
      if (_availableLiquidity == 0 || _market.totalSupplyShares == 0) {
        _withdrawable = 0;
      } else {
        // get assets deposited by the vault in the maket
        _vaultAssets = _position.supplyShares * _market.totalSupplyAssets / _market.totalSupplyShares;
        // get max withdrawable amount for this market (min between available liquidity and vault assets)
        _withdrawable = _vaultAssets > _availableLiquidity ? _availableLiquidity : _vaultAssets;
      }
      // If this is the target market, return the current _sub value, eventually
      // reduced to the max withdrawable amount
      if (_currMarketId == _targetMarketId) {
        if (_sub > _withdrawable) {
          _sub = _withdrawable;
        }
        break;
      }
      // If this is not the target market, check if we can withdraw all the _sub amount
      // in this market, otherwise continue the loop and subtract the available liquidity
      if (_sub > _withdrawable) {
        _sub -= _withdrawable;
      } else {
        _sub = 0;
        break;
      }
    }

    return _sub;
  }
}