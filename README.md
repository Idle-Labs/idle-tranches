# Idle Perpetual Yield Tranches

## Intro
The aim of Idle Perpetual Yield Tranches is to pool capital of users (eg DAI), deposit it into a lending provider and split the interest received between 2 classes of users with different risk profiles.

One will gain more interest and will be more risky (BB or junior tranche) and the other will have a lower APR but more safety (AA or senior tranche). In the case of an hack or a loss of funds of the lending provider integrated (or any other protocol integrated by this provider), all funds still available will be used to refund senior tranche holders first with the aim of making them whole, and with remaining funds, if any, junior holders after.

There are no locking period or epochs and users are free to enter and exit at any time, the interest earned (and governance tokens, after being sold in the market) will be split between the two classes according to a dynamic ratio called `trancheAPRSplitRatio` which is updated, based on the TVL of both tranches, at each deposit/redeem. The apr is variable for both classes of tranches.

## Docs

https://docs.idle.finance/developers/perpetual-yield-tranches

## Architecture
The main contract which will be used by users is `IdleCDO` which allows to deposit underlying and mint tranche tokens (ERC20), either AA or BB, and redeem principal+interest from it.

The IdleCDO uses an `IIdleCDOStrategy` for interacting with a specific lending protocol. Governance tokens collected as rewards, are not redistributed to users directly in the IdleCDO contract but rather sold to the market (`harvest` method) and the underlyings reinvested in the downstream lending provider where possible.

These are the main contracts used:

- **IdleCDO.sol**: contract which holds all the users pooled assets (both underlyings, eg DAI, and interest bearing tokens, eg cDAI or aDAI) and entry point for the user to mint tranche tokens and burn them to redeem principal + interest.
When users deposit into the CDO they will: update the global accounting of the system (ie split accrued rewards) and mint their chosen tranche tokens. Funds won't get put in lending right away. The `harvest` method will be called periodically to put new deposits in lending, get fees and update the accounting. During the harvest call  rewards will be sold into the market (via uniswap) and released linearly over x (currently set a 6400) blocks, to increase the value of all tranche holders. On redeem users will burn their tranche tokens and get underlyings back.

- **IdleCDOTranche.sol**: ERC20 representing a specific (either AA or BB) tranche token. Only IdleCDO contract can mint and burn tranche tokens.

- **strategies/\*\*.sol**: strategies for lending assets in different lending providers.


## Setup

```
yarn install
forge install
```
For foundry setup [here](https://book.getfoundry.sh/getting-started/installation.html)

* One line change is needed in node_modules/@uniswap/v3-core/contracts/libraries/FullMath.sol to make compilation working see -> https://ethereum.stackexchange.com/questions/96642/unary-operator-minus-cannot-be-applied-to-type-uint256

## Tests

Tests were initially done using Hardhat and then new ones with Foundry. Foundry tests are located in `test/foundry/` and are the ones that should be used for testing new features.
New tests should be written using Foundry.

### Old tests with Hardhat

For unit tests run:

```
yarn test
```

## Test with Foundry

For foundry tests (located in `test/foundry/`) run:

```
forge test -vvv
```
or 

```
forge test -vvv --match-contract=MyTestContract
```
to run a specific test.

## Deploy with Hardhat

Deployment of new IdleCDOs is done with Hardhat using a factory contract which will deploy a new IdleCDO and initialize it with the correct params.

```
npx hardhat deploy-with-factory-params --network YOUR_CONFIGURED_NETWORK --cdoname CDO_NAME 
```

`CDO_NAME` should be the name of the key of the `deployTokens` object in `utils/addresses.js` with all params for deployment.
This is an example of config for deploying an IdleCDO with Lido strategy:
```
  lido: {
    underlying: mainnetContracts.stETH,    // underlying token for the IdleCDO
    decimals: 18,                          // underlying token decimals
    proxyCdoAddress: CDOs.idleDAI.cdoAddr, // address of another IdleCDO where we will get the implementation to use
    strategyName: 'IdleLidoStrategy',      // name of the strategy contract
    strategyParams: [                      // strategy params for `initialize` call
      mainnetContracts.wstETH,
      mainnetContracts.stETH,
      'owner'                              // The string 'owner' can be used to replace a specific address with the deployer of the strategy
    ],
    AAStaking: false,                      // if rewards are distributed in IdleCDO to AA holders
    BBStaking: false,                      // if rewards are distributed in IdleCDO to BB holders
    stkAAVEActive: false,                  // if IdleCDO needs to manage stkAAVE
    limit: '1000000',                      // deposit limit for this IdleCDO
    AARatio: '10000'                       // Interest rate split for AA holders. `100000` means 100% to AA
  },
```

## Testing deployment with Foundry + Hardhat
Start with

```
anvil -f https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --fork-block-number XXXXX
```

Then run the deployment with hardhat script to deploy everything on anvil network
```
npx hardhat deploy-with-factory-params --cdoname cpwinusdc --network local
```

then run the forge test against anvil network (using the deployed IdleCDO address)

```
forge test --fork-url http://127.0.0.1:8545/ --match-contract=MyTest -vvv
```

## Code Contributions
Note this repo was built using hardhat so most tests and scripts are in js. Foundry was also recently integrated and we encourage all new contributions and features to be tested using the foundry toolkit.

We welcome new contributors and code contributions with open arms! Please be sure to follow our contribution [guidelines](https://github.com/Idle-Labs/idle-tranches/blob/master/CONTRIBUTING.md) when proposing any new code. Idle Finance is a
decentralized protocol managed by a decentralized governance, any new code contributions are more likely to be accepted into future deployments and proposals if they have been openly discussed within the community first in our forum https://gov.idle.finance/
