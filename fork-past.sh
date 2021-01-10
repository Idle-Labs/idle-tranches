if [ $# -lt 2 ]; then
  echo "USAGE:";
  echo "./fork NETWORK_NAME BLOCK_NUMBER";
  echo
  echo "for mainnet block 11615912:";
  echo "./fork-past.sh mainnet 11615912";
  echo
  echo "for kovan block 11615912:";
  echo "./fork-past.sh kovan 11615912";
  exit 1;
fi

npx hardhat node \
  --fork https://eth-$1.alchemyapi.io/v2/$ALCHEMY_KEY \
  --fork-block-number $2
