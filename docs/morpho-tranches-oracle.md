# Morpho tranche oracle (`TranchesChainlinkOracle`)

`contracts/strategies/morpho/TranchesChainlinkOracle.sol` is a Chainlink-style price feed (`IAggregatorV3Minimal`) that
prices an Idle tranche token in the underlying (loan) token of its CDO using `cdo.virtualPrice(tranche)`. It is meant to
be the base feed of a `MorphoChainlinkOracleV2`: the adapter alone is not the Morpho market oracle.

## Discount

The adapter can apply a fixed discount to the tranche `virtualPrice`, so that the collateral is valued below its
virtual price in a Morpho market.

```
price = virtualPrice * (1e18 - discount) / 1e18
```

- **Units**: `discount` is a fixed-point number scaled by `DISCOUNT_SCALE = 1e18`, where `1e18` is 100%. For example
  `5e16` is 5% and `1e16` is 1%.
- **Price units**: the returned price keeps the units of the `virtualPrice`, which has the same decimals as the loan token
  (`decimals()` is unchanged). With a 6 decimals loan token, a `virtualPrice` of `1_000_000` (1.0) and a 5% discount returns
  `950_000` (0.95).
- **Default**: the default discount is zero, which must be passed explicitly (Solidity constructors have no default
  arguments). With `discount = 0` the tranche is valued at its undiscounted `virtualPrice`.
- **Bounds**: any discount above `1e18` (100%) reverts the constructor with `DiscountTooHigh()`. A discount of exactly
  `1e18` is accepted and prices the collateral at zero.
- **Rounding**: the result is rounded down, so the collateral is never valued above the exact discounted price. For
  example a `virtualPrice` of `1` with a 5% discount returns `0`.

## Immutable configuration

The discount is set once in the constructor and stored as an `immutable` (`discount()`). There is no setter, owner or
upgrade path. Changing the discount requires deploying a new adapter, a new `MorphoChainlinkOracleV2` and, because the
oracle is part of the market parameters, a new Morpho market.

## Signature changes

| Item | Before | After |
| --- | --- | --- |
| `TranchesChainlinkOracle` constructor | `constructor(address _trancheToken)` | `constructor(address _trancheToken, uint256 _discount)` |
| `DeployMetamorphoVault.deployOracle` | `deployOracle(address collateralToken, IMetaMorphoOracleFactory oracleFactory)` | `deployOracle(address collateralToken, IMetaMorphoOracleFactory oracleFactory, uint256 discount)` |
| New on the adapter | - | `discount()`, `DISCOUNT_SCALE()`, `error DiscountTooHigh()` |

Oracles already deployed with the old constructor are not affected and keep returning the undiscounted `virtualPrice`.
`DeployMetamorphoVault._initializeTrancheMarket` passes `0`, so the market it creates is priced as before.

Deploying a discounted oracle with the script entrypoint (broadcast and verification flags as for the other deployment
scripts in this repository):

```
forge script ./forge-scripts/DeployMetamorphoVault.s.sol \
  --sig "deployOracle(address,address,uint256)" <trancheToken> <morphoOracleFactory> 50000000000000000
```

`50000000000000000` is a 5% discount.

## Tests

`TestTranchesChainlinkOracle` in `test/foundry/MetamorphoIdleVault.t.sol` forks mainnet at block `22_525_130`
using the repository's `mainnet` RPC endpoint (`ETH_RPC_URL`). It exercises the deployed Fasanara USDC and Lido stETH
CDOs for 6- and 18-decimal pricing and the deployed Morpho factory for deployment-script forwarding and market-oracle
pricing. Only the exact unit-price, rounding and price-change scenarios mock the CDO's `virtualPrice` return.

Coverage includes zero and 5% discounts, boundary discounts (`0`, `1`, `1e18 - 1`, `1e18`, `1e18 + 1`,
`type(uint256).max`), floor rounding and freshly compiled runtime size against EIP-170.

Run the oracle suite with `ETH_RPC_URL` configured:

```
forge test --offline --evm-version london --match-contract '^TestTranchesChainlinkOracle$'
```
