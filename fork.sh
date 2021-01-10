if [ -z "$1" ]; then
  echo "USAGE:";
  echo "./fork NETWORK_NAME";
  echo
  echo "for mainnet:";
  echo "./fork mainnet";
  echo
  echo "for kovan:";
  echo "./fork mainnet";
  exit 1;
fi

npx hardhat node \
  --fork https://$1.infura.io/v3/$IDLE_INFURA_KEY
