#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
preview_runtime="$(mktemp -d /tmp/godot-skeleton-sample-XXXXXX)"
mkdir -p "$preview_runtime/data" "$preview_runtime/config" "$preview_runtime/cache"
export XDG_DATA_HOME="$preview_runtime/data" XDG_CONFIG_HOME="$preview_runtime/config" XDG_CACHE_HOME="$preview_runtime/cache"
exec godot --path "$project_dir" --script res://tools/art/skeleton_minion/preview_sample.gd "$@"
