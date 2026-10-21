#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dp_init "$@"
[[ $# == 1 || ( $# == 2 && "$2" == --calldata ) ]] || dp_fail "Usage: $0 <network> [--calldata]"
dp_proxy
implementation=$(dp_config_address mechMarketplaceAddress)
dp_code "$implementation"
dp_check "$implementation" 'VERSION()(string)' 1.2.0 "Unexpected Marketplace version"
# Preserve constructor dependencies: an implementation upgrade changes immutable values too.
for getter in 'serviceRegistry()(address)' 'karma()(address)'; do
    dependency=$(dp_call "$DP_PROXY" "$getter")
    dp_check "$implementation" "$getter" "$dependency" "Implementation dependencies differ from the current proxy"
done
legacy=$(dp_call "$DP_PROXY" 'getDomainSeparator()(bytes32)')
owner=$(dp_call "$DP_PROXY" 'owner()(address)')
dp_send 'changeImplementation(address)' "$implementation"
if [[ "$DP_PLAN" == false ]]; then
    dp_check "$DP_PROXY" 'getImplementation()(address)' "$implementation" "Implementation readback failed"
    dp_check "$DP_PROXY" 'VERSION()(string)' 1.2.0 "Version readback failed"
    dp_check "$DP_PROXY" 'getDomainSeparator()(bytes32)' "$legacy" "Legacy domain changed; inspect the completed upgrade"
    dp_check "$DP_PROXY" 'owner()(address)' "$owner" "Owner changed; inspect the completed upgrade"
    echo 'Upgrade confirmed; proxy address retained'
fi
