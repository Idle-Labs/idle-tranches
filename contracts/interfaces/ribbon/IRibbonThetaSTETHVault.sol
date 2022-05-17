// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

library Vault {
    struct Withdrawal {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Number of shares withdrawn
        uint128 shares;
    }
}

interface IRibbonThetaSTETHVault {
    function WETH() external view returns (address);
    function keeper() external view returns (address);
    function strikeSelection() external view returns (address);
    function currentOption() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function depositETH() external payable;
    function commitAndClose() external;
    function rollToNextOption() external;
    function transfer(address receiptient, uint256 amount) external;
    function initiateWithdraw(uint256 amount) external;
    function completeWithdraw() external;

    function pricePerShare() external view returns (uint256);
    function accountVaultBalance(address account) external view returns (uint256);
    function shareBalances(address account) external view returns (uint256);
    function withdrawals(address account) external view returns (Vault.Withdrawal memory);
}
