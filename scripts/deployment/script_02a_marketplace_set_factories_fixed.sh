#!/bin/bash
set -euo pipefail
DP_REGISTER=factories
source "$(dirname "$0")/lib/register_fixed.sh" "$@"
