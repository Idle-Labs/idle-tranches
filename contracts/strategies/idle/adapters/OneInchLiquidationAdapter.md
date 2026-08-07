# OneInchLiquidationAdapter quick guide

This adapter lets `CollateralsVault` liquidate collateral via 1inch Aggregation Router v5 using off-chain quoted calldata.

## Deploy
- Deploy `OneInchLiquidationAdapter` with the 1inch router address for your chain (v5).
- Allow it in the vault: `setLiquidationAdapter(adapter, true)`.

## Off-chain quote
1. Call 1inch API swap endpoint (v5) with:
   - `fromToken` = collateral token
   - `toToken` = borrowed token
   - `amount` = collateral amount to sell
   - `fromAddress` = adapter address
   - `slippage` = your tolerance (e.g. 1)
2. Extract from the response:
   - `executor` (often `tx.to` or `protocolExecutor`)
   - `tx.data` (swap calldata)
   - `toTokenAmount` (quote)
3. Compute `minOut` = `toTokenAmount * (1 - slippage)` for on-chain protection.
4. Build `swapData` = `abi.encode(executor, tx.data)`.

## On-chain call (vault.liquidate)
For each collateral index:
- `collateralsToLiquidate[i]` = collateral token address
- `minBorrowedOut[i]` = per-leg `minOut`
- `adapters[i]` = adapter address
- `swapDatas[i]` = encoded `(executor, data)` from API

The vault will:
- Transfer collateral to the adapter
- Approve router and execute 1inch swap
- Enforce `minOut` per collateral
- Keep borrowed tokens in the vault (virtual repayment) and send penalty to `penaltyReceiver`

## Notes
- Adapter expects ERC20 -> ERC20 (no native ETH path); provide wrapped tokens.
- Always simulate off-chain first with the exact calldata/amounts and set `minOut` defensively.
- If a collateral leg should be skipped, omit it from the arrays.
