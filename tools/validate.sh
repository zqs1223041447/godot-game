#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godot-game-validation.XXXXXX")"
trap 'rm -rf -- "$VALIDATION_DIR"' EXIT

# Isolate test settings and saves, including in restricted cloud workspaces.
if [[ "$(uname -s)" == "Linux" ]]; then
	export XDG_DATA_HOME="$VALIDATION_DIR/data"
	export XDG_CONFIG_HOME="$VALIDATION_DIR/config"
	export XDG_CACHE_HOME="$VALIDATION_DIR/cache"
	mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
fi

CHECK_INDEX=0
run_check() {
	CHECK_INDEX=$((CHECK_INDEX + 1))
	if [[ "$(uname -s)" == "Linux" ]]; then
		export XDG_DATA_HOME="$VALIDATION_DIR/data/check-$CHECK_INDEX"
		mkdir -p "$XDG_DATA_HOME"
	fi
	local log_file="$VALIDATION_DIR/check.log"
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" "$@" 2>&1 | tee "$log_file"
	# Godot may log a script/import error without a failing process exit code.
	if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log_file"; then
		echo "Validation failed: Godot reported an error." >&2
		return 1
	fi
}

echo "Godot version: $("$GODOT_BIN" --version)"
run_check --editor --import
run_check --script res://tests/build_test.gd
run_check --script res://tests/passive_jewel_test.gd
run_check --script res://tests/combat_pipeline_test.gd
run_check --script res://tests/combat_integration_test.gd
run_check --script res://tests/smoke_test.gd
run_check --quit-after 300
echo "Validation passed: import, build model, passive/jewel invariants, projectile/damage pipeline, combat/UI integration, and 300-frame startup."
