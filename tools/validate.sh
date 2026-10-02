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
run_check --script res://tests/equipment_catalog_test.gd
run_check --script res://tests/typed_affix_catalog_test.gd
run_check --script res://tests/damage_base_test.gd
run_check --script res://tests/damage_preview_test.gd
run_check --script res://tests/typed_damage_state_test.gd
run_check --script res://tests/typed_damage_integration_test.gd
run_check --script res://tests/save_guard_integration_test.gd
run_check --script res://tests/equipment_state_test.gd
run_check --script res://tests/equipment_integration_test.gd
run_check --script res://tests/skill_compiler_test.gd
run_check --script res://tests/skill_support_state_test.gd
run_check --script res://tests/skill_support_integration_test.gd
run_check --script res://tests/skill_support_ui_test.gd
run_check --script res://tests/equipment_soak_test.gd
run_check --script res://tests/passive_jewel_test.gd
run_check --script res://tests/mechanic_registry_test.gd
run_check --script res://tests/passive_balance_test.gd
run_check --script res://tests/monster_system_test.gd
run_check --script res://tests/monster_integration_test.gd
run_check --script res://tests/combat_pipeline_test.gd
run_check --script res://tests/spatial_collision_test.gd
run_check --script res://tests/projectile_schedule_test.gd
run_check --script res://tests/density_integration_test.gd
run_check --script res://tests/world_view_test.gd
run_check --script res://tests/combat_integration_test.gd
run_check --script res://tests/smoke_test.gd
run_check --script res://tests/visual_settings_test.gd
run_check --script res://tests/combat_cues_test.gd
run_check --script res://tests/combat_cues_integration_test.gd
run_check --script res://tests/fantasy_actor_test.gd
run_check --script res://tests/equipment_art_test.gd
run_check --script res://tests/material_frame_test.gd
run_check --quit-after 300
echo "Validation passed: import, original equipment rolls/loot, schema6 compatibility/protected saves, typed hit bases and previews, compiled supports/cast/UI, wide native camera/100 real enemies/spatial-reference equivalence, fantasy artwork/materials and bounded visual cues, build/save model, passive/jewel/balance invariants, shared mechanisms, monster lifecycle/scene, projectile/damage pipeline, combat/UI integration, and 300-frame startup."
