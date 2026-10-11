#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != Linux ]]; then
  echo "This write-test runner requires Linux XDG isolation." >&2
  exit 78
fi
qa_dir="$(mktemp -d /tmp/godot-m1-quick-dash-check.XXXXXX)"
trap 'rm -rf -- "$qa_dir"' EXIT
export XDG_DATA_HOME="$qa_dir/data" XDG_CONFIG_HOME="$qa_dir/config" XDG_CACHE_HOME="$qa_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
timeout 40s "${GODOT_BIN:-godot}" --headless --path "$project_dir" --script res://tests/quick_dash_binding_test.gd
