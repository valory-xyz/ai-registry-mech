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

[[ $# == 1 && -n "${1:-}" ]] || fail "Usage: $0 <network>"

# Get globals file
globals="$(cd "$(dirname "$0")" && pwd)/globals_$1.json"
if [ ! -f "$globals" ]; then
  echo "!!! $globals is not found"
  exit 1
fi

# Read variables using jq
useLedger=$(jq -er '.useLedger | if type == "boolean" then tostring else error("useLedger must be boolean") end' "$globals")
derivationPath=$(jq -r '.derivationPath' "$globals")
chainId=$(jq -er '.chainId' "$globals")
networkURL=$(jq -er '.networkURL' "$globals")


mechMarketplaceAddress=$(jq -er ".mechMarketplaceAddress" "$globals")
mechMarketplaceProxyAddress=$(jq -er ".mechMarketplaceProxyAddress" "$globals")

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

address "$mechMarketplaceAddress" mechMarketplaceAddress
address "$mechMarketplaceProxyAddress" mechMarketplaceProxyAddress
check "$mechMarketplaceAddress" 'VERSION()(string)' 1.2.0 "Wrong Marketplace version"
# Registry and Karma are implementation immutables, so compare with the existing proxy.
for getter in 'serviceRegistry()(address)' 'karma()(address)'; do
  expected=$(cast call --rpc-url "$networkURL$API_KEY" "$mechMarketplaceProxyAddress" "$getter" 2>/dev/null) || fail "Cannot read existing dependency"
  check "$mechMarketplaceAddress" "$getter" "$expected" "Implementation dependencies differ from the proxy"
done
owner=$(cast call --rpc-url "$networkURL$API_KEY" "$mechMarketplaceProxyAddress" 'owner()(address)' 2>/dev/null) || fail "Cannot read proxy owner"
domainSeparator=$(cast call --rpc-url "$networkURL$API_KEY" "$mechMarketplaceProxyAddress" 'getDomainSeparator()(bytes32)' 2>/dev/null) || fail "Cannot read legacy domain"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs=(-l --mnemonic-derivation-path "$derivationPath")
  deployer=$(cast wallet address "${walletArgs[@]}" 2>/dev/null) || fail "Cannot read wallet address"
else
  [[ -n "${PRIVATE_KEY:-}" ]] || fail "Set PRIVATE_KEY or useLedger=true"
  walletArgs=(--private-key "$PRIVATE_KEY")
  deployer=$(cast wallet address "${walletArgs[@]}" 2>/dev/null) || fail "Cannot read wallet address"
fi

check "$mechMarketplaceProxyAddress" 'owner()(address)' "$deployer" "Signer is not Marketplace owner; use the owner's governance procedure"

# Cast command
echo "${green}Casting from: $deployer${reset}"
echo "${green}Change implementation in MechMarketplaceProxy contracts${reset}"

castSendHeader=(cast send --json --rpc-url "$networkURL$API_KEY" "${walletArgs[@]}")
castArgs=("$mechMarketplaceProxyAddress" 'changeImplementation(address)' "$mechMarketplaceAddress")
echo "${castArgs[*]}"
castCmd=("${castSendHeader[@]}" "${castArgs[@]}")
result=$("${castCmd[@]}" 2>/dev/null) || fail "Upgrade submission failed; inspect the transaction before retrying"
jq -e '(.status == "0x1" or .status == 1 or .status == "1") and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$result" >/dev/null || fail "Missing or unsuccessful transaction receipt"
echo "Transaction: $(jq -r .transactionHash <<< "$result")"
check "$mechMarketplaceProxyAddress" 'getImplementation()(address)' "$mechMarketplaceAddress" "Implementation readback failed"
check "$mechMarketplaceProxyAddress" 'VERSION()(string)' 1.2.0 "Version readback failed"
check "$mechMarketplaceProxyAddress" 'owner()(address)' "$owner" "Owner changed during upgrade"
check "$mechMarketplaceProxyAddress" 'getDomainSeparator()(bytes32)' "$domainSeparator" "Legacy domain changed during upgrade"
echo "Upgrade confirmed; existing proxy retained"
