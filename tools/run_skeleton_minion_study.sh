#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
study_runtime="$(mktemp -d /tmp/godot-skeleton-game-XXXXXX)"
mkdir -p "$study_runtime/data" "$study_runtime/config" "$study_runtime/cache"
export XDG_DATA_HOME="$study_runtime/data" XDG_CONFIG_HOME="$study_runtime/config" XDG_CACHE_HOME="$study_runtime/cache"
exec godot --path "$project_dir" --script res://scripts/studies/run_skeleton_minion_study.gd "$@"
