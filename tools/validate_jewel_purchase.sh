#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
if [[ "$(uname -s)" != Linux ]]; then
  echo "This write-test runner requires Linux XDG isolation." >&2
  exit 78
fi
qa_dir="$(mktemp -d /tmp/godot-m1-jewel-purchase.XXXXXX)"
trap 'rm -rf -- "$qa_dir"' EXIT
export XDG_CONFIG_HOME="$qa_dir/config"
export XDG_CACHE_HOME="$qa_dir/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
for case_name in transactions gameplay; do
  export XDG_DATA_HOME="$qa_dir/$case_name/data"
  mkdir -p "$XDG_DATA_HOME"
  timeout 45s "$godot_bin" --headless --path "$project_dir" --script "res://tests/jewel_purchase_${case_name}_test.gd"
done
