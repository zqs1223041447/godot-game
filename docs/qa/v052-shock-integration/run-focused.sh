#!/usr/bin/env bash
set -euo pipefail

# Shared resource import must already be complete. This runs only the two
# compiler/schema tests; no editor import, full historical suite or scene smoke.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
QA_DIR="$PROJECT_DIR/docs/qa/v052-shock-integration"
TEST_ROOT="$(mktemp -d /tmp/godot-m1-v052-integration.XXXXXX)"
mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/cache/fontconfig"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_CACHE_HOME="$TEST_ROOT/cache"

for test_name in shock_support_compiler shock_gem_migration; do
  export XDG_DATA_HOME="$TEST_ROOT/$test_name/data"
  mkdir -p "$XDG_DATA_HOME"
  "$GODOT_BIN" --headless --path "$PROJECT_DIR" --script "res://tests/${test_name}_test.gd" 2>&1 | tee "$QA_DIR/$test_name.log"
  if rg -n 'SCRIPT ERROR:|Parse Error:|^ERROR:' "$QA_DIR/$test_name.log"; then
    exit 1
  fi
  if ! rg -q 'Shock .*: [0-9]+ checks, 0 failures' "$QA_DIR/$test_name.log"; then
    exit 1
  fi
done
printf 'Focused Shock compiler/schema checks passed; isolated data: %s\n' "$TEST_ROOT"
