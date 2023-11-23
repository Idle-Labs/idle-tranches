// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/morpho/IMorphoSupplyVault.sol";
import "../../interfaces/morpho/IMorphoAaveV2Lens.sol";
import "../../interfaces/morpho/IMorphoCompoundLens.sol";
import "../../interfaces/morpho/IRewardsDistributor.sol";
import "../../interfaces/morpho/IURD.sol";
import "../ERC4626Strategy.sol";

contract MetaMorphoStrategy is ERC4626Strategy {
  using SafeERC20Upgradeable for IERC20Detailed;

  //// @notice MORPHO governance token
  IERC20Detailed internal constant MORPHO = IERC20Detailed(0x9994E35Db50125E0DF82e4c2dde62496CE330999);

  /// @notice reward token address (e.g. MORPHO, COMP, ...)
  address[] public rewardTokens;

  /// @notice reward distributors
  IURD[] public rewardDistributors;

  /// @notice MORPHO transferability
  bool public morphoTransferable;

  /// Initialization

  /// @notice initialize the strategy
  /// @param _strategyToken strategy token address
  /// @param _token underlying token address
  /// @param _owner owner address
  /// @param _rewardTokens array of reward tokens
  /// @param _distributors array of reward distributors
  function initialize(
    address _strategyToken,
    address _token,
    address _owner,
    address[] memory _rewardTokens,
    address[] memory _distributors
  ) public {
    _initialize(_strategyToken, _token, _owner);

    for (uint256 i = 0; i < _rewardTokens.length; i++) {
      rewardTokens.push(_rewardTokens[i]);
      rewardDistributors.push(IURD(_distributors[i]));
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
    if (_rewardsLen == 0) {
      return rewards;
    }

    rewards = new uint256[](_rewardsLen);
    bytes[] memory claimDatas = abi.decode(data, (bytes[]));
    address reward;
    uint256 claimable; 
    bytes32[] memory proof;
    IURD[] memory _rewardDistributors = rewardDistributors;

    for (uint256 i = 0; i < _rewardsLen; i++) {
      if (claimDatas[i].length == 0) {
        continue;
      }
      (reward, claimable, proof) = abi.decode(claimDatas[i], (address, uint256, bytes32[]));
      rewards[i] = _claimReward(_rewardDistributors[i], reward, claimable, proof);
    }
  }

  /// @notice transfer MORPHO to the idleCDO
  /// @dev Anyone can call this function
  function transferMorpho() public {
    uint256 bal = MORPHO.balanceOf(address(this));
    MORPHO.safeTransfer(address(idleCDO), bal);
  }

  /// onlyOwner methods

  /// @dev set to array(0) to skip `redeemRewards`
  /// @param _rewardTokens array of reward tokens
  function setRewardTokens(address[] memory _rewardTokens) external onlyOwner {
    rewardTokens = _rewardTokens;
  }

  /// @dev set morpho transferability
  /// @param _isTransferable true if MORPHO is transferable
  function setMorphoTransferable(bool _isTransferable) external onlyOwner {
    morphoTransferable = _isTransferable;
  }

  /// Internal methods

  /// @notice claim and transfer reward to idleCDO by verifying a merkle root
  /// @param distributor contract for distributing rewards
  /// @param reward reward address to claim
  /// @param claimable amount of reward to claim
  /// @param proof merkle proof
  function _claimReward(
    IURD distributor,
    address reward,
    uint256 claimable,
    bytes32[] memory proof
  ) internal returns (uint256 claimed) {
    uint256 balBefore = IERC20Detailed(reward).balanceOf(address(this));
    distributor.claim(address(this), reward, claimable, proof);
    claimed = IERC20Detailed(reward).balanceOf(address(this)) - balBefore;
    // MORPHO is not transferable atm
    if (reward != address(MORPHO) || morphoTransferable) {
      IERC20Detailed(reward).safeTransfer(address(idleCDO), claimed);
    }
  }

  /// View methods

  /// @notice return the reward tokens
  function getRewardTokens() external override view returns (address[] memory) {
    return rewardTokens;
  }

  // TODO
  /// @dev return always a value which is multiplied by 1e18
  /// eg for 2% apr -> 2*1e18
  function getApr() external view override returns (uint256 apr) {
    // This was for morpho v2 optimizer
    // // The supply rate per year experienced on average on the given market (in ray).
    // (uint256 ratePerYear, , ) = LENS.getAverageSupplyRatePerYear(poolToken);
    // apr = ratePerYear / 1e7; // ratePerYear / 1e9 * 100
  }
}