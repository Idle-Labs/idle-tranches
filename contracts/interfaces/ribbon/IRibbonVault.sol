// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

library Vault {
    struct Withdrawal {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Number of shares withdrawn
        uint128 shares;
    }
    struct DepositReceipt {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Deposit amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        uint104 amount;
        // Unredeemed shares balance
        uint128 unredeemedShares;
    }
    struct VaultState {
        // 32 byte slot 1
        //  Current round number. `round` represents the number of `period`s elapsed.
        uint16 round;
        // Amount that is currently locked for selling options
        uint104 lockedAmount;
        // Amount that was locked for selling options in the previous round
        // used for calculating performance fee deduction
        uint104 lastLockedAmount;
        // 32 byte slot 2
        // Stores the total tally of how much of `asset` there is
        // to be used to mint rTHETA tokens
        uint128 totalPending;
        // Total amount of queued withdrawal shares from previous rounds (doesn't include the current round)
        uint128 queuedWithdrawShares;
    }
}

interface IRibbonVault {
    function WETH() external view returns (address);
    function STETH() external view returns (address);
    function keeper() external view returns (address);
    function strikeSelection() external view returns (address);
    function currentOption() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function depositETH() external payable;
    function closeRound() external;
    function commitAndClose() external;
    function commitNextOption() external;
    function rollToNextOption() external;
    function transfer(address receiptient, uint256 amount) external;
    function initiateWithdraw(uint256 amount) external;
    function completeWithdraw() external;
    function deposit(uint256 amount) external;
    function depositYieldToken(uint256 amount) external;
    function withdrawInstantly(uint256 amount, uint256) external;
    function withdrawInstantly(uint256 amount) external;

    function pricePerShare() external view returns (uint256);
    function accountVaultBalance(address account) external view returns (uint256);
    function shareBalances(address account) external view returns (uint256);
    function withdrawals(address account) external view returns (Vault.Withdrawal memory);

    function depositReceipts(address acount) external view returns(Vault.DepositReceipt memory);
    function shares(address acount) external view returns(uint256);
    function setMinPrice(uint256 minPrice) external;
    function nextOptionReadyAt() external view returns (uint256);
    function GNOSIS_EASY_AUCTION() external view returns(address);
    function vaultState() external view returns (Vault.VaultState memory);
    function roundPricePerShare(uint256) external view returns (uint256);
    function cap() external view returns(uint256);
    function setCap(uint256 amount) external;
    function owner() external view returns(address);
}
