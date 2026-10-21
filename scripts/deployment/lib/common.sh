#!/bin/bash
# Shared by the Phase 2 fixed-price deployment entrypoints. Bash 3.2 compatible.
set -euo pipefail

dp_fail() { echo "Error: $*" >&2; exit 1; }
dp_capture() { python3 "$DP_DIR/lib/deployment_io.py" run "$@"; }
dp_field() { jq -er --arg key "$1" '.[$key] | select(. != null and . != "")' "$DP_GLOBALS"; }
dp_address() {
    [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ && "$1" != 0x0000000000000000000000000000000000000000 ]] || dp_fail "Invalid or zero address: $2"
}
dp_config_address() {
    local value
    value=$(dp_field "$1") || dp_fail "Missing configuration: $1"
    dp_address "$value" "$1"
    echo "$value"
}
dp_equal() { [[ "$(echo "$1" | tr '[:upper:]' '[:lower:]')" == "$(echo "$2" | tr '[:upper:]' '[:lower:]')" ]] || dp_fail "$3"; }
dp_call() {
    local result
    result=$(dp_capture cast call --rpc-url "$DP_RPC" "$@") || dp_fail "Contract read failed: $2"
    echo "$result" | tr -d '"'
}
dp_check() {
    local address=$1 signature=$2 expected=$3 message=$4 actual
    shift 4
    # Do not nest a failing RPC read inside dp_equal's arguments: Bash can mask that failure.
    actual=$(dp_call "$address" "$signature" "$@") || dp_fail "$message (read failed)"
    dp_equal "$actual" "$expected" "$message"
}
dp_code() {
    local code
    code=$(dp_capture cast code --rpc-url "$DP_RPC" "$1") || dp_fail "Cannot read contract code"
    [[ "$code" =~ ^0x[0-9a-fA-F]+$ && "$code" != 0x0 && "$code" != 0x ]] || dp_fail "No contract code at $1"
}
dp_build_factories() {
    command -v python3 >/dev/null || dp_fail "Missing dependency: python3"
    # Refresh artifacts so stale build output cannot authorize a pre-upgrade factory.
    forge build --use "${FOUNDRY_SOLC:-0.8.30}" --out "$DP_ROOT/out" --skip ImportWETH.sol --skip Proposal01FeeActivation >/dev/null 2>&1 || dp_fail "Cannot build the current factories; registration stopped"
}
dp_factory_code() {
    local code artifact
    artifact="$DP_ROOT/out/$2.sol/$2.json"
    code=$(dp_capture cast code --rpc-url "$DP_RPC" "$1") || dp_fail "Cannot read selected factory code"
    python3 "$DP_DIR/lib/check_factory.py" "$artifact" "$DP_PROXY" <<< "$code" || dp_fail "Selected factory failed the current-build check: $1"
}
dp_init() {
    [[ "${1:-}" =~ ^[a-zA-Z0-9_-]+$ ]] || dp_fail "Usage: $0 <network> [--calldata] [native|olas|usdc ...]"
    DP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    DP_ROOT=$(cd "$DP_DIR/../.." && pwd)
    DP_GLOBALS="$DP_DIR/globals_$1.json"
    DP_PLAN=false
    [[ "${2:-}" != --calldata ]] || DP_PLAN=true
    for dependency in jq cast forge python3; do command -v "$dependency" >/dev/null || dp_fail "Missing dependency: $dependency"; done
    [[ -f "$DP_GLOBALS" ]] || dp_fail "Configuration not found: $DP_GLOBALS"
    jq -e 'type == "object"' "$DP_GLOBALS" >/dev/null || dp_fail "Invalid configuration JSON"
    DP_CHAIN=$(dp_field chainId) || dp_fail "Missing chainId"
    [[ "$DP_CHAIN" =~ ^[1-9][0-9]*$ ]] || dp_fail "chainId must be a positive decimal integer"
    DP_RPC=$(dp_field networkURL) || dp_fail "Missing networkURL"
    [[ "$DP_RPC" == http://* || "$DP_RPC" == https://* ]] || dp_fail "networkURL must be HTTP(S)"
    # Append a key only for an incomplete Alchemy URL, not for every RPC on that chain.
    if [[ "$DP_RPC" == https://*.g.alchemy.com/v2/ ]]; then
        local key_name key_value
        case "$DP_CHAIN" in
            1) key_name=ALCHEMY_API_KEY_MAINNET;;
            11155111) key_name=ALCHEMY_API_KEY_SEPOLIA;;
            137) key_name=ALCHEMY_API_KEY_MATIC;;
            80002) key_name=ALCHEMY_API_KEY_AMOY;;
            *) dp_fail "Supply a complete Alchemy networkURL for chain $DP_CHAIN";;
        esac
        key_value=${!key_name:-}
        [[ -n "$key_value" ]] || dp_fail "Set $key_name"
        DP_RPC+="$key_value"
    fi
    local rpc_chain
    rpc_chain=$(dp_capture cast chain-id --rpc-url "$DP_RPC") || dp_fail "Cannot read RPC chain ID"
    dp_equal "$rpc_chain" "$DP_CHAIN" "RPC chain ID does not match configuration"
    # Foundry must use this checkout's compiler settings, regardless of the caller's cwd.
    cd "$DP_ROOT"
}
dp_wallet() {
    local ledger path
    ledger=$(jq -er '.useLedger | if type == "boolean" then tostring else error("useLedger must be boolean") end' "$DP_GLOBALS") || dp_fail "useLedger must be boolean"
    if [[ "$ledger" == true ]]; then
        path=$(dp_field derivationPath) || dp_fail "Missing derivationPath"
        DP_WALLET=(--ledger --mnemonic-derivation-path "$path")
    else
        [[ -n "${PRIVATE_KEY:-}" ]] || dp_fail "Set PRIVATE_KEY or useLedger=true"
        DP_WALLET=(--private-key "$PRIVATE_KEY")
    fi
    DP_SENDER=$(dp_capture cast wallet address "${DP_WALLET[@]}") || dp_fail "Cannot read wallet address"
    dp_address "$DP_SENDER" sender
    echo "Sender: $DP_SENDER; chain: $DP_CHAIN" >&2
}
dp_proxy() {
    DP_PROXY=$(dp_config_address mechMarketplaceProxyAddress)
    dp_code "$DP_PROXY"
}
dp_owner() {
    dp_wallet
    dp_check "$DP_PROXY" 'owner()(address)' "$DP_SENDER" "Wallet is not Marketplace owner; use --calldata for governance execution"
}
dp_receipt() {
    jq -e '(.status == "0x1" or .status == "1" or .status == 1) and (.transactionHash | test("^0x[0-9a-fA-F]{64}$"))' <<< "$1" >/dev/null || dp_fail "Missing or unsuccessful transaction receipt"
    echo "Transaction: $(jq -r .transactionHash <<< "$1")" >&2
}
dp_send() {
    local data
    if [[ "$DP_PLAN" == true ]]; then
        echo "Chain: $DP_CHAIN"
        echo "Target: $DP_PROXY"
        echo "Value: 0"
        data=$(cast calldata "$@") || dp_fail "Cannot encode calldata"
        echo "Data: $data"
        return
    fi
    dp_owner
    local receipt
    # Never print a command containing a key or a credential-bearing RPC URL.
    receipt=$(dp_capture cast send --json --rpc-url "$DP_RPC" "${DP_WALLET[@]}" "$DP_PROXY" "$@") || dp_fail "Transaction submission failed; check receipt before retrying"
    dp_receipt "$receipt"
}
dp_save() {
    local temporary
    temporary=$(mktemp "$DP_GLOBALS.tmp.XXXXXX") || dp_fail "Cannot create temporary configuration"
    if ! jq --arg key "$1" --arg value "$2" '.[$key] = $value' "$DP_GLOBALS" > "$temporary" || ! mv "$temporary" "$DP_GLOBALS"; then
        rm -f "$temporary"
        dp_fail "Cannot save deployed address; recover it from the transaction above"
    fi
}
dp_deploy_options() {
    shift
    DP_REPLACE_OLD=''
    if [[ $# -gt 0 ]]; then
        [[ $# == 2 && "$1" == --replace ]] || dp_fail "Usage: $0 <network> [--replace <exact currently configured address>]"
        dp_address "$2" --replace
        DP_REPLACE_OLD=$2
    fi
}
dp_deploy() {
    local key=$1 target=$2 signature=$3 verification output address tx receipt encoded blockscout previous metadata nonce
    shift 3
    DP_RECORD="$DP_DIR/.deployment-records/$(basename "$DP_GLOBALS" .json)/$key.pending.json"
    previous=$(jq -r --arg key "$key" '.[$key] // empty' "$DP_GLOBALS")
    [[ "$previous" != 0x0000000000000000000000000000000000000000 ]] || previous=''
    if [[ -n "$DP_REPLACE_OLD" ]]; then
        dp_equal "$previous" "$DP_REPLACE_OLD" "Configured address differs from --replace; no deployment was submitted"
        [[ "$key" != mechMarketplaceProxyAddress ]] || dp_fail "Replacing the Marketplace proxy is not supported; keep its address and use script_06"
    fi
    [[ ! -e "$DP_RECORD" ]] || dp_fail "Unresolved deployment attempt exists: $DP_RECORD; inspect the transaction before any further deployment"
    [[ -z "$previous" || -n "$DP_REPLACE_OLD" ]] || dp_fail "Deployment already configured; use --replace with its exact address only for an intentional new deployment"
    verification=$(jq -er '.contractVerification | if type == "boolean" then tostring else error("contractVerification must be boolean") end' "$DP_GLOBALS") || dp_fail "contractVerification must be boolean"
    if [[ "$verification" == true ]]; then
        [[ -n "${ETHERSCAN_API_KEY:-}" ]] || dp_fail "Set ETHERSCAN_API_KEY for contractVerification=true"
    fi
    encoded=$(cast abi-encode "$signature" "$@")
    dp_capture forge build --use "${FOUNDRY_SOLC:-0.8.30}" --out "$DP_ROOT/out" --skip ImportWETH.sol --skip Proposal01FeeActivation >/dev/null || dp_fail "Cannot build deployment artifacts; no deployment was submitted"
    dp_wallet
    nonce=$(dp_capture cast nonce "$DP_SENDER" --block pending --rpc-url "$DP_RPC") || dp_fail "Cannot read deployment nonce; no deployment was submitted"
    [[ "$nonce" =~ ^[0-9]+$ ]] || dp_fail "Invalid deployment nonce"
    metadata=$(jq -n --arg chain "$DP_CHAIN" --arg target "$target" --arg constructor "$encoded" --arg sender "$DP_SENDER" --arg nonce "$nonce" '{chainId:$chain,target:$target,constructor:$constructor,sender:$sender,nonce:$nonce}')
    python3 "$DP_DIR/lib/deployment_io.py" begin "$DP_RECORD" "$DP_GLOBALS" "$key" "$previous" "$metadata"
    output=$(DP_COMMAND_RECORD="$DP_RECORD" dp_capture forge create "$target" --use "${FOUNDRY_SOLC:-0.8.30}" --skip ImportWETH.sol --skip Proposal01FeeActivation --broadcast --json --nonce "$nonce" --rpc-url "$DP_RPC" "${DP_WALLET[@]}" --constructor-args "$@") || dp_fail "Deployment failed; inspect $DP_RECORD and wallet transactions before retrying"
    address=$(jq -er .deployedTo <<< "$output") || dp_fail "Invalid deployment JSON; inspect $DP_RECORD before retrying"
    tx=$(jq -er '.transactionHash | select(test("^0x[0-9a-fA-F]{64}$"))' <<< "$output") || dp_fail "Missing deployment transaction hash; inspect $DP_RECORD"
    dp_address "$address" deployedTo
    echo "Deployment transaction: $tx" >&2
    receipt=$(dp_capture cast receipt --json --rpc-url "$DP_RPC" "$tx") || dp_fail "Cannot retrieve deployment receipt; inspect transaction $tx before proceeding"
    dp_receipt "$receipt"
    dp_equal "$(jq -er .transactionHash <<< "$receipt")" "$tx" "Wrong deployment receipt"
    echo "Deployment address: $address" >&2
    dp_equal "$(jq -er .contractAddress <<< "$receipt")" "$address" "Receipt contract address does not match deployment"
    dp_code "$address"
    case "$key" in
        mechMarketplaceAddress)
            dp_check "$address" 'VERSION()(string)' 1.2.0 "Unexpected Marketplace version"
            dp_check "$address" 'serviceRegistry()(address)' "$1" "Wrong service registry"
            dp_check "$address" 'karma()(address)' "$2" "Wrong karma contract";;
        mechMarketplaceProxyAddress)
            dp_check "$address" 'getImplementation()(address)' "$1" "Wrong proxy implementation"
            dp_check "$address" 'owner()(address)' "$DP_SENDER" "Wrong proxy owner";;
        *) dp_check "$address" 'mechMarketplace()(address)' "$1" "Wrong factory Marketplace";;
    esac
    # A confirmed deployment remains recoverable if saving or explorer verification fails.
    dp_save "$key" "$address"
    python3 "$DP_DIR/lib/deployment_io.py" finish "$DP_RECORD" "$metadata" "$tx" "$address"
    if [[ "$verification" == true ]]; then
        dp_capture forge verify-contract --watch --chain "$DP_CHAIN" --etherscan-api-key "$ETHERSCAN_API_KEY" "$address" "$target" --constructor-args "$encoded" >/dev/null || dp_fail "Explorer verification failed; deployed address is saved. Retry explorer verification separately for transaction $tx; do not redeploy"
        blockscout=$(jq -r '.blockscoutURL // empty' "$DP_GLOBALS")
        if [[ -n "$blockscout" ]]; then
            dp_capture forge verify-contract --watch --chain "$DP_CHAIN" --verifier blockscout --verifier-url "${blockscout%/}/api" "$address" "$target" --constructor-args "$encoded" >/dev/null || dp_fail "Blockscout verification failed; deployed address is saved. Retry verification separately; do not redeploy transaction $tx"
        fi
    fi
    echo "Confirmed $key: $address"
}
