#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dp_init "$@"
dp_deploy_options "$@"
registry=$(dp_config_address serviceRegistryAddress)
karma=$(dp_config_address karmaProxyAddress)
dp_code "$registry"
dp_code "$karma"
dp_deploy mechMarketplaceAddress contracts/MechMarketplace.sol:MechMarketplace 'constructor(address,address)' "$registry" "$karma"
