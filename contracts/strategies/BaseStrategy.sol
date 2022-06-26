// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IIdleCDOStrategy.sol";
import "../interfaces/IERC20Detailed.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

abstract contract BaseStrategy is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IIdleCDOStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice one year, used to calculate the APR
    uint256 private constant YEAR = 365 days;

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

    /// @notice address of the IdleCDO
    address public idleCDO;

    /// @notice total underlying tokens staked
    uint256 public totalTokensStaked;

    /// @notice total underlying tokens locked
    uint256 public totalTokensLocked;

    /// @notice time when last deposit/redeem was made, used for calculating the APR
    uint256 public lastIndexedTime;

    ///@dev packed into the same storage slot as lastApr and blocks period.
    /// @notice latest harvest
    uint128 public latestHarvestBlock;

    /// @notice latest saved apr
    uint96 internal lastApr;

    /// @notice harvested tokens release delay
    uint32 public releaseBlocksPeriod;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        token = address(1);
    }

    /// @notice can be only called once
    /// @param _name name of this strategy ERC20 tokens
    /// @param _symbol symbol of this strategy ERC20 tokens
    /// @param _strategyToken address of the strategy token
    /// @param _underlyingToken address of the underlying token
    function _initialize(
        string memory _name,
        string memory _symbol,
        address _strategyToken,
        address _underlyingToken,
        address _owner
    ) internal initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        require(token == address(0), "Token is already initialized");

        //----- // -------//
        strategyToken = _strategyToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);

        // Set basic parameters
        lastIndexedTime = block.timestamp;
        releaseBlocksPeriod = 6400;

        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        //------//-------//

        transferOwnership(_owner);
    }

    /// @dev makes the actual deposit into the `strategy`
    /// @param _amount amount of tokens to deposit
    function _deposit(uint256 _amount)
        internal
        virtual
        returns (uint256 amountUsed, uint256 amountStaked);

    /// @dev makes the actual withdraw from the 'strategy'
    /// @return amountWithdrawn returns the amount withdrawn
    function _withdraw(uint256 _amountToWithdraw, address _destination)
        internal
        virtual
        returns (uint256 amountWithdrawn, uint256 amountUnstaked);

    /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
    /// @param _amount amount of `token` to deposit
    /// @return shares strategyTokens minted
    function deposit(uint256 _amount)
        external
        override
        onlyIdleCDO
        returns (uint256 shares)
    {
        if (_amount != 0) {
            // Get current price
            uint256 _price = price();
            // Send tokens to the strategy
            IERC20Detailed(token).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );

            totalTokensStaked += _amount;

            // Calls our internal deposit function
            (uint256 amountUsed, uint256 amountStaked) = _deposit(_amount);

            // Adjust with actual staked amount
            if (amountStaked != 0) {
                totalTokensStaked = totalTokensStaked - _amount + amountStaked;
            }
            // Mint shares
            shares = (amountUsed * oneToken) / _price;
            _mint(msg.sender, shares);
        }
    }

    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
    /// @param _shares amount of strategyTokens to redeem
    /// @return amountRedeemed  amount of underlyings redeemed
    function redeem(uint256 _shares)
        external
        override
        onlyIdleCDO
        returns (uint256 amountRedeemed)
    {
        if (_shares != 0) {
            amountRedeemed = _positionWithdraw(_shares, msg.sender, price(), 0);
        }
    }

    /// @notice Redeem Tokens
    /// @param _amount amount of underlying tokens to redeem
    /// @return amountRedeemed Amount of underlying tokens received
    function redeemUnderlying(uint256 _amount)
        external
        virtual
        onlyIdleCDO
        returns (uint256 amountRedeemed)
    {
        uint256 _price = price();
        uint256 _shares = (_amount * oneToken) / _price;
        if (_shares != 0) {
            amountRedeemed = _positionWithdraw(_shares, msg.sender, _price, 0);
        }
    }

    /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
    /// @param _shares amount of strategyTokens to redeem
    /// @param _destination The destination to send the output to
    /// @param _underlyingPerShare The precomputed shares per underlying
    /// @param _minUnderlying The min amount of output to produce. useful for mannualy harvesting
    /// @return amountWithdrawn amount of underlyings redeemed
    function _positionWithdraw(
        uint256 _shares,
        address _destination,
        uint256 _underlyingPerShare,
        uint256 _minUnderlying
    ) internal returns (uint256 amountWithdrawn) {
        uint256 amountNeeded = (_shares * _underlyingPerShare) / oneToken;

        // check-effect-interaction
        _burn(msg.sender, _shares);

        uint256 amountUnstaked;
        // Withdraw amount needed
        totalTokensStaked -= amountNeeded;
        (amountWithdrawn, amountUnstaked) = _withdraw(
            amountNeeded,
            _destination
        );

        // Adjust with actual unstaked amount
        if (amountNeeded > amountUnstaked) {
            totalTokensStaked =
                totalTokensStaked +
                amountNeeded -
                amountUnstaked;
        }

        // We revert if this call doesn't produce enough underlying
        // This security feature is useful in some edge cases
        require(amountWithdrawn >= _minUnderlying, "Not enough underlying");
    }

    /// @notice redeem the rewards
    /// @return rewards amount of reward that is deposited to the ` strategy`
    function redeemRewards(bytes calldata data)
        external
        virtual
        onlyIdleCDO
        nonReentrant
        returns (uint256[] memory rewards)
    {
        uint256 mintedUnderlyings;
        (mintedUnderlyings, rewards) = _redeemRewards(data);

        // reinvest the generated/minted underlying to the the `strategy`
        if (mintedUnderlyings != 0) {
            uint256 underlyingsStaked = _reinvest(mintedUnderlyings);
            require(underlyingsStaked <= mintedUnderlyings, "sanity check");

            // save the block in which rewards are swapped and the amount
            latestHarvestBlock = uint128(block.number);
            totalTokensLocked = underlyingsStaked;
            totalTokensStaked += underlyingsStaked;

            // update the apr after claiming the rewards
            _updateApr(underlyingsStaked);
        }
    }

    /// @dev reinvest underlyings` to the `strategy`
    ///      this method should be used in the `_redeemRewards` method
    ///      Ussually don't mint new shares.
    function _reinvest(uint256 underlyings)
        internal
        virtual
        returns (uint256 underlyingsStaked)
    {
        (, underlyingsStaked) = _deposit(underlyings);
    }

    function _redeemRewards(bytes calldata data)
        internal
        virtual
        returns (uint256 mintedUnderlyings, uint256[] memory rewards);

    /// @notice update last saved apr
    /// @param _gain amount of underlying tokens to mint/redeem
    function _updateApr(uint256 _gain) internal {
        uint256 priceIncrease = (_gain * oneToken) / totalSupply();
        lastApr = uint96(
            priceIncrease * (YEAR / (block.timestamp - lastIndexedTime)) * 100
        ); // prettier-ignore
        lastIndexedTime = block.timestamp;
    }

    /// @dev deprecated method
    /// @notice pull stkedAave
    function pullStkAAVE() external override returns (uint256 pulledAmount) {}

    /// @notice net price in underlyings of 1 strategyToken
    /// @return _price
    function price() public view virtual override returns (uint256 _price) {
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            _price = oneToken;
        } else {
            _price =
                ((totalTokensStaked - _lockedTokens()) * oneToken) /
                _totalSupply;
        }
    }

    function _lockedTokens() internal view returns (uint256 _locked) {
        uint256 _totalLockedTokens = totalTokensLocked;
        uint256 _releaseBlocksPeriod = releaseBlocksPeriod;
        uint256 _blocksSinceLastHarvest = block.number - latestHarvestBlock;

        if (
            _totalLockedTokens != 0 &&
            _blocksSinceLastHarvest < _releaseBlocksPeriod
        ) {
            // progressively release harvested rewards
            _locked = (_totalLockedTokens * (_releaseBlocksPeriod - _blocksSinceLastHarvest)) / _releaseBlocksPeriod; // prettier-ignore
        }
    }

    function getApr() external view returns (uint256 apr) {
        apr = lastApr;
    }

    function setReleaseBlocksPeriod(uint32 _releaseBlocksPeriod)
        external
        onlyOwner
    {
        require(_releaseBlocksPeriod != 0, "IS_0");
        releaseBlocksPeriod = _releaseBlocksPeriod;
    }

    /// @notice This contract should not have funds at the end of each tx (except for stkAAVE), this method is just for leftovers
    /// @dev Emergency method
    /// @param _token address of the token to transfer
    /// @param value amount of `_token` to transfer
    /// @param _to receiver address
    function transferToken(
        address _token,
        uint256 value,
        address _to
    ) external onlyOwner nonReentrant {
        IERC20Detailed(_token).safeTransfer(_to, value);
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
