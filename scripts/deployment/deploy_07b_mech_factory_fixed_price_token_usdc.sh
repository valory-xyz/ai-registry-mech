#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dp_init "$@"
dp_deploy_options "$@"
dp_proxy
dp_deploy mechFactoryFixedPriceTokenUSDCAddress contracts/mechs/token/usdc/MechFactoryFixedPriceTokenUSDC.sol:MechFactoryFixedPriceTokenUSDC 'constructor(address)' "$DP_PROXY"
