# Credit Vault factory deployment fee

The Credit Vault factory supports paid access on Ethereum mainnet, Base, and Arbitrum One. An unlisted wallet can pay a fixed amount of the network's native USDC each time it calls `deployCreditVault` or `deployRevolvingCreditVault`. The factory sends the fee directly to its `treasury()`, the network's treasury multisig. The vault's underlying asset and its performance and management fees are configured independently.

## Deploying from an unlisted wallet

1. Read `deploymentFeeToken()` and `deploymentFee()` from the factory proxy. The fee uses six-decimal USDC units, so `5_000_000_000` represents 5,000 USDC.
2. Approve the factory proxy to spend the fee in that USDC token.
3. Call the factory's standard or revolving deployment function. Both entry points use the fee in effect when the transaction executes.

Each deployment uses a separate fee from the caller's balance and allowance. Insufficient balance or allowance reverts the transaction. If vault setup reverts after the transfer, the USDC balances and allowance are restored along with the rest of the transaction state.

Whitelisted callers continue to use their deployment quotas without paying USDC. An exhausted quota requires replenishment to use the whitelisted path. Removing a wallet from the whitelist makes it eligible to use paid access when enabled.

## Configuring paid access

The factory treasury can call `setDeploymentFee(uint256)` to enable paid access or change the fee for future deployments. Set the fee to zero to disable paid access. New factories start with a zero fee. A plain implementation upgrade preserves the stored `deploymentFee()`: it is zero after upgrading a factory that never had paid access and keeps any fee treasury already configured. On other networks, `deploymentFeeToken()` returns the zero address and setting a positive fee reverts.

## Monthly subscriptions

The factory also records a per-wallet monthly subscription, paid in the same USDC token as the deployment fee and sent directly to `treasury()`. A subscription month is `SUBSCRIPTION_PERIOD()`, a fixed 30 days (2,592,000 seconds), not a calendar month.

Every wallet without an admin override owes `DEFAULT_MONTHLY_SUBSCRIPTION_FEE()`, a fixed 500 USDC (`500_000_000`) per month. The admin can override any wallet's rate, including setting it to zero so that the wallet never has to approve or pay a subscription. New factories and factories upgraded to this implementation start with no overrides and no paid periods, so every unlisted wallet is due at the default rate until it pays or receives an override. On networks without a fee token, `monthlySubscriptionFee(wallet)` returns zero for every wallet and no subscription is due.

The subscription is separate from deployment authorization. The factory does not require an active subscription to deploy. The plain `deployCreditVault` and `deployRevolvingCreditVault` calls neither pay nor extend a subscription, so they leave `subscriptionPaidUntil(wallet)` untouched. The UI decides whether to prompt for payment.

Whitelisted wallets (`whitelist(wallet)` is true) are exempt from subscriptions. For a whitelisted caller, `paySubscription` and the subscription part of both combined deployment calls transfer no USDC, set no expiry, and emit no `SubscriptionPaid` event, whatever its rate. The wallet's rate, whether the default or an override, applies once the wallet is removed from the whitelist. The exemption also covers a whitelisted wallet whose deployment quota is exhausted.

| Wallet | `isSubscriptionDue(wallet)` |
| --- | --- |
| Whitelisted, with any rate or expiry | `false` |
| Overridden to zero | `false` |
| Not whitelisted, default or nonzero override rate, and never paid or `subscriptionPaidUntil(wallet) <= block.timestamp` | `true` |
| Not whitelisted, default or nonzero override rate, and `subscriptionPaidUntil(wallet) > block.timestamp` | `false` |

A wallet overridden to zero has no subscription to pay, but it still pays `deploymentFee()` for each deployment unless it is whitelisted.

### Reading subscription status

All read calls are `view` functions on the factory proxy.

| Call | Input | Output (ABI type) |
| --- | --- | --- |
| `isSubscriptionDue(address wallet)` | Wallet to check | `bool`: whether to prompt the wallet to pay. |
| `subscriptionPaidUntil(address wallet)` | Wallet to check | `uint256`: Unix timestamp in seconds when the paid period ends; `0` if never paid. |
| `monthlySubscriptionFee(address wallet)` | Wallet to check | `uint256`: effective USDC per month in six-decimal units: the override if one is set, otherwise the 500 USDC default; `0` for zero overrides and on networks without a fee token. |
| `hasMonthlySubscriptionFeeOverride(address wallet)` | Wallet to check | `bool`: whether an admin set the wallet's rate. |
| `whitelist(address wallet)` | Wallet to check | `bool`: whether the wallet is exempt. |
| `DEFAULT_MONTHLY_SUBSCRIPTION_FEE()` | None | `uint256`: rate for wallets without an override (`500000000`). |
| `SUBSCRIPTION_PERIOD()` | None | `uint256`: seconds per paid month (`2592000`). |
| `deploymentFeeToken()` | None | `address`: USDC token used for payments; the zero address on unsupported networks. |

Prompt the user when `isSubscriptionDue(wallet)` returns `true`. Show `subscriptionPaidUntil(wallet)` as the expiry; when it is in the future, the subscription is active. Use `monthlySubscriptionFee(wallet)` for the price; do not read the default constant directly, because it ignores overrides.

### Paying a subscription

1. Choose a whole number of months `months` and compute `amount = monthlySubscriptionFee(wallet) * months`.
2. Approve the factory proxy to spend `amount` of `deploymentFeeToken()`.
3. Call `paySubscription(uint256 months)` from the wallet. It always pays for `msg.sender`.

`paySubscription` has no return value. On a successful payment it emits `SubscriptionPaid(address indexed wallet, uint256 months, uint256 amount, uint256 paidUntil)`, where `paidUntil` is the new expiry. The new expiry is `max(block.timestamp, subscriptionPaidUntil(wallet)) + months * SUBSCRIPTION_PERIOD()`. Renewing before expiry extends the current paid period. Renewing after expiry starts from the payment time, so the lapsed gap is not charged.

For a wallet that is not whitelisted, `paySubscription` reverts with `Is0()` when `months` is zero or the caller's rate is overridden to zero. Insufficient balance or allowance reverts without changing the expiry. For a whitelisted wallet, the call succeeds without charging, extending, or emitting an event, so the UI should not offer it.

### Deploying and subscribing in one transaction

`deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, months)` and `deployRevolvingCreditVaultWithSubscription(cvParams, strategyData, programmableBorrowerParams, ancillaryParams, months)` take the same parameters as the existing deployment functions, plus `uint256 months`. Each call pays `months` of the caller's subscription and then runs the matching deployment flow.

The combined calls have no return value. On success, read the deployed addresses from the `CreditVaultDeployed` event and the new expiry from the `SubscriptionPaid` event, which is emitted only when a subscription was charged.

For an unlisted wallet, approve `monthlySubscriptionFee(wallet) * months + deploymentFee()`. If either payment or any deployment step fails, the whole transaction reverts, including the subscription payment. The combined calls revert with `Is0()` for an unlisted wallet overridden to zero or zero `months`; use `deployCreditVault` or `deployRevolvingCreditVault` instead.

For a whitelisted wallet, the combined calls charge no subscription and no deployment fee and set no expiry, whatever `months` is. They consume one deployment from the wallet's quota exactly like the plain deployment calls: a finite quota decreases by one, an `UNLIMITED_DEPLOYMENTS()` quota never decreases, and an exhausted quota reverts with `DeploymentLimitReached()`.

### Configuring subscription rates

The factory treasury or the Pareto deployer can call `setMonthlySubscriptionFees(address[] wallets, uint256[] monthlyFees)`. Each value sets an override in six-decimal USDC units and marks the wallet in `hasMonthlySubscriptionFeeOverride`. Set a wallet to `0` to exempt it from the subscription; set it to `500000000` to charge the default amount again. A new rate applies to future payments and does not change a paid period. On networks without a fee token, a nonzero override reverts with `UnsupportedDeploymentFeeNetwork()`.
