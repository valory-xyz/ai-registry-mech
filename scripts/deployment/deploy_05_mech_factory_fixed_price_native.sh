#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dp_init "$@"
dp_deploy_options "$@"
dp_proxy
dp_deploy mechFactoryFixedPriceNativeAddress contracts/mechs/native/MechFactoryFixedPriceNative.sol:MechFactoryFixedPriceNative 'constructor(address)' "$DP_PROXY"
