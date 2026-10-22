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
[[ -n "${1:-}" ]] || fail "Usage: $0 <network>"
scriptDirectory=$(cd "$(dirname "$0")" && pwd)
globals="$scriptDirectory/globals_$1.json"
[[ -f "$globals" ]] || fail "Configuration not found"
for tool in jq cast forge; do command -v "$tool" >/dev/null || fail "Missing dependency: $tool"; done
jq -e 'type == "object"' "$globals" >/dev/null || fail "Invalid configuration JSON"
chainId=$(jq -er '.chainId' "$globals")
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
mechMarketplaceAddress=$(jq -er '.mechMarketplaceAddress' "$globals")
mechMarketplaceProxyAddress=$(jq -er '.mechMarketplaceProxyAddress' "$globals")
address "$mechMarketplaceAddress" mechMarketplaceAddress
address "$mechMarketplaceProxyAddress" mechMarketplaceProxyAddress
check "$mechMarketplaceAddress" 'VERSION()(string)' 1.2.0 "Wrong Marketplace version"
# Registry and Karma are implementation immutables, so compare with the existing proxy.
for getter in 'serviceRegistry()(address)' 'karma()(address)'; do
  expected=$(cast call --rpc-url "$networkURL" "$mechMarketplaceProxyAddress" "$getter" 2>/dev/null) || fail "Cannot read existing dependency"
  check "$mechMarketplaceAddress" "$getter" "$expected" "Implementation dependencies differ from the proxy"
done
owner=$(cast call --rpc-url "$networkURL" "$mechMarketplaceProxyAddress" 'owner()(address)' 2>/dev/null) || fail "Cannot read proxy owner"
domainSeparator=$(cast call --rpc-url "$networkURL" "$mechMarketplaceProxyAddress" 'getDomainSeparator()(bytes32)' 2>/dev/null) || fail "Cannot read legacy domain"
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

check "$mechMarketplaceProxyAddress" 'owner()(address)' "$deployer" "Signer is not Marketplace owner; use the owner's governance procedure"
receipt=$(cast send --json --rpc-url "$networkURL" "${walletArgs[@]}" "$mechMarketplaceProxyAddress" 'changeImplementation(address)' "$mechMarketplaceAddress" 2>/dev/null) || fail "Upgrade submission failed; inspect the transaction before retrying"
jq -e '(.status == "0x1" or .status == 1 or .status == "1") and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$receipt" >/dev/null || fail "Missing or unsuccessful transaction receipt"
echo "Upgrade transaction: $(jq -r .transactionHash <<< "$receipt")"
check "$mechMarketplaceProxyAddress" 'getImplementation()(address)' "$mechMarketplaceAddress" "Implementation readback failed"
check "$mechMarketplaceProxyAddress" 'VERSION()(string)' 1.2.0 "Version readback failed"
check "$mechMarketplaceProxyAddress" 'owner()(address)' "$owner" "Owner changed during upgrade"
check "$mechMarketplaceProxyAddress" 'getDomainSeparator()(bytes32)' "$domainSeparator" "Legacy domain changed during upgrade"
echo "Upgrade confirmed; existing proxy retained"
