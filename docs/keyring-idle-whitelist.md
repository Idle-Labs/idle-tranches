# KeyringIdleWhitelist

`KeyringIdleWhitelist.checkCredential(policyId, wallet)` is the read-only eligibility check used by the Credit Vault. It checks the adapter's local blacklist first, then the Chainalysis sanctions oracle. A wallet that passes both checks must have a stored whitelist grant or satisfy the underlying Keyring policy.

- The whitelist admin can call `setBlacklistStatus(wallet, true)` to deny a wallet and clear its stored whitelist flag. Removing the blacklist entry lets the wallet be screened again. A new whitelist grant requires a separate admin action.
- Chainalysis listings deny eligibility immediately. Anyone can submit a `syncSanctions(wallet)` transaction to clear a stored grant while the wallet is listed. The `whitelist(wallet)` getter reports the stored flag. Use `checkCredential` for current eligibility.
- `setWhitelistStatus(wallet, true)` screens the wallet against both lists. If either denies the wallet, the stored flag is set to `false`. The admin can revoke a grant with `setWhitelistStatus(wallet, false)` even during an oracle outage.

## Supported networks

The adapter accepts Ethereum mainnet (chain ID 1) and Arbitrum One (chain ID 42161). It uses the Chainalysis oracle at `0x40C57923924B5c5c5455c48D93317139ADDaC8fb` on both networks. Construction requires a valid response from the oracle's `isSanctioned` function. Other chain IDs, including Base, revert at construction. Factory transactions that request a Keyring adapter inherit this guard. [Ethereum oracle](https://etherscan.io/address/0x40C57923924B5c5c5455c48D93317139ADDaC8fb) · [Arbitrum One oracle](https://arbiscan.io/address/0x40C57923924B5c5c5455c48D93317139ADDaC8fb)

The configured Foundry suite exercises the deployed oracle on Ethereum snapshots, including blocks 14,500,000 and 22,525,130 for the before-and-after sanctions test. A separate public-RPC fork probe on Arbitrum One confirmed adapter deployment, a positive sanctions lookup, and eligibility for a granted, unflagged wallet. The configured suite exercises Base rejection by setting the chain ID in a test.

If the oracle later becomes unavailable, eligibility checks and grants that reach the oracle revert. An existing Credit Vault begins using the new checks when configured with a newly deployed adapter.
