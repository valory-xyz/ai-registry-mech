#!/bin/bash
set -euo pipefail
[[ $# == 1 || ( $# == 2 && "$2" == --calldata ) ]] || { echo "Usage: $0 <network> [--calldata]" >&2; exit 1; }
exec bash "$(dirname "$0")/script_03a_marketplace_set_balance_trackers_fixed.sh" "$@" native
