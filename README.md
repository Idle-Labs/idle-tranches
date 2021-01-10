## Setup

`yarn install`


## Tests

`yarn test`

## Integration test with network fork

Start a mainnet fork:

```
export IDLE_INFURA_KEY=YOUR_INFURA_KEY
./fork.sh mainnet # or ./fork.sh kovan
```

Run the integration test:

```
npx hardhat run scripts/integration_test.js --network local
```


### Deploy

```
export MAINNET_PRIVATE_KEY=YOUR_MAINNET_KEY # without 0x prefix
npx hardhat run scripts/deploy.js --network YOUR_CONFIGURED_NETWORK
```

## Batches stats

```
npx hardhat stats --network kovan --address 0xB9f068bDAe0D7C4796A04f59d0DEF33Ac784AfB4
```
