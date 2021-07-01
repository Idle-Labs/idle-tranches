# Idle Dynamic Tranches
The aim of Idle Dynamic Tranches is to pool capital of users (eg DAI), deposit it into a lending provider (eg Idle Finance) and split the interest received between 2 classes of users with different risk profiles.

One will gain more interest and will be more risky (BB or junior tranche) and the other will have a lower APR but more safety (AA or senior tranche). In the case of an hack or a loss of funds of the lending provider integrated (or any other protocol integrated by this provider), all funds still available will be used to refund senior tranche holders first with the aim of making them whole, and with remaining funds, if any, junior holders after.

There are no locking period or epochs and users are free to enter and exit at any time, the interest earned (and governance tokens, after being partially sold in the market) will be split between the two classes according to a predefined ratio called `trancheAPRSplitRatio` (eg 20% interest to AA holders and 80% to BB) so the rate is variable for both classes of tranches.

To determine the actual APR for each tranche class, we also need to know the ratio between the current underlying value of AA and BB tranches (ie `AAratio = AA Value / (AA Value + BB Value)`), below are some examples

![Tranche apr / value split ratio](tranches.png)

We can see that when the `AAratio == trancheAPRSplitRatio` we have the same APR of the lending provider (8%).

Given that AA have intrinsically less risk (due the liquidation priority over BB holders) they should also have a lower APR than BB, so ideally `AAratio > trancheAPRSplitRatio` (eg if the interest for AA is 20% of the total interest earned then more than 20% of the total tranches value should be of AA tranches). This behaviour should be market driven given the different rights the users have in case of hack.

The ratio between tranches heavily influences the APR of both classes of users and the aim should be to have different results with regard to the basic lending provider but not too much skewed otherwise one of the two classes won't have enough holders due to the low APR. For this reason a `trancheIdealWeightRatio` is set during initialization (and can be updated) which represent the ideal ratio, in value, that AA and BB should have to have an APR suitable for both classes of users.

For example in the image above, where we are splitting the interest 20% to AA and 80% to BB, an ideal AA ratio could be 50% because it would mean that holders of 50% of the pool (which are generating 50% of the interest) are retaining only the 20% of the total interest, so the APR of BB holders will be higher than the normal lending provider (12.8% vs the 8% in the example) and the one of AA is not too low considering it's liquidation priority.

To incentivize the reach of `trancheIdealWeightRatio` part of farmed governance tokens (eg stkAAVE or IDLE) are redistributed to users who stakes their tranche tokens in specific tranche rewards contracts.

In case of hack, an emergency shutdown can be triggered (by both the `guardian`, which would be a multi-sig wallet, and the `owner` which will be the Idle governance) in order to pause both deposits and redeems, the redistribution of remaining funds can happens selectively, by allowing only AA holders to withdraw first directly in the main contract, or through a separate contract for more complex cases and resolutions (managed by the Idle governance).

A Fee is collected on harvests in the form AA or BB supply diluition (based on the current AA ratio in value) and it's basically a performance fee, currently set at 10% of the interest generated and it will be redirected to the Idle fee collector address.

## Architecture
The main contract which will be used by users is `IdleCDO` which allow to deposits underlying and mint tranche tokens (ERC20), either AA or BB, and redeem principal+interest from it.

The IdleCDO references an `IIdleCDOStrategy` and the first strategy proposed is `IdleStrategy` which uses [Idle finance](http://idle.finance/) as a lending provider. IdleCDO should be able to change its strategy without impact, so it's possibile to change the lending provider (assuming the position have been previously withdrawn). Governance tokens collected as rewards, are not redistributed to users directly in the IdleCDO contract but rather sold to the market (`harvest` method) and the underlyings reinvested in the downstream lending provider where possibile. For other tokens, eg IDLE that won't be sold or stkAAVE that have no liquid markets due to locking, those will get redistributed to people who staked their tranches in a separate `IdleCDOTrancheRewards` contract (one for AA and one for BB).

These are the main contracts used:

- **IdleCDO.sol**: contract which holds all the users pooled assets (both underlyings, eg DAI, and interest bearing tokens, eg idleDAI) and entry point for the user to mint tranche tokens and burn them to redeem principal + interest.
When users deposit into the CDO they will: update the global accounting of the system (ie split accrued rewards) and mint their choosen tranche tokens. Funds won't get put in lending right away. The `harvest` method will be called periodically to put new deposits in lending, get fees and update the accounting. During the harvest call some predefined rewards will be sold into the market (via uniswap) to increase the value of all tranche holders, and part of the gov tokens will be sent to IdleCDOTrancheRewards contracts, if those are presetn, to incentivize the ideal ratio `trancheIdealWeightRatio`. On redeem users will burn their tranche tokens and get underlyings using a checkpointed price (set at last harvest to avoid potential theft of interest, updated when dumping gov tokens to increase the tranche price)

- **IdleCDOTrancheRewards.sol**: contract for staking tranche tokens and getting rewards (for incentivizing the `trancheIdealWeightRatio`)
- **IdleCDOTranche.sol**: ERC20 representing a specific (either AA or BB) tranche token. Only IdleCDO contract can mint and burn tranche tokens.
- **IdleStrategy.sol**: IdleCDO strategy for lending assets in Idle Finance. This contract it's just a proxy for interacting with Idle Finance and should have no funds at end of each transaction. More info on how idleTokens works can be found [here](https://developers.idle.finance). The tldr of the Idle Finance protocol is this (using DAI as an example):
In Idle Finance you deposit DAI to earn interest, on deposits you get back idleDAI, an interest bearing token that always increase in price and represent your position in Idle + the interest earned by that position (similar to Compound's cTokens). Idle lend those funds to other protocols such as Compound and Aave and continously rebalance the pooled user funds in order to achieve the highest avg yield. On redeems you burn your idleDAI and get back DAI principal + DAI earned as interest + a set of governance tokens rewards (currently IDLE, COMP, stkAAVE)

Notes:
- IdleCDO, IdleStrategy and IdleCDOTrancheRewards are upgradable contracts.
- There are no 'loose' scripts but only hardhat tasks which are used both for interacting with contracts and tests in fork (`integration` task)
- The `integration` task should be useful also to understand the complete workflow

## Setup

```
yarn install
```

## Unit Tests

```
npx hardhat test
```

## Integration tests (in fork)

Copy the `.env.public` in a new `.env` file and fill out the keys OR in terminal:

```
export ALCHEMY_API_KEY=XXXX
```
then uncomment the
```
forking: {
  url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
  blockNumber: 12554260, // DAI all in compound
}
```
block in `hardhat.config.js` and then run

```
npx hardhat integration
```
or any other tasks in `tasks/*`

## Deploy

```
npx hardhat deploy --network YOUR_CONFIGURED_NETWORK
```

## Coverage

```
npx hardhat coverage
```
