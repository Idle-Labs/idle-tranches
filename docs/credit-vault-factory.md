# Credit Vault factory deployment fee

The Credit Vault factory supports paid access on Ethereum mainnet, Base, and Arbitrum One. An unlisted wallet can pay a fixed amount of the network's native USDC each time it calls `deployCreditVault` or `deployRevolvingCreditVault`. The factory sends the fee directly to its `treasury()`, the network's treasury multisig. The vault's underlying asset and its performance and management fees are configured independently.

## Deploying from an unlisted wallet

1. Read `deploymentFee()` from the factory proxy. A zero global fee closes unlisted deployments, including for wallets with custom prices.
2. Read `deploymentFeeFor(wallet)` for the calling wallet. If the quote is positive, approve the factory proxy to spend that amount of `deploymentFeeToken()` in six-decimal USDC units. A zero quote while unlisted deployments are open means the wallet has a waiver.
3. Call the factory's standard or revolving deployment function. Both entry points use the fee in effect when the transaction executes.

Each deployment uses a separate fee from the caller's balance and allowance. Insufficient balance or allowance reverts the transaction. If vault setup reverts after the transfer, the USDC balances and allowance are restored along with the rest of the transaction state.

Whitelisted callers continue to use their deployment quotas without paying USDC. An exhausted quota requires replenishment to use the whitelisted path. Removing a wallet from the whitelist makes it eligible to use paid access when enabled.

## Configuring paid access

New factories on Ethereum mainnet, Base, and Arbitrum One start at 5,000 USDC per unlisted deployment. A plain implementation upgrade preserves the proxy's stored fee. For an existing V3 proxy upgrading from the whitelist-only implementation, the treasury Safe must call `setDeploymentFee(5000000000)` on the factory proxy after the upgrade to enable the 5,000 USDC fee. The treasury can change the fee later or set it to zero to disable paid deployments. On other networks the fee starts at zero and setting a positive fee reverts.

Treasury or the Pareto deployer can update several wallets in one transaction with `setWalletFees(address[] wallets, WalletFees[] fees)`. The factory stores both prices together under the wallet address. Each fee pair contains only `(deploymentFee, monthlyFee)`, in six-decimal USDC units. Both arrays must have the same length, and `fees[i]` applies to `wallets[i]`.

| Fee pair for a wallet | Deployment price | Monthly subscription |
| --- | --- | --- |
| `(2000000000, 250000000)` | 2,000 USDC | 250 USDC |
| `(USE_DEFAULT_FEE, 0)` | Current factory default | Waived |
| `(USE_DEFAULT_FEE, USE_DEFAULT_FEE)` | Current factory default | Current factory default |

For example, in ethers.js, this batch gives the first wallet custom prices and waives only the second wallet's subscription.

```js
const useDefault = await factory.USE_DEFAULT_FEE()
await factory.setWalletFees(
  [firstWallet, secondWallet],
  [[2_000_000_000, 250_000_000], [useDefault, 0]]
)
```

Each update replaces both prices for that wallet. Read `walletFees(wallet)` to retrieve its current terms before changing just one. The getter returns `USE_DEFAULT_FEE()` for a price that follows the default and `0` for a waiver. For the price charged at deployment, use `deploymentFeeFor(wallet)`, which also accounts for the whitelist and the global deployment setting.

## Monthly subscriptions

The factory also records a per-wallet monthly subscription, paid in the same USDC token as the deployment fee and sent directly to `treasury()`. A subscription month is `SUBSCRIPTION_PERIOD()`, a fixed 30 days (2,592,000 seconds), not a calendar month.

On a supported network, an unlisted wallet without an override pays the default of 500 USDC (`500_000_000`) per 30 days. On upgrade from the whitelist-only V3 factory, both wallet prices start at their defaults and the paid-through timestamp starts at zero. Subsequent fee changes preserve any time the wallet has paid for. A zero override exempts the wallet from the subscription. On networks without a fee token, `monthlySubscriptionFee(wallet)` returns zero and no subscription is due.

The subscription is separate from deployment authorization. The factory does not require an active subscription to deploy. The plain `deployCreditVault` and `deployRevolvingCreditVault` calls neither pay nor extend a subscription, so they leave `subscriptionPaidUntil(wallet)` untouched. The UI decides whether to prompt for payment.

Whitelisted wallets (`whitelist(wallet)` is true) are exempt from subscriptions. For a whitelisted caller, `paySubscription` and the subscription part of both combined deployment calls transfer no USDC, set no expiry, and emit no `SubscriptionPaid` event, whatever its rate. The wallet's rate, whether the default or an override, applies once the wallet is removed from the whitelist. The exemption also covers a whitelisted wallet whose deployment quota is exhausted.

| Wallet | `isSubscriptionDue(wallet)` |
| --- | --- |
| Whitelisted, with any rate or expiry | `false` |
| Overridden to zero | `false` |
| Not whitelisted, default or nonzero override rate, and never paid or `subscriptionPaidUntil(wallet) <= block.timestamp` | `true` |
| Not whitelisted, default or nonzero override rate, and `subscriptionPaidUntil(wallet) > block.timestamp` | `false` |

A wallet with a zero monthly rate has no subscription to pay. Its deployment price is given by `deploymentFeeFor(wallet)`.

### Reading subscription status

All read calls are `view` functions on the factory proxy.

| Call | Input | Output (ABI type) |
| --- | --- | --- |
| `walletFees(address wallet)` | Wallet to check | `(uint256 deploymentFee, uint256 monthlyFee)` in six-decimal USDC units, including any default markers. |
| `isSubscriptionDue(address wallet)` | Wallet to check | `bool`: whether to prompt the wallet to pay. |
| `subscriptionPaidUntil(address wallet)` | Wallet to check | `uint256`: Unix timestamp in seconds when the paid period ends; `0` if never paid. |
| `monthlySubscriptionFee(address wallet)` | Wallet to check | `uint256`: effective USDC per month in six-decimal units: the override if one is set, otherwise the 500 USDC default; `0` for zero overrides and on networks without a fee token. |
| `whitelist(address wallet)` | Wallet to check | `bool`: whether the wallet is exempt. |
| `DEFAULT_MONTHLY_SUBSCRIPTION_FEE()` | None | `uint256`: rate for wallets without an override (`500000000`). |
| `SUBSCRIPTION_PERIOD()` | None | `uint256`: seconds per paid month (`2592000`). |
| `deploymentFeeToken()` | None | `address`: USDC token used for payments; the zero address on unsupported networks. |

Prompt the user when `isSubscriptionDue(wallet)` returns `true`. Show `subscriptionPaidUntil(wallet)` as the expiry; when it is in the future, the subscription is active. Use `monthlySubscriptionFee(wallet)` for the price; do not read the default constant directly, because it ignores overrides.

### Paying a subscription

1. Choose a whole number of months `months` and compute `amount = monthlySubscriptionFee(wallet) * months`.
2. Approve the factory proxy to spend `amount` of `deploymentFeeToken()`.
3. Call `paySubscription(uint256 months)` from the wallet. It always pays for `msg.sender`.

`paySubscription` has no return value. On a successful payment it emits `SubscriptionPaid(address indexed wallet, uint256 months, uint256 amount, uint256 paidUntil)`, where `paidUntil` is the new expiry. The new expiry is `max(block.timestamp, subscriptionPaidUntil(wallet)) + months * SUBSCRIPTION_PERIOD()`:

- Paying before expiry extends from the current expiry, so the remaining paid days are kept. With an expiry of March 30, one month paid on March 20 runs to about April 29 (March 30 plus 30 days).
- Paying on or after expiry adds the months from the payment time. With an expiry of March 30, one month paid on April 10 runs to about May 10. The lapsed gap is not charged.

For a wallet that is not whitelisted, `paySubscription` reverts with `Is0()` when `months` is zero or the caller's rate is overridden to zero. Insufficient balance or allowance reverts without changing the expiry. For a whitelisted wallet, the call succeeds without charging, extending, or emitting an event, so the UI should not offer it.

### Deploying and subscribing in one transaction

`deployCreditVaultWithSubscription(cvParams, strategyData, ancillaryParams, months)` and `deployRevolvingCreditVaultWithSubscription(cvParams, strategyData, programmableBorrowerParams, ancillaryParams, months)` take the same parameters as the existing deployment functions, plus `uint256 months`. Each call pays `months` of the caller's subscription and then runs the matching deployment flow.

The combined calls have no return value. On success, read the deployed addresses from the `CreditVaultDeployed` event and the new expiry from the `SubscriptionPaid` event, which is emitted only when a subscription was charged.

For an unlisted wallet, approve `monthlySubscriptionFee(wallet) * months + deploymentFeeFor(wallet)`. If either payment or any deployment step fails, the whole transaction reverts, including the subscription payment. If the wallet has a zero monthly rate or chooses zero months, use `deployCreditVault` or `deployRevolvingCreditVault`. The combined calls would revert with `Is0()`.

For a whitelisted wallet, the combined calls charge no subscription and no deployment fee and set no expiry, whatever `months` is. They consume one deployment from the wallet's quota exactly like the plain deployment calls: a finite quota decreases by one, an `UNLIMITED_DEPLOYMENTS()` quota never decreases, and an exhausted quota reverts with `DeploymentLimitReached()`.

### Configuring subscription rates

Use the monthly fee field of the same `setWalletFees` entry described under [Configuring paid access](#configuring-paid-access). Rate changes apply to future payments. A wallet keeps the time it has already paid for, including when it returns to the default. On networks without a fee token, a positive custom price in either field reverts the entire batch.

## Strategy CDO binding and token rescue

Each `IdleCreditVault` strategy serves exactly one credit vault, stored in `idleCDO()`. Only that vault can mint and burn strategy tokens, move the strategy's underlying through deposits, withdrawal funding and claims, and finalize default recovery.

| Strategy owner call | Behavior |
| --- | --- |
| `setWhitelistedCDO(address cdo)` | While `idleCDO()` is zero, binds the strategy to a nonzero `cdo` and reverts with `"IS_0"` if `cdo` is the zero address. Once `idleCDO()` is set, every call reverts with `NotAllowed()`, whatever `cdo` is: the zero address, the bound address or another address. |
| `transferToken(address token, uint256 value, address to)` | Rescues an ERC-20 sent to the strategy. Reverts with `NotAllowed()` when `token` is the strategy's underlying, `token()`. |

The strategy's underlying backs funded withdrawal claims and the default recovery reserve, so it leaves the strategy only through the vault's claim, epoch and recovery flows. The restriction applies to the strategy only. The credit vault's own `transferToken`, which sends tokens to its governance recovery fund, is unchanged.

Both `deployCreditVault` and `deployRevolvingCreditVault` deploy a fresh strategy proxy owned by the factory. During setup they set the strategy APR and then bind the strategy to the new vault, before transferring ownership of both to `treasury()`. The revolving flow sets the APR to zero. After deployment, treasury cannot rebind the strategy.

The binding lives in the proxy's existing `idleCDO` storage slot, and a plain `ProxyAdmin.upgrade` does not change it. After the upgrade, a proxy that was already bound keeps its vault and rejects every later `setWhitelistedCDO` call with `NotAllowed()`, including zero-address calls. A proxy that was still unbound can be bound once by its owner, and a zero-address attempt reverts with `"IS_0"` until then. A wrong binding can no longer be corrected through the setter, so confirm that `idleCDO()` returns the intended vault before upgrading a live strategy.
