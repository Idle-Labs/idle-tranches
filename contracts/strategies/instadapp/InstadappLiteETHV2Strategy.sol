// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../interfaces/IERC20Detailed.sol";
import "../ERC4626Strategy.sol";

contract InstadappLiteETHV2Strategy is ERC4626Strategy {
    using SafeERC20Upgradeable for IERC20Detailed;

    uint256 internal constant SECONDS_IN_YEAR = 60 * 60 * 24 * 365;
    address internal constant ETHV2Vault = 0xA0D3707c569ff8C87FA923d3823eC5D81c98Be78;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // TODO: pack into single or 2 slots
    uint256 internal lastPriceTimestamp;
    uint256 internal lastPrice;
    uint256 internal lastApr;

    function initialize(address _owner) public {
        _initialize(ETHV2Vault, STETH, _owner);
        lastPrice = price();
        lastPriceTimestamp = block.timestamp;
    }

    function deposit(uint256 _amount) external override onlyIdleCDO returns (uint256 shares) {
        uint256 _lastPrice = lastPrice;
        uint256 _lastPriceTimestamp = lastPriceTimestamp;

        // ETHV2Vault price is updated only at the time of rebalance
        // if _lastPrice == zero, then apr returns zero as well
        if (_lastPriceTimestamp < block.timestamp) {
            uint256 _price = price();
            // update
            if (_price > lastPrice){
                lastPrice = _price;
                lastPriceTimestamp = block.timestamp;
                lastApr = _computeApr(block.timestamp, _price, _lastPriceTimestamp, _lastPrice);
            }
        }
        if (_amount != 0) {
            // Send tokens to the strategy
            IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
            // Calls deposit function
            shares = IERC4626(strategyToken).deposit(_amount, msg.sender);
        }
    }

    /// @notice redeem the rewards
    /// @return rewards amount of reward that is deposited to the ` strategy`
    function redeemRewards(bytes calldata data)
        public
        virtual
        override
        onlyIdleCDO
        nonReentrant
        returns (uint256[] memory rewards)
    {}

    function getRewardTokens() external view returns (address[] memory rewards) {}

    function getApr() external view override returns (uint256) {
        uint256 _price = price();
        if (lastPriceTimestamp >= block.timestamp || lastPrice > _price) {
            return lastApr;
        }
        return _computeApr(block.timestamp, _price, lastPriceTimestamp, lastPrice);
    }

    function _computeApr(
        uint256 _currentTimestamp,
        uint256 _currentPrice,
        uint256 _lastPriceTimestamp,
        uint256 _lastPrice
    ) internal pure returns (uint256) {
        if (_lastPrice > _currentPrice) {
            return 0;
        }
        // Calculate the percentage change in the price of the token
        uint256 priceChange = ((_currentPrice - _lastPrice) * 1e18) / _lastPrice;

        // Determine the time difference in seconds between the current timestamp and the timestamp when the last price was updated
        uint256 timeDifference = _currentTimestamp - _lastPriceTimestamp;

        uint256 aprPerYear = (priceChange * SECONDS_IN_YEAR) / timeDifference;

        return aprPerYear * 100; // Return APR as a percentage
    }
}
