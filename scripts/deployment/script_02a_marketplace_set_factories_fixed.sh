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

[[ $# -ge 2 && -n "${1:-}" ]] || fail "Usage: $0 <network> native|olas|usdc ..."

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

mechMarketplaceProxyAddress=$(jq -er ".mechMarketplaceProxyAddress" "$globals")
mechFactoryFixedPriceNativeAddress=$(jq -r ".mechFactoryFixedPriceNativeAddress" "$globals")
mechFactoryFixedPriceTokenOLASAddress=$(jq -r ".mechFactoryFixedPriceTokenOLASAddress" "$globals")
mechFactoryFixedPriceTokenUSDCAddress=$(jq -r ".mechFactoryFixedPriceTokenUSDCAddress" "$globals")

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

address "$mechMarketplaceProxyAddress" mechMarketplaceProxyAddress
check "$mechMarketplaceProxyAddress" 'VERSION()(string)' 1.2.0 "Upgrade the Marketplace proxy to 1.2.0 before registration"
cd "$(dirname "$globals")/../.."
forge build --use "${FOUNDRY_SOLC:-0.8.30}" --out out --skip ImportWETH.sol --skip Proposal01FeeActivation >/dev/null 2>&1 || fail "Cannot build current contracts"
command -v python3 >/dev/null || fail "Missing dependency: python3"
factories=()
statuses=()
paymentTypes=()
trackers=()
seen=' '
for payment in "${@:2}"; do
  [[ "$seen" != *" $payment "* ]] || fail "Duplicate payment type"
  seen+="$payment "
  case "$payment" in
    native) factory=$mechFactoryFixedPriceNativeAddress; suffix=Native; typeName=FixedPriceNative; factoryName=MechFactoryFixedPriceNative; assetField=wrappedNativeTokenAddress; assetGetter='wrappedNativeToken()(address)';;
    olas) factory=$mechFactoryFixedPriceTokenOLASAddress; suffix=TokenOLAS; typeName=FixedPriceToken; factoryName=MechFactoryFixedPriceToken; assetField=olasAddress; assetGetter='token()(address)';;
    usdc) factory=$mechFactoryFixedPriceTokenUSDCAddress; suffix=TokenUSDC; typeName=FixedPriceTokenUSDC; factoryName=MechFactoryFixedPriceTokenUSDC; assetField=usdcAddress; assetGetter='token()(address)';;
    *) fail "Unknown payment type: $payment";;
  esac
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
  factoryCode=$(cast code --rpc-url "$networkURL$API_KEY" "$factory" 2>/dev/null) || fail "Cannot read factory code"
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
echo "${green}Set factories in MechMarketplaceProxy${reset}"

castSendHeader=(cast send --json --rpc-url "$networkURL$API_KEY" "${walletArgs[@]}")
factoryArray=$(IFS=,; echo "[${factories[*]}]")
statusArray=$(IFS=,; echo "[${statuses[*]}]")
castArgs=("$mechMarketplaceProxyAddress" 'setMechFactoryStatuses(address[],bool[])' "$factoryArray" "$statusArray")
echo "${castArgs[*]}"
castCmd=("${castSendHeader[@]}" "${castArgs[@]}")
submissionStatus=0
result=$("${castCmd[@]}" 2>/dev/null) || submissionStatus=$?
# A failed command or reverted receipt can still identify a broadcast transaction.
transactionHash=$(jq -r '.transactionHash // empty' <<< "$result" 2>/dev/null || true)
if [[ "$transactionHash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then echo "Transaction: $transactionHash"; fi
[[ "$submissionStatus" == 0 ]] || fail "Factory registration failed; inspect the transaction before retrying"
jq -e '(.status == "0x1" or .status == 1 or .status == "1") and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$result" >/dev/null 2>&1 || fail "Missing or unsuccessful transaction receipt"
for ((i=0; i<${#factories[@]}; i++)); do
  check "$mechMarketplaceProxyAddress" 'mapMechFactories(address)(bool)' true "Factory registration readback failed" "${factories[i]}"
  check "$mechMarketplaceProxyAddress" 'mapPaymentTypeBalanceTrackers(bytes32)(address)' "${trackers[i]}" "Tracker mapping changed" "${paymentTypes[i]}"
done
echo "Factories confirmed for: ${*:2}; existing trackers retained"
