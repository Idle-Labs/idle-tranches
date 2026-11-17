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
  arguments). With `discount = 0` the oracle returns exactly the original `int256(virtualPrice)` for every input.
- **Bounds**: any discount above `1e18` (100%) reverts the constructor with `DiscountTooHigh()`. A discount of exactly
  `1e18` is accepted and prices the collateral at zero.
- **Rounding**: the result is rounded down, so the collateral is never valued above the exact discounted price. For
  example a `virtualPrice` of `1` with a 5% discount returns `0`.
- **Arithmetic**: the calculation splits `virtualPrice = q * 1e18 + r` and computes
  `q * (1e18 - discount) + r * (1e18 - discount) / 1e18`. This gives the same floor-rounded result without
  intermediate overflow for any `uint256` price: the remainder product is below `1e36`, and the sum never exceeds
  the original price. There is no longer an intermediate-product price limit.
- **Signed answer**: the final `uint256` to `int256` conversion is unchanged from the original adapter. Nonnegative
  answers require the discounted result to be at most `type(int256).max`; larger results retain the existing
  two's-complement conversion to negative values. No new range check is introduced.

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

`TestTranchesChainlinkOracle` in `test/foundry/MetamorphoIdleVault.t.sol` has an independent mock setup (no fork).
It covers zero discount, the 5% example, boundary discounts (`0`, `1`, `1e18 - 1`, `1e18`, `1e18 + 1`,
`type(uint256).max`), floor rounding, large prices above the former multiplication limits, the existing signed
conversion, deployment-script forwarding and freshly compiled runtime size against EIP-170.

Run this contract independently of the existing fork suite:

```
forge test --offline --evm-version london --match-contract '^TestTranchesChainlinkOracle$'
```
