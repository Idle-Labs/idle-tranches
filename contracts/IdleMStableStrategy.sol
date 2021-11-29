// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IMAsset.sol";
import "./interfaces/ISavingsContractV2.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IVault.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IdleMStableStrategy is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IIdleCDOStrategy
{
    using SafeERC20Upgradeable for IERC20Detailed;
    using SafeMath for uint256;

    /// @notice underlying token address (eg mUSD)
    address public override token;

    /// @notice address of the strategy used, in this case imUSD
    address public override strategyToken;

    /// @notice decimals of the underlying asset
    uint256 public override tokenDecimals;

    /// @notice one underlying token
    uint256 public override oneToken;

    /// @notice idleToken contract
    ISavingsContractV2 public imUSD;

    /// @notice underlying ERC20 token contract
    IERC20Detailed public underlyingToken;

    /* ------------Extra declarations ---------------- */
    address public govToken;
    IVault public vault;

    mapping(address => uint256) public Credits;
    uint256 public totalCredits;

    mapping(address => uint256) public govTokenShares;
    uint256 public totalGovTokenShares;

    uint256 public totalGovTokens;

    constructor() {
        token = address(1);
    }

    event Deposit(address indexed user, uint256 amount, uint256 sharesRecevied);
    event Redeem(address indexed user, uint256 credits, uint256 received);

    function initialize(
        address _strategyToken,
        address _underlyingToken,
        address _govToken,
        address _vault,
        address _owner
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        //----- // -------//
        strategyToken = _strategyToken;
        token = _underlyingToken;
        underlyingToken = IERC20Detailed(token);
        tokenDecimals = underlyingToken.decimals();
        oneToken = 10**(tokenDecimals);
        imUSD = ISavingsContractV2(_strategyToken);
        govToken = _govToken;
        vault = IVault(_vault);
        //------//-------//

        transferOwnership(_owner);
    }

    // only claim gov token rewards
    function redeemRewards()
        external
        override
        returns (uint256[] memory rewards)
    {
        rewards[0] = _withdrawGovTokens(msg.sender);
    }

    function pullStkAAVE() external override returns (uint256) {
        return 0;
    }

    function price() public view override returns (uint256) {
        return imUSD.exchangeRate();
    }

    function getRewardTokens()
        external
        view
        override
        returns (address[] memory)
    {
        address[] memory govTokens;
        govTokens[0] = govToken;
        return govTokens;
    }

    function deposit(uint256 _amount)
        external
        override
        returns (uint256 minted)
    {
        require(_amount != 0, "Deposit amount should be greater than 0");
        underlyingToken.transferFrom(msg.sender, address(this), _amount);
        underlyingToken.approve(address(imUSD), _amount);
        uint256 interestTokensReceived = imUSD.depositSavings(_amount);

        uint256 interestTokenAvailable = imUSD.balanceOf(address(this));
        imUSD.approve(address(vault), interestTokenAvailable);

        uint256 rawBalanceBefore = vault.rawBalanceOf(address(this));
        vault.stake(interestTokenAvailable);
        uint256 rawBalanceAfter = vault.rawBalanceOf(address(this));
        uint256 rawBalanceIncreased = rawBalanceAfter.sub(rawBalanceBefore);

        Credits[msg.sender] = Credits[msg.sender].add(rawBalanceIncreased);
        totalCredits = totalCredits.add(rawBalanceIncreased);

        govTokenShares[msg.sender] = govTokenShares[msg.sender].add(
            rawBalanceIncreased
        );
        totalGovTokenShares = totalGovTokenShares.add(rawBalanceIncreased);

        emit Deposit(msg.sender, _amount, rawBalanceIncreased);
        return interestTokensReceived;
    }

    function transferShares(
        address _to,
        uint256 _interestTokens,
        uint256 _govShares
    ) public {
        require(msg.sender != _to, "Sender and Received cannot be same");
        Credits[msg.sender] = Credits[msg.sender].sub(_interestTokens);
        Credits[_to] = Credits[_to].add(_interestTokens);

        govTokenShares[msg.sender] = govTokenShares[msg.sender].sub(_govShares);
        govTokenShares[_to] = govTokenShares[_to].add(_govShares);
    }

    // _amount is strategy token
    function redeem(uint256 _amount) external override returns (uint256) {
        return _redeem(_amount);
    }

    // _amount in underlying token
    function redeemUnderlying(uint256 _amount)
        external
        override
        returns (uint256)
    {
        uint256 _underlyingAmount = _amount.mul(oneToken).div(price());
        return _redeem(_underlyingAmount);
    }

    function getApr() external view override returns (uint256) {
        return oneToken;
    }

    /* -------- internal functions ------------- */

    // here _amount means credits, will redeem any governance token if there
    function _redeem(uint256 _amount) internal returns (uint256) {
        require(_amount != 0, "Amount shuld be greater than 0");
        uint256 availableCredits = Credits[msg.sender];
        require(
            availableCredits >= _amount,
            "Cannot redeem more than available"
        );
        Credits[msg.sender] = Credits[msg.sender].sub(_amount);
        totalCredits = totalCredits.sub(_amount);
        vault.withdraw(_amount);

        uint256 massetReceived = imUSD.redeem(_amount);
        underlyingToken.transfer(msg.sender, massetReceived);
        _withdrawGovTokens(msg.sender);
        emit Redeem(msg.sender, _amount, massetReceived);
        return massetReceived;
    }

    function _withdrawGovTokens(address _address)
        internal
        returns (uint256 govTokensToSend)
    {
        if (govTokenShares[_address] != 0) {
            govTokensToSend = govTokenShares[_address].mul(totalGovTokens).div(
                totalGovTokenShares
            );
            if (govTokensToSend != 0) {
                totalGovTokenShares = totalGovTokenShares.sub(
                    govTokenShares[_address]
                );
                govTokenShares[_address] = 0;
                IERC20Detailed(govToken).transfer(_address, govTokensToSend);
            }
        }
    }

    function claimGovernanceTokens(uint256 startRound, uint256 endRound)
        public
        onlyOwner
    {
        _claimGovernanceTokens(startRound, endRound);
    }

    // pass (0,0) as paramsif you want to claim for all epochs
    function _claimGovernanceTokens(uint256 startRound, uint256 endRound)
        internal
    {
        require(
            startRound >= endRound,
            "Start Round Cannot be more the end round"
        );

        if (startRound == 0 && endRound == 0) {
            vault.claimRewards(); // this be a infy gas call,
        } else {
            vault.claimRewards(startRound, endRound);
        }
        totalGovTokens = IERC20Detailed(govToken).balanceOf(address(this));
    }
}
