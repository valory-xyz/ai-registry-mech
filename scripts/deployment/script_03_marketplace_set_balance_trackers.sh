#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "!!! $globals is not found"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

mechMarketplaceProxyAddress=$(jq -r ".mechMarketplaceProxyAddress" $globals)
balanceTrackerFixedPriceNativeAddress=$(jq -r ".balanceTrackerFixedPriceNativeAddress" $globals)
balanceTrackerFixedPriceTokenAddress=$(jq -r ".balanceTrackerFixedPriceTokenAddress" $globals)

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

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Cast command
echo "${green}Casting from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Set balance trackers in MechMarketplaceProxy${reset}"

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
castArgs="$mechMarketplaceProxyAddress setPaymentTypeBalanceTrackers(bytes32[],address[]) [0xba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1,0x3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9] [$balanceTrackerFixedPriceNativeAddress,$balanceTrackerFixedPriceTokenAddress]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
