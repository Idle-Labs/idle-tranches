pragma solidity 0.8.10;

import "./utils/ReentrancyGuardInitialize.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
contract StakingRewards is ReentrancyGuardInitialize, Ownable, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  IERC20 public rewardsToken;
  IERC20 public stakingToken;
  uint256 public periodFinish;
  uint256 public rewardRate;
  uint256 public rewardsDuration;
  uint256 public lastUpdateTime;
  uint256 public rewardPerTokenStored;
  address public rewardsDistribution;

  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewards;

  uint256 private _totalSupply;
  mapping(address => uint256) private _balances;
  bool public shouldTransfer;

  /* ========== INITIALIZE ========== */

  function initialize(
    address _rewardsDistribution,
    address _rewardsToken,
    address _stakingToken,
    address _owner,
    bool _shouldTransfer
  ) public {
    require(address(stakingToken) == address(0), 'Initialized');

    rewardsToken = IERC20(_rewardsToken);
    stakingToken = IERC20(_stakingToken);
    rewardsDistribution = _rewardsDistribution;
    shouldTransfer = _shouldTransfer;
    rewardsDuration = 1 days;
    _transferOwnership(_owner);
    // ReentrancyGuardInitialize initialization
    _status = _NOT_ENTERED;
  }

  /* ========== VIEWS ========== */

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  function lastTimeRewardApplicable() public view returns (uint256) {
    return block.timestamp < periodFinish ? block.timestamp : periodFinish;
  }

  function rewardPerToken() public view returns (uint256) {
    if (_totalSupply == 0) {
      return rewardPerTokenStored;
    }
    return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _totalSupply);
  }

  function earned(address account) public view returns (uint256) {
    return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
  }

  function getRewardForDuration() external view returns (uint256) {
    return rewardRate * rewardsDuration;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  // Add stakeFor to allow IdleCDO to stake tranche tokens received as fees for the feeReceiver
  function stakeFor(address _user, uint256 amount) external {
    require(msg.sender == rewardsDistribution, 'Only rewards distribution can stake for user');
    _stake(_user, msg.sender, amount);
  }

  function stake(uint256 amount) external {
    _stake(msg.sender, msg.sender, amount);
  }
  function _stake(address _user, address _payer, uint256 amount) internal nonReentrant whenNotPaused updateReward(_user) {
    require(amount > 0, "Cannot stake 0");
    _totalSupply += amount;
    _balances[_user] += amount;
    stakingToken.safeTransferFrom(_payer, address(this), amount);
    emit Staked(_user, amount);
  }

  function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
    require(amount > 0, "Cannot withdraw 0");
    _totalSupply -= amount;
    _balances[msg.sender] -= amount;
    stakingToken.safeTransfer(msg.sender, amount);
    emit Withdrawn(msg.sender, amount);
  }

  function getReward() public nonReentrant updateReward(msg.sender) {
    uint256 reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      rewardsToken.safeTransfer(msg.sender, reward);
      emit RewardPaid(msg.sender, reward);
    }
  }

  function exit() external {
    withdraw(_balances[msg.sender]);
    getReward();
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  // Changed from 
  // function notifyRewardAmount(uint256 reward)
  // to 
  // function depositReward(address, uint256 reward)
  // for compatibility reason with IdleCDO. Added also a transferFrom to get the reward amount
  function depositReward(address, uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
    if (shouldTransfer) {
      rewardsToken.safeTransferFrom(msg.sender, address(this), reward);
    }

    if (block.timestamp >= periodFinish) {
      rewardRate = reward / rewardsDuration;
    } else {
      uint256 remaining = periodFinish - block.timestamp;
      uint256 leftover = remaining * rewardRate;
      rewardRate = (reward + leftover) / rewardsDuration;
    }

    // Ensure the provided reward amount is not more than the balance in the contract.
    // This keeps the reward rate in the right range, preventing overflows due to
    // very high values of rewardRate in the earned and rewardsPerToken functions;
    // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
    uint balance = rewardsToken.balanceOf(address(this));
    require(rewardRate <= balance / rewardsDuration, "Provided reward too high");

    lastUpdateTime = block.timestamp;
    periodFinish = block.timestamp + rewardsDuration;

    emit RewardAdded(reward);
  }

  // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
  function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
    require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
    IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    emit Recovered(tokenAddress, tokenAmount);
  }

  function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
    require(
      block.timestamp > periodFinish,
      "Previous rewards period must be complete before changing the duration for the new period"
    );
    rewardsDuration = _rewardsDuration;
    emit RewardsDurationUpdated(rewardsDuration);
  }

  function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
    rewardsDistribution = _rewardsDistribution;
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }


  /* ========== MODIFIERS ========== */

  modifier updateReward(address account) {
    rewardPerTokenStored = rewardPerToken();
    lastUpdateTime = lastTimeRewardApplicable();
    if (account != address(0)) {
        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
    _;
  }

  modifier onlyRewardsDistribution() {
    require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
    _;
  }

  /* ========== EVENTS ========== */

  event RewardAdded(uint256 reward);
  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
  event RewardsDurationUpdated(uint256 newDuration);
  event Recovered(address token, uint256 amount);
}