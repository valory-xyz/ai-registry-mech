#!/bin/bash
set -euo pipefail

red=$(tput setaf 1 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

fail() { echo "Error: $*" >&2; exit 1; }
address() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ && "$1" != 0x0000000000000000000000000000000000000000 ]] || fail "Invalid address: $2"
  local code
  code=$(cast code --rpc-url "$networkURL" "$1" 2>/dev/null) || fail "Cannot read contract code: $2"
  [[ "$code" =~ ^0x[0-9a-fA-F]+$ && "$code" != 0x0 ]] || fail "No contract code: $2"
}
check() {
  local actual expected=$3 message=$4
  actual=$(cast call --rpc-url "$networkURL" "$1" "$2" "${@:5}" 2>/dev/null) || fail "$message (read failed)"
  actual=$(echo "$actual" | tr -d '"' | tr '[:upper:]' '[:lower:]')
  expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
  [[ "$actual" == "$expected" ]] || fail "$message"
}

# Read the selected network configuration; do not log credential-bearing URLs.
[[ "${1:-}" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Usage: $0 <network>"
scriptDirectory=$(cd "$(dirname "$0")" && pwd)
globals="$scriptDirectory/globals_$1.json"
[[ -f "$globals" ]] || fail "Configuration not found"
for tool in jq cast forge; do command -v "$tool" >/dev/null || fail "Missing dependency: $tool"; done
jq -e 'type == "object"' "$globals" >/dev/null || fail "Invalid configuration JSON"
chainId=$(jq -er '.chainId' "$globals")
[[ "$chainId" =~ ^[1-9][0-9]*$ ]] || fail "Invalid chainId"
networkURL=$(jq -er '.networkURL' "$globals")
[[ "$networkURL" == http://* || "$networkURL" == https://* ]] || fail "Invalid networkURL"
API_KEY=""
# Complete URLs need no Alchemy key, regardless of chain.
if [[ "$networkURL" == https://*.g.alchemy.com/v2/ ]]; then
  case "$chainId" in
    1) API_KEY=${ALCHEMY_API_KEY_MAINNET:-};;
    11155111) API_KEY=${ALCHEMY_API_KEY_SEPOLIA:-};;
    137) API_KEY=${ALCHEMY_API_KEY_MATIC:-};;
    80002) API_KEY=${ALCHEMY_API_KEY_AMOY:-};;
  esac
  [[ -n "$API_KEY" ]] || fail "Supply the Alchemy key or a complete networkURL"
fi
networkURL+="$API_KEY"
rpcChainId=$(cast chain-id --rpc-url "$networkURL" 2>/dev/null) || fail "Cannot read RPC chain ID"
[[ "$rpcChainId" == "$chainId" ]] || fail "RPC chain ID does not match configuration"
cd "$scriptDirectory/../.."

[[ $# == 1 ]] || fail "Usage: $0 <network>"
contractVerification=$(jq -er '.contractVerification | if type == "boolean" then tostring else error("contractVerification must be boolean") end' "$globals")
if [[ "$contractVerification" == true ]]; then
  [[ -n "${ETHERSCAN_API_KEY:-}" ]] || fail "Set ETHERSCAN_API_KEY for verification"
fi
serviceRegistryAddress=$(jq -er '.serviceRegistryAddress' "$globals")
karmaProxyAddress=$(jq -er '.karmaProxyAddress' "$globals")
address "$serviceRegistryAddress" serviceRegistryAddress
address "$karmaProxyAddress" karmaProxyAddress
constructorArgs=("$serviceRegistryAddress" "$karmaProxyAddress")
constructorType='constructor(address,address)'
contractName=MechMarketplace
contractPath="contracts/$contractName.sol:$contractName"
encodedConstructor=$(cast abi-encode "$constructorType" "${constructorArgs[@]}" 2>/dev/null) || fail "Cannot encode constructor"
forge build --use "${FOUNDRY_SOLC:-0.8.30}" --out out --skip ImportWETH.sol --skip Proposal01FeeActivation >/dev/null 2>&1 || fail "Cannot build current contracts"
# Select the signer without printing keys, command lines or RPC credentials.
useLedger=$(jq -er '.useLedger | if type == "boolean" then tostring else error("useLedger must be boolean") end' "$globals")
if [[ "$useLedger" == true ]]; then
  derivationPath=$(jq -er '.derivationPath' "$globals")
  walletArgs=(--ledger --mnemonic-derivation-path "$derivationPath")
else
  [[ -n "${PRIVATE_KEY:-}" ]] || fail "Set PRIVATE_KEY or useLedger=true"
  walletArgs=(--private-key "$PRIVATE_KEY")
fi
deployer=$(cast wallet address "${walletArgs[@]}" 2>/dev/null) || fail "Cannot read wallet address"
[[ "$deployer" =~ ^0x[0-9a-fA-F]{40}$ && "$deployer" != 0x0000000000000000000000000000000000000000 ]] || fail "Invalid wallet address"
echo "${green}Signer: $deployer; chain: $chainId${reset}"

echo "${green}Deploying $contractName${reset}"
# A timeout may follow a mined deployment. Stop; inspect wallet transactions before retrying.
if ! deploymentOutput=$(forge create "$contractPath" --use "${FOUNDRY_SOLC:-0.8.30}" --skip ImportWETH.sol --skip Proposal01FeeActivation --broadcast --json --rpc-url "$networkURL" "${walletArgs[@]}" --constructor-args "${constructorArgs[@]}" 2>/dev/null); then
  transactionHash=$(jq -r '.transactionHash // empty' <<< "$deploymentOutput" 2>/dev/null || true)
  if [[ "$transactionHash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then echo "Inspect transaction: $transactionHash" >&2; fi
  fail "Deployment command failed; inspect wallet transactions before retrying"
fi
deployedAddress=$(jq -er '.deployedTo' <<< "$deploymentOutput") || fail "Invalid deployment output"
[[ "$deployedAddress" =~ ^0x[0-9a-fA-F]{40}$ && "$deployedAddress" != 0x0000000000000000000000000000000000000000 ]] || fail "Invalid address: deployedAddress"
transactionHash=$(jq -er '.transactionHash | select(test("^0x[0-9a-fA-F]{64}$"))' <<< "$deploymentOutput") || fail "Missing deployment transaction hash"
echo "Deployment transaction: $transactionHash"
receipt=$(cast receipt --json --rpc-url "$networkURL" "$transactionHash" 2>/dev/null) || fail "Cannot read deployment receipt; inspect the transaction before retrying"
jq -e '(.status == "0x1" or .status == 1 or .status == "1") and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$receipt" >/dev/null || fail "Missing or unsuccessful transaction receipt"
jq -e --arg tx "$transactionHash" --arg contract "$deployedAddress" '(.transactionHash | ascii_downcase) == ($tx | ascii_downcase) and (.contractAddress | ascii_downcase) == ($contract | ascii_downcase)' <<< "$receipt" >/dev/null || fail "Deployment receipt does not match the transaction and address"
address "$deployedAddress" deployedAddress
check "$deployedAddress" 'VERSION()(string)' 1.2.0 "Wrong Marketplace version"
check "$deployedAddress" 'serviceRegistry()(address)' "$serviceRegistryAddress" "Wrong service registry"
check "$deployedAddress" 'karma()(address)' "$karmaProxyAddress" "Wrong Karma contract"
# Save only a confirmed deployment; a later explorer failure must not discard its address.
temporary=$(mktemp "$globals.tmp.XXXXXX")
trap 'rm -f "$temporary"' EXIT
jq --arg address "$deployedAddress" '.mechMarketplaceAddress = $address' "$globals" > "$temporary"
mv "$temporary" "$globals"
trap - EXIT
echo "${green}$contractName deployed at: $deployedAddress${reset}"
if [[ "$contractVerification" == true ]]; then
  forge verify-contract --watch --chain "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" "$deployedAddress" "$contractPath" --constructor-args "$encodedConstructor" >/dev/null 2>&1 || fail "Explorer verification failed; address is saved. Verify it separately; do not redeploy"
  blockscoutURL=$(jq -r '.blockscoutURL // empty' "$globals")
  if [[ -n "$blockscoutURL" ]]; then
    forge verify-contract --watch --chain "$chainId" --verifier blockscout --verifier-url "${blockscoutURL%/}/api" "$deployedAddress" "$contractPath" --constructor-args "$encodedConstructor" >/dev/null 2>&1 || fail "Blockscout verification failed; address is saved. Verify it separately; do not redeploy"
  fi
fi
