// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../BaseStrategy.sol";

import "../../interfaces/euler/IEToken.sol";
import "../../interfaces/euler/IDToken.sol";
import "../../interfaces/euler/IMarkets.sol";
import "../../interfaces/euler/IExec.sol";
import "../../interfaces/euler/IEulerGeneralView.sol";
import "../../interfaces/euler/IEulDistributor.sol";
import "../../interfaces/ISwapRouter.sol";

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

    ISwapRouter public router;

    bytes public path;

    event UpdateTargetHealthScore(uint256 oldHeathScore, uint256 newHeathScore);

    event UpdateEulDistributor(address oldEulDistributor, address newEulDistributor);

    event UpdateSwapRouter(address oldRouter, address newRouter);

    event UpdateRouterPath(bytes oldRouter, bytes _path);

    function initialize(
        string memory _name,
        string memory _symbol,
        address _euler,
        address _eToken,
        address _dToken,
        address _underlying,
        address _owner,
        address _eulDistributor,
        address _router,
        bytes memory _path,
        uint256 _targetHealthScore
    ) public initializer {
        _initialize(_name, _symbol, _underlying, _owner);
        eToken = IEToken(_eToken);
        dToken = IDToken(_dToken);
        eulDistributor = IEulDistributor(_eulDistributor);
        router = ISwapRouter(_router);
        path = _path;
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

        // some of the amount should be deposited to make the health score close to the target one.
        eToken.deposit(SUB_ACCOUNT_ID, _amount);

        // self borrow
        if (amountToMint != 0) {
            eToken.mint(SUB_ACCOUNT_ID, amountToMint);
        }

        amountUsed = balanceBefore - underlyingToken.balanceOf(address(this));
    }

    function _redeemRewards(bytes calldata data) internal override returns (uint256[] memory rewards) {
        rewards = new uint256[](1);

        if (address(eulDistributor) != address(0) && address(router) != address(0) && data.length != 0) {
            (uint256 claimable, bytes32[] memory proof) = abi.decode(data, (uint256, bytes32[]));

            // claim EUL by verifying a merkle root
            eulDistributor.claim(address(this), address(EUL), claimable, proof, address(0));
            uint256 amountIn = EUL.balanceOf(address(this));

            // swap EUL for underlying
            EUL.safeApprove(address(router), amountIn);
            router.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0
                })
            );

            rewards[0] = underlyingToken.balanceOf(address(this));
        }
    }

    function _withdraw(uint256 _amountToWithdraw, address _destination)
        internal
        override
        returns (uint256 amountWithdrawn)
    {
        uint256 balanceBefore = underlyingToken.balanceOf(address(this));
        uint256 amountToBurn = getSelfAmountToBurn(targetHealthScore, _amountToWithdraw);

        if (amountToBurn != 0) {
            // Pay off dToken liability with eTokens ("self-repay")
            eToken.burn(SUB_ACCOUNT_ID, amountToBurn);
        }

        uint256 balanceInUnderlying = eToken.balanceOfUnderlying(address(this));
        if (_amountToWithdraw > balanceInUnderlying) {
            console.log("_amountToWithdraw :>>", _amountToWithdraw);
            console.log("balanceInUnderlying :>>", balanceInUnderlying);
            _amountToWithdraw = balanceInUnderlying;
        }
        // withdraw underlying
        eToken.withdraw(SUB_ACCOUNT_ID, _amountToWithdraw);

        amountWithdrawn = underlyingToken.balanceOf(address(this)) - balanceBefore;
        underlyingToken.safeTransfer(_destination, amountWithdrawn);
    }

    /// @dev Pay off dToken liability with eTokens ("self-repay") and depost the withdrawn underlying
    function deleverageMannualy(uint256 _amount) external onlyOwner {
        eToken.burn(SUB_ACCOUNT_ID, _amount);
        eToken.deposit(SUB_ACCOUNT_ID, underlyingToken.balanceOf(address(this)));
    }

    function setTargetHealthScore(uint256 _healthScore) external onlyOwner {
        require(_healthScore > EXP_SCALE, "strat/invalid-target-hs");

        uint256 _oldTargetHealthScore = targetHealthScore;
        targetHealthScore = _healthScore;

        emit UpdateTargetHealthScore(_oldTargetHealthScore, _healthScore);
    }

    function setEulDistributor(address _eulDistributor) external onlyOwner {
        address oldEulDistributor = address(eulDistributor);
        eulDistributor = IEulDistributor(_eulDistributor);

        emit UpdateEulDistributor(oldEulDistributor, _eulDistributor);
    }

    function setSwapRouter(address _router) external onlyOwner {
        address oldRouter = address(router);
        router = ISwapRouter(_router);

        emit UpdateSwapRouter(oldRouter, _router);
    }

    function setRouterPath(bytes calldata _path) external onlyOwner {
        bytes memory oldPath = path;
        path = _path;

        emit UpdateRouterPath(oldPath, _path);
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
    function _getSelfAmount(uint256 _targetHealthScore, int256 _amount) internal view returns (uint256 selfAmount) {
        require(_targetHealthScore > EXP_SCALE, "strat/invalid-target-hs");

        uint256 debtInUnderlying = dToken.balanceOf(address(this));

        uint256 cf;
        uint256 balance;
        uint256 balanceInUnderlying;
        {
            IMarkets.AssetConfig memory config = EULER_MARKETS.underlyingToAssetConfig(token);
            cf = config.collateralFactor;
            balance = IEToken(config.eTokenAddress).balanceOf(address(this));
            balanceInUnderlying = IEToken(config.eTokenAddress).convertBalanceToUnderlying(balance);
        }

        {
            int256 collateral = int256(balanceInUnderlying) + _amount;
            require(collateral > 0, "strat/exceed-balance");

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

            if (term1 >= term2) {
                if (_amount <= 0) return 0;
                selfAmount = ((term1 - term2) * ONE_FACTOR_SCALE) / denominator;
            } else {
                if (_amount >= 0) return 0;
                selfAmount = ((term2 - term1) * ONE_FACTOR_SCALE) / denominator;
                if (selfAmount > debtInUnderlying) {
                    selfAmount = debtInUnderlying;
                }
            }
        }
    }

    function getSelfAmountToMint(uint256 _targetHealthScore, uint256 _amount) public view returns (uint256) {
        return _getSelfAmount(_targetHealthScore, int256(_amount));
    }

    function getSelfAmountToBurn(uint256 _targetHealthScore, uint256 _amount) public view returns (uint256) {
        return _getSelfAmount(_targetHealthScore, -int256(_amount));
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
