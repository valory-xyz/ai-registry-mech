#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dp_init "$@"
dp_deploy_options "$@"
# An upgrade must keep the existing proxy and its storage.
existing=$(jq -r '.mechMarketplaceProxyAddress // empty' "$DP_GLOBALS")
[[ -z "$existing" || "$existing" == 0x0000000000000000000000000000000000000000 ]] || dp_fail "Proxy already configured; use script_06 for an upgrade"
implementation=$(dp_config_address mechMarketplaceAddress)
dp_code "$implementation"
dp_check "$implementation" 'VERSION()(string)' 1.2.0 "Unexpected Marketplace version"
fee=$(dp_field fee)
minimum=$(dp_field minResponseTimeout)
maximum=$(dp_field maxResponseTimeout)
for value in "$fee" "$minimum" "$maximum"; do [[ "$value" =~ ^[0-9]+$ ]] || dp_fail "Initialization values must be unsigned decimal integers"; done
data=$(cast calldata 'initialize(uint256,uint256,uint256)' "$fee" "$minimum" "$maximum")
dp_deploy mechMarketplaceProxyAddress contracts/proxies/MechMarketplaceProxy.sol:MechMarketplaceProxy 'constructor(address,bytes)' "$implementation" "$data"
