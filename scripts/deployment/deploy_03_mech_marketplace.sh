#!/bin/bash
set -euo pipefail

red=$(tput setaf 1 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

fail() { echo "Error: $*" >&2; exit 1; }
address() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ && "$1" != 0x0000000000000000000000000000000000000000 ]] || fail "Invalid address: $2"
  local code
  code=$(cast code --rpc-url "$networkURL$API_KEY" "$1" 2>/dev/null) || fail "Cannot read contract code: $2"
  [[ "$code" =~ ^0x[0-9a-fA-F]+$ && "$code" != 0x0 ]] || fail "No contract code: $2"
}
check() {
  local actual expected=$3 message=$4
  actual=$(cast call --rpc-url "$networkURL$API_KEY" "$1" "$2" "${@:5}" 2>/dev/null) || fail "$message (read failed)"
  actual=$(echo "$actual" | tr -d '"' | tr '[:upper:]' '[:lower:]')
  expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
  [[ "$actual" == "$expected" ]] || fail "$message"
}

# Check if $1 is provided
if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "${red}!!! Usage: $0 <network>${reset}"
  echo "${red}Example: $0 eth_mainnet${reset}"
  exit 1
fi

# Get globals file
globals="$(cd "$(dirname "$0")" && pwd)/globals_$1.json"
if [ ! -f "$globals" ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 1
fi

# Read variables using jq
contractVerification=$(jq -er '.contractVerification | if type == "boolean" then tostring else error("contractVerification must be boolean") end' "$globals")
useLedger=$(jq -er '.useLedger | if type == "boolean" then tostring else error("useLedger must be boolean") end' "$globals")
derivationPath=$(jq -r '.derivationPath' "$globals")
chainId=$(jq -er '.chainId' "$globals")
networkURL=$(jq -er '.networkURL' "$globals")

# check if the ETHERSCAN_API_KEY is set
if [ "$contractVerification" == "true" ] && [ -z "${ETHERSCAN_API_KEY:-}" ]; then
  echo "${red}!!! Set the ETHERSCAN_API_KEY environment variable${reset}"
  exit 1
fi


API_KEY=""
# Check for Alchemy keys on ETH, Polygon mainnets and testnets
if [ "$chainId" == 1 ] && [[ "$networkURL" == https://*.g.alchemy.com/v2/ ]]; then
  API_KEY=${ALCHEMY_API_KEY_MAINNET:-}
  if [ "$API_KEY" == "" ]; then
      echo "${red}!!! Set ALCHEMY_API_KEY_MAINNET env variable${reset}"
      exit 1
  fi
elif [ "$chainId" == 11155111 ] && [[ "$networkURL" == https://*.g.alchemy.com/v2/ ]]; then
    API_KEY=${ALCHEMY_API_KEY_SEPOLIA:-}
    if [ "$API_KEY" == "" ]; then
        echo "${red}!!! Set ALCHEMY_API_KEY_SEPOLIA env variable${reset}"
        exit 1
    fi
elif [ "$chainId" == 137 ] && [[ "$networkURL" == https://*.g.alchemy.com/v2/ ]]; then
  API_KEY=${ALCHEMY_API_KEY_MATIC:-}
  if [ "$API_KEY" == "" ]; then
      echo "${red}!!! Set ALCHEMY_API_KEY_MATIC env variable${reset}"
      exit 1
  fi
elif [ "$chainId" == 80002 ] && [[ "$networkURL" == https://*.g.alchemy.com/v2/ ]]; then
    API_KEY=${ALCHEMY_API_KEY_AMOY:-}
    if [ "$API_KEY" == "" ]; then
        echo "${red}!!! Set ALCHEMY_API_KEY_AMOY env variable${reset}"
        exit 1
    fi
fi

rpcChainId=$(cast chain-id --rpc-url "$networkURL$API_KEY" 2>/dev/null) || fail "Cannot read RPC chain ID"
[[ "$rpcChainId" == "$chainId" ]] || fail "RPC chain ID does not match configuration"

serviceRegistryAddress=$(jq -er '.serviceRegistryAddress' "$globals")
karmaProxyAddress=$(jq -er '.karmaProxyAddress' "$globals")

contractName="MechMarketplace"
contractPath="contracts/$contractName.sol:$contractName"
constructorArgs=("$serviceRegistryAddress" "$karmaProxyAddress")
contractArgs=("$contractPath" --constructor-args "${constructorArgs[@]}")

address "$serviceRegistryAddress" serviceRegistryAddress
address "$karmaProxyAddress" karmaProxyAddress
cd "$(dirname "$globals")/../.."
forge build --use "${FOUNDRY_SOLC:-0.8.30}" --out out --skip ImportWETH.sol --skip Proposal01FeeActivation >/dev/null 2>&1 || fail "Cannot build current contracts"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs=(-l --mnemonic-derivation-path "$derivationPath")
  deployer=$(cast wallet address "${walletArgs[@]}" 2>/dev/null) || fail "Cannot read wallet address"
else
  [[ -n "${PRIVATE_KEY:-}" ]] || fail "Set PRIVATE_KEY or useLedger=true"
  walletArgs=(--private-key "$PRIVATE_KEY")
  deployer=$(cast wallet address "${walletArgs[@]}" 2>/dev/null) || fail "Cannot read wallet address"
fi

# Deployment message
echo "${green}Deploying from: $deployer${reset}"
echo "${green}Deployment of: ${contractArgs[*]}${reset}"

# Deploy the contract and capture the address
execCmd=(forge create --broadcast --json --use "${FOUNDRY_SOLC:-0.8.30}" --skip ImportWETH.sol --skip Proposal01FeeActivation --rpc-url "$networkURL$API_KEY" "${walletArgs[@]}" "${contractArgs[@]}")
if ! deploymentOutput=$("${execCmd[@]}" 2>/dev/null); then
  transactionHash=$(jq -r '.transactionHash // empty' <<< "$deploymentOutput" 2>/dev/null || true)
  if [[ "$transactionHash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then echo "Inspect transaction: $transactionHash" >&2; fi
  fail "Deployment command failed; inspect wallet transactions before retrying"
fi
mechMarketplaceAddress=$(jq -er '.deployedTo' <<< "$deploymentOutput") || fail "Invalid deployment output"

# Get output length
outputLength=${#mechMarketplaceAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 1
fi

[[ "$mechMarketplaceAddress" =~ ^0x[0-9a-fA-F]{40}$ && "$mechMarketplaceAddress" != 0x0000000000000000000000000000000000000000 ]] || fail "Invalid address: deployedAddress"
transactionHash=$(jq -er '.transactionHash | select(test("^0x[0-9a-fA-F]{64}$"))' <<< "$deploymentOutput") || fail "Missing deployment transaction hash"
echo "Deployment transaction: $transactionHash"
receipt=$(cast receipt --json --rpc-url "$networkURL$API_KEY" "$transactionHash" 2>/dev/null) || fail "Cannot read deployment receipt; inspect the transaction before retrying"
jq -e '(.status == "0x1" or .status == 1 or .status == "1") and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$receipt" >/dev/null || fail "Missing or unsuccessful transaction receipt"
jq -e --arg tx "$transactionHash" --arg contract "$mechMarketplaceAddress" '(.transactionHash | ascii_downcase) == ($tx | ascii_downcase) and (.contractAddress | ascii_downcase) == ($contract | ascii_downcase)' <<< "$receipt" >/dev/null || fail "Deployment receipt does not match the transaction and address"
address "$mechMarketplaceAddress" deployedAddress
check "$mechMarketplaceAddress" 'VERSION()(string)' 1.2.0 "Wrong Marketplace version"
check "$mechMarketplaceAddress" 'serviceRegistry()(address)' "$serviceRegistryAddress" "Wrong service registry"
check "$mechMarketplaceAddress" 'karma()(address)' "$karmaProxyAddress" "Wrong Karma contract"
MARKETPLACE_RPC_URL="$networkURL$API_KEY" python3 scripts/deployment/check_marketplace_implementation.py \
  --implementation "$mechMarketplaceAddress" --chain-id "$chainId" \
  --registry "$serviceRegistryAddress" --karma "$karmaProxyAddress"

# Write new deployed contract back into JSON
temporary=$(mktemp "$globals.tmp.XXXXXX")
trap 'rm -f "$temporary"' EXIT
jq --arg address "$mechMarketplaceAddress" '. += {"mechMarketplaceAddress":$address}' "$globals" > "$temporary"
mv "$temporary" "$globals"
trap - EXIT

# Verify contract
if [ "$contractVerification" == "true" ]; then
  encodedConstructor=$(cast abi-encode "constructor(address,address)" "${constructorArgs[@]}" 2>/dev/null) || fail "Cannot encode constructor"
  contractParams=("$mechMarketplaceAddress" "$contractPath" --constructor-args "$encodedConstructor")
  echo "Verification contract params: ${contractParams[*]}"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --watch --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" "${contractParams[@]}" >/dev/null 2>&1 || fail "Explorer verification failed; address is saved. Verify it separately; do not redeploy"

  blockscoutURL=$(jq -r '.blockscoutURL' "$globals")
  if [ "$blockscoutURL" != "null" ] && [ -n "$blockscoutURL" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --watch --chain "$chainId" --verifier blockscout --verifier-url "$blockscoutURL/api" "${contractParams[@]}" >/dev/null 2>&1 || fail "Blockscout verification failed; address is saved. Verify it separately; do not redeploy"
  fi
fi

echo "${green}$contractName deployed at: $mechMarketplaceAddress${reset}"
