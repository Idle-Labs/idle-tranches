# KeyringIdleWhitelist

Credit Vaults use the read-only `checkCredential(policyId, wallet)` function to check wallet eligibility. The adapter denies locally blacklisted wallets first. Other wallets qualify through a stored whitelist grant or a valid credential for the underlying Keyring policy.

- The admin can call `setBlacklistStatus(wallet, true)` to deny a wallet and clear its stored whitelist flag. A call to grant whitelist access while the wallet is blacklisted leaves the flag false.
- Calling `setBlacklistStatus(wallet, false)` removes the local denial. A valid Keyring credential can then make the wallet eligible. Restoring a stored whitelist grant requires a separate admin action.
- `whitelist(wallet)` reports the stored grant. Use `checkCredential` for current eligibility.

An existing Credit Vault begins using the local blacklist when configured with a newly deployed adapter.
