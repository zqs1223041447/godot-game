#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export XDG_CACHE_HOME="$ROOT/.runtime-home/.cache"
export XDG_CONFIG_HOME="$ROOT/.runtime-home/.config"
export XDG_DATA_HOME="$ROOT/.runtime-home/.local/share"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
exec godot --path "$ROOT" "$@"
