#!/bin/bash

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' globals.json)
useLedger=$(jq -r '.useLedger' globals.json)
derivationPath=$(jq -r '.derivationPath' globals.json)
gasPriceInGwei=$(jq -r '.gasPriceInGwei' globals.json)
chainId=$(jq -r '.chainId' globals.json)
networkURL=$(jq -r '.networkURL' globals.json)

didRegistryAddress=$(jq -r '.didRegistryAddress' globals.json)
transferNFTConditionAddress=$(jq -r '.transferNFTConditionAddress' globals.json)
escrowPaymentConditionAddress=$(jq -r '.escrowPaymentConditionAddress' globals.json)

# Check for Polygon keys only since on other networks those are not needed
if [ $chainId == 137 ]; then
  API_KEY=$ALCHEMY_API_KEY_MATIC
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MATIC env variable"
      exit 0
  fi
elif [ $chainId == 80002 ]; then
    API_KEY=$ALCHEMY_API_KEY_AMOY
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_AMOY env variable"
        exit 0
    fi
fi

contractPath="contracts/mechs/nevermined/utils/SubscriptionProvider.sol:SubscriptionProvider"
constructorArgs="$didRegistryAddress $transferNFTConditionAddress $escrowPaymentConditionAddress"
contractArgs="$contractPath --constructor-args $constructorArgs"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Deployment message
echo "Deploying from: $deployer"
echo "Deployment of: $contractArgs"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
subscriptionProviderAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#subscriptionProviderAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "!!! The contract was not deployed, aborting..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"subscriptionProviderAddress":"'$subscriptionProviderAddress'"}' globals.json)" > globals.json

# Verify contract
if [ "$contractVerification" == "true" ]; then
  echo "Verifying contract..."
  forge verify-contract \
    --chain-id "$chainId" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    "$subscriptionProviderAddress" \
    "$contractPath" \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" $constructorArgs)
fi

echo "Contract deployed at: $subscriptionProviderAddress"