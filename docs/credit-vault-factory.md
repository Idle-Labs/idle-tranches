# Credit Vault factory deployment fee

The Credit Vault factory supports paid access on Ethereum mainnet, Base, and Arbitrum One. An unlisted wallet can pay a fixed amount of the network's native USDC each time it calls `deployCreditVault` or `deployRevolvingCreditVault`. The factory sends the fee directly to its `treasury()`, the network's treasury multisig. The vault's underlying asset and its performance and management fees are configured independently.

## Deploying from an unlisted wallet

1. Read `deploymentFeeToken()` and `deploymentFee()` from the factory proxy. The fee uses six-decimal USDC units, so `5_000_000_000` represents 5,000 USDC.
2. Approve the factory proxy to spend the fee in that USDC token.
3. Call the factory's standard or revolving deployment function. Both entry points use the fee in effect when the transaction executes.

Each deployment uses a separate fee from the caller's balance and allowance. Insufficient balance or allowance reverts the transaction. If vault setup reverts after the transfer, the USDC balances and allowance are restored along with the rest of the transaction state.

Whitelisted callers continue to use their deployment quotas without paying USDC. An exhausted quota requires replenishment to use the whitelisted path. Removing a wallet from the whitelist makes it eligible to use paid access when enabled.

## Configuring paid access

The factory treasury can call `setDeploymentFee(uint256)` to enable paid access or change the fee for future deployments. Set the fee to zero to disable paid access. The initial fee is zero for both new factories and existing factories upgraded to this implementation. On other networks, `deploymentFeeToken()` returns the zero address and setting a positive fee reverts.
