// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../BaseStrategy.sol";

import "../../interfaces/euler/IEToken.sol";
import "../../interfaces/euler/IDToken.sol";
import "../../interfaces/euler/IMarkets.sol";
import "../../interfaces/euler/IExec.sol";
import "../../interfaces/euler/IEulerGeneralView.sol";
import "../../interfaces/euler/IEulDistributor.sol";

import "forge-std/Test.sol";

contract IdleLeveragedEulerStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice Euler markets contract address
    IMarkets internal constant EULER_MARKETS = IMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);

    /// @notice Euler general view contract address
    IEulerGeneralView internal constant EULER_GENERAL_VIEW =
        IEulerGeneralView(0xACC25c4d40651676FEEd43a3467F3169e3E68e42);

    IExec internal constant EULER_EXEC = IExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

    IERC20Detailed internal constant EUL = IERC20Detailed(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b);

    uint256 internal constant EXP_SCALE = 1e18;

    uint256 internal constant ONE_FACTOR_SCALE = 1_000_000_000;

    uint256 internal constant CONFIG_FACTOR_SCALE = 4_000_000_000;

    uint256 internal constant SELF_COLLATERAL_FACTOR = 0.95 * 4_000_000_000;

    uint256 internal constant SUB_ACCOUNT_ID = 0;

    /// @notice EToken contract
    IEToken public eToken;

    IDToken public dToken;

    uint256 public targetHealthScore;

    IEulDistributor public eulDistributor;

    event UpdateTargetHealthScore(uint256 oldHeathScore, uint256 newHeathScore);

    function initialize(
        string memory _name,
        string memory _symbol,
        address _euler,
        address _eToken,
        address _dToken,
        address _underlying,
        address _owner,
        address _eulDistributor,
        uint256 _targetHealthScore
    ) public initializer {
        _initialize(_name, _symbol, _underlying, _owner);
        eToken = IEToken(_eToken);
        dToken = IDToken(_dToken);
        eulDistributor = IEulDistributor(_eulDistributor);

        targetHealthScore = _targetHealthScore;

        // Enter the collateral market (collateral's address, *not* the eToken address)
        EULER_MARKETS.enterMarket(SUB_ACCOUNT_ID, _underlying);

        underlyingToken.safeApprove(_euler, type(uint256).max);
    }

    /// @param _amount amount of underlying to deposit
    function _deposit(uint256 _amount) internal override returns (uint256 amountUsed) {
        if (_amount == 0) {
            return 0;
        }
        IRiskManager.LiquidityStatus memory status = EULER_EXEC.liquidity(address(this));

        uint256 balanceBefore = underlyingToken.balanceOf(address(this));

        // get amount to deposit to retain a target health score
        // uint256 amountToMint = getAmountToMintByHealthScore(targetHealthScore, _amount);
        uint256 amountToMint = getSelfAmountToMint(targetHealthScore, _amount);

        console.log("status.collateralValue, status.liabilityValue :>>", status.collateralValue, status.liabilityValue);

        // some of the amount should be deposited to make the health score close to the target one.
        eToken.deposit(SUB_ACCOUNT_ID, _amount);

        // self borrow
        if (amountToMint != 0) {
            eToken.mint(SUB_ACCOUNT_ID, amountToMint);
        }
        console.log("underlyingT    oken.balanceOf(address(this)) :>>", underlyingToken.balanceOf(address(this)));
        amountUsed = balanceBefore - underlyingToken.balanceOf(address(this));
        console.log("amountUsed :>>", amountUsed);
    }

    function _redeemRewards(bytes calldata data) internal override returns (uint256[] memory rewards) {
        rewards = new uint256[](1);
        // (uint256 claimable, bytes32[] memory proof) = abi.decode(data, (uint256, bytes32[]));
        // claim EUL by verifying a merkle root
        // eulDistributor.claim(address(this), address(EUL), claimable, proof, address(0));
        // uint256 bal = EUL.balanceOf(address(this));
        // address[] memory path = new address[](3);
        // path = [EUL, ETH, underlying];
        // router.swap(path, bal);
        // amountOut = underlying.balanceOf(address(this));
    }

    function _withdraw(uint256 _amountToWithdraw, address _destination)
        internal
        override
        returns (uint256 amountWithdrawn)
    {
        uint256 balanceBefore = underlyingToken.balanceOf(address(this));
        uint256 amountToBurn = getSelfAmountToBurn(targetHealthScore, _amountToWithdraw);

        console.log("_amountToWithdraw :>>", _amountToWithdraw);
        if (amountToBurn != 0) {
            // Pay off dToken liability with eTokens ("self-repay")
            eToken.burn(SUB_ACCOUNT_ID, amountToBurn);
        }
        eToken.withdraw(SUB_ACCOUNT_ID, _amountToWithdraw);

        console.log("underlyingToken.balanceOf(address(this)) :>>", underlyingToken.balanceOf(address(this)));
        console.log("dToken.balanceOf(address(this)) :>>", dToken.balanceOf(address(this)));

        amountWithdrawn = underlyingToken.balanceOf(address(this)) - balanceBefore;
        underlyingToken.safeTransfer(_destination, amountWithdrawn);

        console.log("amountWithdrawn :>>", amountWithdrawn);
    }

    /// @dev Pay off dToken liability with eTokens ("self-repay")
    function repayMannualy(uint256 _amount) external onlyOwner {
        eToken.burn(SUB_ACCOUNT_ID, _amount);
    }

    function setTargetHealthScore(uint256 _healthScore) external onlyOwner {
        require(_healthScore > EXP_SCALE, "strat/invalid-target-hs");

        uint256 _oldTargetHealthScore = targetHealthScore;
        targetHealthScore = _healthScore;

        emit UpdateTargetHealthScore(_oldTargetHealthScore, _healthScore);
    }

    /// @notice For example
    /// - deposit $1000 RBN
    /// - mint $10,00 RBN
    /// in the end this contract holds $11000 RBN deposits and $10,000 RBN debts.
    /// will have a health score of exactly 1.
    /// Changes in price of RBN will have no effect on a user's health score,
    /// because their collateral deposits rise and fall at the same rate as their debts.
    /// So, is a user at risk of liquidation? This depends on how much more interest they are
    /// paying on their debts than they are earning on their deposits.
    /// @dev
    /// Euler fi defines health score a little differently
    /// Health score = risk adjusted collateral / risk adjusted liabilities
    /// Collateral amount * collateral factor = risk adjusted collateral
    /// Borrow amount / borrow factor = risk adjusted liabilities
    /// ref: https://github.com/euler-xyz/euler-contracts/blob/0fade57d9ede7b010f943fa8ad3ad74b9c30e283/contracts/modules/RiskManager.sol#L314
    /// @param _targetHealthScore  health score 1.0 == 1e18
    /// @param _amount _amount to deposit or withdraw. _amount greater than zero means `deposit`. _amount less than zero means `withdraw`
    function _getSelfAmount(uint256 _targetHealthScore, int256 _amount) internal view returns (int256) {
        require(_targetHealthScore > EXP_SCALE, "strat/invalid-target-hs");
        IMarkets.AssetConfig memory config = EULER_MARKETS.underlyingToAssetConfig(token);
        uint256 cf = config.collateralFactor;

        uint256 balanceInUnderlying = IEToken(config.eTokenAddress).balanceOfUnderlying(address(this));
        uint256 debtInUnderlying = dToken.balanceOf(address(this));
        int256 collateral = int256(balanceInUnderlying) + _amount;
        require(collateral > 0, "strat/exceed-balance");

        console.log("balanceInUnderlying,debtInUnderlying :>>", balanceInUnderlying, debtInUnderlying);
        {
            uint256 term1 = ((cf * uint256(collateral))) / CONFIG_FACTOR_SCALE;
            uint256 term2 = (((_targetHealthScore * ONE_FACTOR_SCALE) /
                EXP_SCALE +
                (cf * ONE_FACTOR_SCALE) /
                SELF_COLLATERAL_FACTOR -
                ONE_FACTOR_SCALE) * debtInUnderlying) / ONE_FACTOR_SCALE;

            uint256 denominator = (_targetHealthScore * ONE_FACTOR_SCALE) /
                EXP_SCALE +
                (cf * ONE_FACTOR_SCALE) /
                SELF_COLLATERAL_FACTOR -
                (cf * ONE_FACTOR_SCALE) /
                CONFIG_FACTOR_SCALE -
                ONE_FACTOR_SCALE;
            int256 selfAmount = ((int256(term1) - int256(term2)) * int256(ONE_FACTOR_SCALE)) / int256(denominator);
            console.log("selfAmount :>>");
            console.logInt(selfAmount);
            if ((_amount >= 0 && selfAmount <= 0) || (_amount <= 0 && selfAmount >= 0)) {
                return 0;
            }
            if ((_amount >= 0 && selfAmount >= _amount) || (_amount <= 0 && selfAmount <= _amount)) {
                return _amount;
            }
            return selfAmount;
        }
    }

    function getSelfAmountToMint(uint256 _targetHealthScore, uint256 _amount) public view returns (uint256) {
        return uint256(_getSelfAmount(_targetHealthScore, int256(_amount)));
    }

    function getSelfAmountToBurn(uint256 _targetHealthScore, uint256 _amount) public view returns (uint256) {
        return uint256(-1 * _getSelfAmount(_targetHealthScore, -int256(_amount)));
    }

    function getCurrentHealthScore() public view returns (uint256) {
        IRiskManager.LiquidityStatus memory status = EULER_EXEC.liquidity(address(this));
        // approximately equal to `eToken.balanceOfUnderlying(address(this))` divide by ` dToken.balanceOf(address(this))`
        return (status.collateralValue * EXP_SCALE) / status.liabilityValue;
    }

    function getCurrentLeverage() public view returns (uint256) {
        uint256 balanceInUnderlying = eToken.balanceOfUnderlying(address(this));
        uint256 debtInUnderlying = dToken.balanceOf(address(this));
        // leverage = debt / principal
        return debtInUnderlying / (balanceInUnderlying - debtInUnderlying);
    }

    function getRewardTokens() external view override returns (address[] memory rewards) {
        rewards = new address[](1);
        rewards[0] = address(EUL);
    }
}
