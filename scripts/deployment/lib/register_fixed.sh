#!/bin/bash
# Called by the two fixed-price registration entrypoints, not directly.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
dp_init "$@"
shift
if [[ "${1:-}" == --calldata ]]; then shift; fi
[[ $# -gt 0 ]] || dp_fail "Select at least one payment type: native olas usdc"
dp_proxy
# Register only after the Phase 2 implementation is active on this proxy.
dp_check "$DP_PROXY" 'VERSION()(string)' 1.2.0 "Upgrade the Marketplace proxy to 1.2.0 before registration"
addresses=()
types=()
flags=()
seen=' '
factory_build_ready=false
# Only explicitly selected payment types are read or submitted; other registrations are untouched.
for payment in "$@"; do
    [[ "$seen" != *" $payment "* ]] || dp_fail "Duplicate payment type: $payment"
    seen+="$payment "
    case "$payment" in
        native) suffix=Native; type_name=FixedPriceNative; factory_name=MechFactoryFixedPriceNative;;
        olas) suffix=TokenOLAS; type_name=FixedPriceToken; factory_name=MechFactoryFixedPriceToken;;
        usdc) suffix=TokenUSDC; type_name=FixedPriceTokenUSDC; factory_name=MechFactoryFixedPriceTokenUSDC;;
        *) dp_fail "Unknown payment type: $payment (choose native olas usdc)";;
    esac
    payment_type=$(cast keccak "$type_name")
    if [[ "$DP_REGISTER" == factories ]]; then
        address=$(dp_config_address "mechFactoryFixedPrice${suffix}Address")
        # Configure trackers first. Do not enable a factory whose mechs cannot be created.
        if [[ "$DP_PLAN" == false ]]; then
            tracker=$(dp_config_address "balanceTrackerFixedPrice${suffix}Address")
            dp_check "$DP_PROXY" 'mapPaymentTypeBalanceTrackers(bytes32)(address)' "$tracker" "Configure the selected tracker before enabling its factory" "$payment_type"
        fi
    else
        address=$(dp_config_address "balanceTrackerFixedPrice${suffix}Address")
    fi
    dp_code "$address"
    dp_check "$address" 'mechMarketplace()(address)' "$DP_PROXY" "Selected contract points to a different Marketplace"
    if [[ "$DP_REGISTER" == factories ]]; then
        if [[ "$factory_build_ready" == false ]]; then
            dp_build_factories
            factory_build_ready=true
        fi
        # Both submission and calldata planning require the selected type's current bytecode.
        dp_factory_code "$address" "$factory_name"
    fi
    if [[ "$DP_REGISTER" == trackers ]]; then
        case "$payment" in
            native) asset=$(dp_config_address wrappedNativeTokenAddress); getter='wrappedNativeToken()(address)';;
            olas) asset=$(dp_config_address olasAddress); getter='token()(address)';;
            usdc) asset=$(dp_config_address usdcAddress); getter='token()(address)';;
        esac
        dp_check "$address" "$getter" "$asset" "Tracker asset differs from configuration"
    fi
    addresses+=("$address")
    types+=("$payment_type")
    flags+=(true)
done
address_array=$(IFS=,; echo "[${addresses[*]}]")
if [[ "$DP_REGISTER" == factories ]]; then
    flag_array=$(IFS=,; echo "[${flags[*]}]")
    dp_send 'setMechFactoryStatuses(address[],bool[])' "$address_array" "$flag_array"
else
    type_array=$(IFS=,; echo "[${types[*]}]")
    dp_send 'setPaymentTypeBalanceTrackers(bytes32[],address[])' "$type_array" "$address_array"
fi
if [[ "$DP_PLAN" == false ]]; then
    for ((i=0; i<${#addresses[@]}; i++)); do
        if [[ "$DP_REGISTER" == factories ]]; then
            dp_check "$DP_PROXY" 'mapMechFactories(address)(bool)' true "Factory status readback failed" "${addresses[i]}"
        else
            dp_check "$DP_PROXY" 'mapPaymentTypeBalanceTrackers(bytes32)(address)' "${addresses[i]}" "Tracker readback failed" "${types[i]}"
        fi
    done
    echo "Confirmed $DP_REGISTER for: $*"
fi
