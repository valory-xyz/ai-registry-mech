#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dp_init "$@"
dp_deploy_options "$@"
dp_proxy
dp_deploy mechFactoryFixedPriceTokenOLASAddress contracts/mechs/token/MechFactoryFixedPriceToken.sol:MechFactoryFixedPriceToken 'constructor(address)' "$DP_PROXY"
