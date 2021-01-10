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

### Deploy

```
export MAINNET_PRIVATE_KEY=YOUR_MAINNET_KEY # without 0x prefix
npx hardhat run scripts/deploy.js --network YOUR_CONFIGURED_NETWORK
```
