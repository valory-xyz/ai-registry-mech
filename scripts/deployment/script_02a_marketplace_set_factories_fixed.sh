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

shift
[[ $# -gt 0 ]] || fail "Select payment types explicitly: native olas usdc"
command -v python3 >/dev/null || fail "Missing dependency: python3"
mechMarketplaceProxyAddress=$(jq -er '.mechMarketplaceProxyAddress' "$globals")
address "$mechMarketplaceProxyAddress" mechMarketplaceProxyAddress
check "$mechMarketplaceProxyAddress" 'VERSION()(string)' 1.2.0 "Upgrade the Marketplace proxy to 1.2.0 before registration"
forge build --use "${FOUNDRY_SOLC:-0.8.30}" --out out --skip ImportWETH.sol --skip Proposal01FeeActivation >/dev/null 2>&1 || fail "Cannot build current contracts"
factories=()
statuses=()
paymentTypes=()
trackers=()
seen=' '
for payment in "$@"; do
  [[ "$seen" != *" $payment "* ]] || fail "Duplicate payment type"
  seen+="$payment "
  case "$payment" in
    native) suffix=Native; typeName=FixedPriceNative; factoryName=MechFactoryFixedPriceNative; assetField=wrappedNativeTokenAddress; assetGetter='wrappedNativeToken()(address)';;
    olas) suffix=TokenOLAS; typeName=FixedPriceToken; factoryName=MechFactoryFixedPriceToken; assetField=olasAddress; assetGetter='token()(address)';;
    usdc) suffix=TokenUSDC; typeName=FixedPriceTokenUSDC; factoryName=MechFactoryFixedPriceTokenUSDC; assetField=usdcAddress; assetGetter='token()(address)';;
    *) fail "Unknown payment type: $payment";;
  esac
  factory=$(jq -er --arg field "mechFactoryFixedPrice${suffix}Address" '.[$field]' "$globals")
  tracker=$(jq -er --arg field "balanceTrackerFixedPrice${suffix}Address" '.[$field]' "$globals")
  asset=$(jq -er --arg field "$assetField" '.[$field]' "$globals")
  address "$factory" factory
  address "$tracker" tracker
  address "$asset" asset
  check "$factory" 'mechMarketplace()(address)' "$mechMarketplaceProxyAddress" "Factory points to a different Marketplace"
  check "$tracker" 'mechMarketplace()(address)' "$mechMarketplaceProxyAddress" "Tracker points to a different Marketplace"
  check "$tracker" "$assetGetter" "$asset" "Tracker asset differs from configuration"
  paymentType=$(cast keccak "$typeName" 2>/dev/null) || fail "Cannot compute payment type"
  check "$mechMarketplaceProxyAddress" 'mapPaymentTypeBalanceTrackers(bytes32)(address)' "$tracker" "Expected tracker is not registered; inspect configuration" "$paymentType"
  # VERSION is unchanged on the factories. Compare current bytecode, including embedded mech code.
  factoryCode=$(cast code --rpc-url "$networkURL" "$factory" 2>/dev/null) || fail "Cannot read factory code"
  python3 - "out/$factoryName.sol/$factoryName.json" "$mechMarketplaceProxyAddress" "$factoryCode" <<'PY'
import json, re, sys
def require(condition, message):
    if not condition:
        raise ValueError(message)
try:
    compiled = json.load(open(sys.argv[1]))['deployedBytecode']
    require(not compiled.get('linkReferences'), 'Unexpected library links')
    require(compiled['object'].startswith('0x'), 'Invalid compiled code')
    expected = bytearray.fromhex(compiled['object'][2:])
    references = compiled['immutableReferences']
    require(len(references) == 1, 'Expected one Marketplace immutable')
    positions = next(iter(references.values()))
    require(bool(positions), 'Missing immutable positions')
    occupied = set()
    for position in positions:
        start, length = position['start'], position['length']
        require(type(start) is int and type(length) is int and start >= 0 and length == 32 and start + length <= len(expected), 'Invalid immutable position')
        indexes = set(range(start, start + length))
        require(not occupied & indexes, 'Overlapping immutable positions')
        occupied.update(indexes)
        expected[start:start + length] = bytes.fromhex(sys.argv[2][2:].zfill(64))
    actual = sys.argv[3]
    require(re.fullmatch(r'0x(?:[0-9a-fA-F]{2})+', actual) and bytes.fromhex(actual[2:]) == expected, 'Factory does not match the current build; deploy its factory from this checkout')
except (OSError, ValueError, KeyError, TypeError) as error:
    sys.exit('Factory code check failed: ' + str(error))
PY
  factories+=("$factory")
  statuses+=(true)
  paymentTypes+=("$paymentType")
  trackers+=("$tracker")
done
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
factoryArray=$(IFS=,; echo "[${factories[*]}]")
statusArray=$(IFS=,; echo "[${statuses[*]}]")
receipt=$(cast send --json --rpc-url "$networkURL" "${walletArgs[@]}" "$mechMarketplaceProxyAddress" 'setMechFactoryStatuses(address[],bool[])' "$factoryArray" "$statusArray" 2>/dev/null) || fail "Factory registration failed; inspect the transaction before retrying"
jq -e '(.status == "0x1" or .status == 1 or .status == "1") and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$receipt" >/dev/null || fail "Missing or unsuccessful transaction receipt"
echo "Registration transaction: $(jq -r .transactionHash <<< "$receipt")"
for ((i=0; i<${#factories[@]}; i++)); do
  check "$mechMarketplaceProxyAddress" 'mapMechFactories(address)(bool)' true "Factory registration readback failed" "${factories[i]}"
  check "$mechMarketplaceProxyAddress" 'mapPaymentTypeBalanceTrackers(bytes32)(address)' "${trackers[i]}" "Tracker mapping changed" "${paymentTypes[i]}"
done
echo "Factories confirmed for: $*; existing trackers retained"
