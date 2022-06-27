// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../interfaces/IIdleCDOStrategy.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../../interfaces/clearpool/IPoolFactory.sol";
import "../../interfaces/clearpool/IPoolMaster.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract IdleClearpoolStrategy is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IIdleCDOStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice underlying token address (pool currency for Clearpool)
    address public override token;

    /// @notice strategy token address (lending pool address for Clearpool)
    address public override strategyToken;

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

    /// @notice address of the governance token (here CPOOL)
    address public govToken;

    /// @notice latest saved apr
    uint256 public lastApr;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice can be only called once
    /// @param _strategyToken address of the strategy token (lending pool)
    /// @param _underlyingToken address of the underlying token (pool currency)
    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        strategyToken = _strategyToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        govToken = IPoolMaster(_strategyToken).factory().cpool();

        ERC20Upgradeable.__ERC20_init(
            "Idle Clearpool Strategy Token",
            string(abi.encodePacked("idleCPOOL", underlyingToken.symbol()))
        );
        //------//-------//

        transferOwnership(_owner);
    }

    /// @notice redeem the rewards. Claims reward as per the _extraData
    /// @return rewards amount of reward that is deposited to vault
    function redeemRewards(bytes calldata)
        external
        override
        onlyIdleCDO
        returns (uint256[] memory rewards)
    {
        address pool = strategyToken;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        IPoolMaster(pool).factory().withdrawReward(pools);

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
        // Convert clearpool precision (18 decimals) to price with idle precision (token decimals)
        return (_price() * oneToken) / 10**18;
    }

    /// @notice Internal price function (uses Clearpool's precision)
    function _price() private view returns (uint256) {
        return IPoolMaster(strategyToken).getCurrentExchangeRate();
    }

    /// @notice Get the reward token
    /// @return array of reward token
    function getRewardTokens()
        external
        view
        override
        returns (address[] memory)
    {
        address[] memory govTokens = new address[](1);
        govTokens[0] = govToken;
        return govTokens;
    }

    function getApr() external view returns (uint256) {
        return IPoolMaster(strategyToken).getSupplyRate() * 100;
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of strategy tokens to redeem
    /// @return Amount of underlying tokens received
    function redeem(uint256 _amount)
        external
        override
        onlyIdleCDO
        returns (uint256)
    {
        if (_amount > 0) {
            return _redeem(_amount);
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
            uint256 _strategyTokens = (_amount * 10**18) / _price();
            return _redeem(_strategyTokens);
        }
        return 0;
    }

    /// @notice Internal function to redeem the underlying tokens
    /// @param _amount Amount of strategy tokens
    /// @return Amount of underlying tokens received
    function _redeem(uint256 _amount) internal returns (uint256) {
        _burn(msg.sender, _amount);
        IERC20Detailed _underlyingToken = underlyingToken;
        uint256 balanceBefore = _underlyingToken.balanceOf(address(this));
        IPoolMaster(strategyToken).redeem(_amount);
        uint256 balanceAfter = _underlyingToken.balanceOf(address(this));
        uint256 balanceReceived = balanceAfter - balanceBefore;
        _underlyingToken.safeTransfer(msg.sender, balanceReceived);
        return balanceReceived;
    }

    /// @notice Deposit the underlying token to vault
    /// @param _amount number of tokens to deposit
    /// @return minted number of reward tokens minted
    function deposit(uint256 _amount)
        external
        override
        onlyIdleCDO
        returns (uint256 minted)
    {
        if (_amount > 0) {
            underlyingToken.safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            minted = _depositToVault(_amount);
        }
    }

    /// @notice internal function to deposit the funds to the vault
    /// @param _amount Amount of underlying tokens to deposit
    function _depositToVault(uint256 _amount) internal returns (uint256) {
        address _strategyToken = strategyToken;
        underlyingToken.safeApprove(_strategyToken, _amount);

        uint256 balanceBefore = IERC20Detailed(_strategyToken).balanceOf(
            address(this)
        );
        IPoolMaster(_strategyToken).provide(_amount);
        uint256 balanceAfter = IERC20Detailed(_strategyToken).balanceOf(
            address(this)
        );

        _mint(msg.sender, balanceAfter - balanceBefore);

        return balanceAfter - balanceBefore;
    }

    /// @notice allow to update whitelisted address
    function setWhitelistedCDO(address _cdo) external onlyOwner {
        require(_cdo != address(0), "IS_0");
        idleCDO = _cdo;
    }

    /// @notice Modifier to make sure that caller os only the idleCDO contract
    modifier onlyIdleCDO() {
        require(idleCDO == msg.sender, "Only IdleCDO can call");
        _;
    }
}
