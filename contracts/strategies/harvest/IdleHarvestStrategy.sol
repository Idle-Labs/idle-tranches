// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/harvest/IHarvestVault.sol";
import "../../interfaces/harvest/IRewardPool.sol";

import "../../interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract IdleHarvestStrategy is Initializable, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice underlying token address (ex: DAI)
    address public override token;

    /// @notice strategy token address (ex: fDAI)
    address public override strategyToken;

    /// @notice decimals of the underlying asset
    uint256 public override tokenDecimals;

    /// @notice one underlying token
    uint256 public override oneToken;

    /// @notice underlying ERC20 token contract
    IERC20Detailed public underlyingToken;

    /// @notice address of the reward pool
    address public rewardPool;

    /// @notice amount last indexed for calculating APR
    uint256 public lastIndexAmount;

    /// @notice time when last deposit/redeem was made, used for calculating the APR
    uint256 public lastIndexedTime;

    /// @notice address of the IdleCDO
    address public idleCDO;

    /// @notice one year, used to calculate the APR
    uint256 public constant YEAR = 365 days;

    /// @notice address of the governance token. (Here FARM)
    address public govToken;

    /// @notice uniswap router path that should be used to swap the tokens
    address[] public uniswapRouterPath;

    /// @notice interface derived from uniswap router
    IUniswapV2Router02 public uniswapV2Router02;

    /// @notice latest saved apr
    uint256 public lastApr;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice can be only called once
    /// @param _strategyToken address of the strategy token
    /// @param _underlyingToken address of the underlying token
    /// @param _rewardPool address of the reward pool
    /// @param _uniswapV2Router02 address of the uniswap router
    /// @param _routerPath path to swap governance tokens
    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _rewardPool,
        address _uniswapV2Router02,
        address[] calldata _routerPath,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        strategyToken = _strategyToken;
        rewardPool = _rewardPool;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        govToken = IRewardPool(rewardPool).rewardToken();

        ERC20Upgradeable.__ERC20_init("Idle Harvest Strategy Token", string(abi.encodePacked("idleHS", underlyingToken.symbol())));
        //------//-------//

        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);
        uniswapRouterPath = _routerPath;

        transferOwnership(_owner);
        lastIndexedTime = block.timestamp;
    }

    /// @notice redeem the rewards. Claims reward as per the _extraData
    /// @return rewards amount of reward that is deposited to vault
    function redeemRewards(bytes calldata) external override onlyIdleCDO returns (uint256[] memory rewards) {
        IRewardPool(rewardPool).getReward();
        rewards = new uint256[](1);
        rewards[0] = IERC20Detailed(govToken).balanceOf(address(this));
        IERC20Detailed(govToken).safeTransfer(msg.sender, rewards[0]);
    }

    /// @notice unused in harvest strategy
    function pullStkAAVE() external pure override returns (uint256) {
        return 0;
    }

    /// @notice return the price from the strategy token contract
    /// @return price
    function price() public view override returns (uint256) {
        return IHarvestVault(strategyToken).getPricePerFullShare();
    }

    /// @notice Get the reward token
    /// @return array of reward token
    function getRewardTokens() external view override returns (address[] memory) {
        address[] memory govTokens = new address[](1);
        govTokens[0] = govToken;
        return govTokens;
    }

    function getApr() external view returns (uint256) {
        return lastApr;
    }

    /// @notice update last saved apr
    /// @param _amount amount of underlying tokens to mint/redeem
    function _updateApr(int256 _amount) internal {
        uint256 rawBalance = IRewardPool(rewardPool).balanceOf(address(this));
        uint256 expectedUnderlyingAmount = (price() * rawBalance) / oneToken;
        uint256 _lastIndexAmount = lastIndexAmount;
        if (lastIndexAmount > 0) {
            uint256 diff = expectedUnderlyingAmount > _lastIndexAmount ? expectedUnderlyingAmount - _lastIndexAmount : 0;
            uint256 gainPerc = ((diff) * 10**20) / _lastIndexAmount;
            lastApr = (YEAR / (block.timestamp - lastIndexedTime)) * gainPerc;
        }
        lastIndexedTime = block.timestamp;
        lastIndexAmount = uint256(int256(expectedUnderlyingAmount) + _amount);
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of strategy tokens to redeem
    /// @return _val Amount of underlying tokens received
    function redeem(uint256 _amount) external override onlyIdleCDO returns (uint256 _val) {
        if (_amount > 0) {
            _val = _redeem(_amount, price());
        }
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of underlying tokens to redeem
    /// @return _val Amount of underlying tokens received
    function redeemUnderlying(uint256 _amount) external onlyIdleCDO returns (uint256 _val) {
        if (_amount > 0) {
            uint256 _price = price();
            uint256 _strategyTokens = (_amount * oneToken) / _price;
            _val = _redeem(_strategyTokens, _price);
        }
    }

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of strategy tokens
    /// @return Amount of underlying tokens received
    function _redeem(uint256 _amount, uint256 _price) internal returns (uint256) {
        uint256 redeemed = (_amount * _price) / oneToken;
        _updateApr(-int256(redeemed));

        lastIndexedTime = block.timestamp;
        _burn(msg.sender, _amount);
        IRewardPool(rewardPool).withdraw(_amount);
        IERC20Detailed _underlyingToken = underlyingToken;
        uint256 balanceBefore = _underlyingToken.balanceOf(address(this));
        IHarvestVault(strategyToken).withdraw(_amount);
        uint256 balanceAfter = _underlyingToken.balanceOf(address(this));
        uint256 balanceReceived = balanceAfter - balanceBefore;
        _underlyingToken.safeTransfer(msg.sender, balanceReceived);
        return balanceReceived;
    }

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 minted) {
        if (_amount > 0) {
            underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
            minted = _depositToVault(_amount);
        }
    }

    /// @notice internal function to deposit the funds to the vault
    /// @param _amount Amount of underlying tokens to deposit
    function _depositToVault(uint256 _amount) internal returns (uint256) {
        _updateApr(int256(_amount));
        address _strategyToken = strategyToken;
        underlyingToken.safeApprove(_strategyToken, _amount);
        IHarvestVault(_strategyToken).deposit(_amount);
        lastIndexedTime = block.timestamp;

        IERC20Detailed _strategyTokenContract = IERC20Detailed(_strategyToken);
        uint256 interestTokenAvailable = _strategyTokenContract.balanceOf(address(this));
        _strategyTokenContract.safeApprove(rewardPool, interestTokenAvailable);

        IRewardPool(rewardPool).stake(interestTokenAvailable);

        _mint(msg.sender, interestTokenAvailable);
        return interestTokenAvailable;
    }

    /// @notice Change idleCDO address
    /// @dev operation can be only done by the owner of the contract
    function changeIdleCDO(address _idleCDO) external onlyOwner {
        idleCDO = _idleCDO;
    }

    /// @notice allow to update whitelisted address
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        idleCDO = _cdo;
    }

    function changeUniswapRouterPath(address[] memory newPath) public onlyOwner {
        uniswapRouterPath = newPath;
    }

    /// @notice Modifier to make sure that caller os only the idleCDO contract
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
