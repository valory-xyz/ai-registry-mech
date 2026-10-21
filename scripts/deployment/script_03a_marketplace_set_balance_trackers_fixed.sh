#!/bin/bash
set -euo pipefail
DP_REGISTER=trackers
source "$(dirname "$0")/lib/register_fixed.sh" "$@"
