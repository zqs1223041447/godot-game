#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
runtime="${TMPDIR:-/tmp}/v111-modular-environment-runtime"
mkdir -p "$runtime/data" "$runtime/config" "$runtime/cache"
export XDG_DATA_HOME="$runtime/data" XDG_CONFIG_HOME="$runtime/config" XDG_CACHE_HOME="$runtime/cache"
export GODOT_SILENCE_ROOT_WARNING=1
if [[ "${1:-}" == "--qa" ]]; then
  exec godot --headless --path . -- --qa
fi
exec godot --path . -- "$@"
