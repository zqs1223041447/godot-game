#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

# These write tests use Linux XDG isolation. Other platforms need their dedicated
# temporary-project/userdata runner before any default user:// can be touched.
if [[ "$(uname -s)" != "Linux" ]]; then
	echo "Validation requires Linux XDG isolation; use the platform-specific isolated runner." >&2
	exit 2
fi

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godot-game-validation.XXXXXX")"
PIERCE_VALIDATION_DIR="$(mktemp -d /tmp/godot-pierce-acceptance-XXXXXX)"
CRAFT_VALIDATION_DIR="$(mktemp -d /tmp/godot-crafting-qa-XXXXXX)"
trap 'rm -rf -- "$VALIDATION_DIR" "$PIERCE_VALIDATION_DIR" "$CRAFT_VALIDATION_DIR"' EXIT

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
		unset GODOT_CRAFTING_TEST_ROOT
		case "${2:-}" in
			res://tests/pierce_integration_test.gd|res://tests/pierce_ui_test.gd)
				export XDG_DATA_HOME="$PIERCE_VALIDATION_DIR/check-$CHECK_INDEX"
				export PIERCE_QA_ROOT="$XDG_DATA_HOME"
				;;
			res://tests/crafting_state_test.gd|res://tests/crafting_integration_test.gd|res://tests/crafting_ui_integration_test.gd|res://tests/crafting_controls_test.gd)
				export XDG_DATA_HOME="$CRAFT_VALIDATION_DIR/check-$CHECK_INDEX/data"
				export GODOT_CRAFTING_TEST_ROOT="$CRAFT_VALIDATION_DIR/check-$CHECK_INDEX"
				unset PIERCE_QA_ROOT
				;;
			*) unset PIERCE_QA_ROOT ;;
		esac
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
python3 "$PROJECT_DIR/tools/check_font_coverage.py"
python3 "$PROJECT_DIR/tests/test_font_coverage.py"
python3 "$PROJECT_DIR/tools/validate_save_paths_linux.py" --godot "$GODOT_BIN"
run_check --editor --import
run_check --script res://tests/build_test.gd
run_check --script res://tests/equipment_catalog_test.gd
run_check --script res://tests/typed_affix_catalog_test.gd
run_check --script res://tests/defense_rules_test.gd
run_check --script res://tests/defense_equipment_catalog_test.gd
run_check --script res://tests/defense_equipment_state_test.gd
run_check --script res://tests/local_weapon_compiler_test.gd
run_check --script res://tests/local_weapon_catalog_test.gd
run_check --script res://tests/local_weapon_state_test.gd
run_check --script res://tests/local_weapon_integration_test.gd
run_check --script res://tests/local_weapon_budget_test.gd
run_check --script res://tests/fire_defense_integration_test.gd
run_check --script res://tests/telegraphed_area_test.gd
run_check --script res://tests/telegraph_integration_test.gd
run_check --script res://tests/telegraph_renderer_test.gd
run_check --script res://tests/encounter_compiler_test.gd
run_check --script res://tests/encounter_controls_test.gd
run_check --script res://tests/encounter_monster_composition_test.gd
run_check --script res://tests/encounter_integration_test.gd
run_check --script res://tests/encounter_ui_integration_test.gd
run_check --script res://tests/damage_base_test.gd
run_check --script res://tests/damage_preview_test.gd
run_check --script res://tests/typed_damage_state_test.gd
run_check --script res://tests/typed_damage_integration_test.gd
run_check --script res://tests/save_guard_integration_test.gd
run_check --script res://tests/progress_batch_test.gd
run_check --script res://tests/equipment_state_test.gd
run_check --script res://tests/equipment_integration_test.gd
run_check --script res://tests/resource_support_rules_test.gd
run_check --script res://tests/element_support_rules_test.gd
run_check --script res://tests/delivery_support_rules_test.gd
run_check --script res://tests/support_batch_matrix_test.gd
run_check --script res://tests/support_projectile_batch_integration_test.gd
run_check --script res://tests/support_area_chain_batch_integration_test.gd
run_check --script res://tests/support_utility_state_ui_test.gd
run_check --script res://tests/area_support_test.gd
run_check --script res://tests/area_support_integration_test.gd
run_check --script res://tests/area_support_ui_test.gd
run_check --script res://tests/skill_compiler_test.gd
run_check --script res://tests/skill_support_state_test.gd
run_check --script res://tests/skill_support_integration_test.gd
run_check --script res://tests/skill_support_ui_test.gd
run_check --script res://tests/projectile_support_rules_test.gd
run_check --script res://tests/pierce_integration_test.gd
run_check --script res://tests/pierce_ui_test.gd
run_check --script res://tests/crafting_rules_test.gd
run_check --script res://tests/crafting_transaction_planner_test.gd
run_check --script res://tests/crafting_controls_test.gd
run_check --script res://tests/crafting_state_test.gd
run_check --script res://tests/crafting_integration_test.gd
run_check --script res://tests/crafting_ui_integration_test.gd
run_check --script res://tests/equipment_soak_test.gd
run_check --script res://tests/passive_jewel_test.gd
run_check --script res://tests/special_jewel_test.gd
run_check --script res://tests/special_jewel_integration_test.gd
run_check --script res://tests/special_jewel_ui_test.gd
run_check --script res://tests/reference_export_test.gd
run_check --script res://tests/reference_launch_test.gd
run_check --script res://tests/mechanic_registry_test.gd
run_check --script res://tests/passive_balance_test.gd
run_check --script res://tests/monster_system_test.gd
run_check --script res://tests/monster_integration_test.gd
run_check --script res://tests/combat_pipeline_test.gd
run_check --script res://tests/spatial_collision_test.gd
run_check --script res://tests/projectile_schedule_test.gd
run_check --script res://tests/density_integration_test.gd
run_check --script res://tests/world_view_test.gd
run_check --script res://tests/fire_visual_test.gd
run_check --script res://tests/combat_integration_test.gd
run_check --script res://tests/smoke_test.gd
run_check --script res://tests/visual_settings_test.gd
run_check --script res://tests/combat_cues_test.gd
run_check --script res://tests/combat_cues_integration_test.gd
run_check --script res://tests/fantasy_actor_test.gd
run_check --script res://tests/equipment_art_test.gd
run_check --script res://tests/material_frame_test.gd
run_check --script res://tests/grimoire_ui_test.gd
run_check --script res://tests/equipment_painterly_art_test.gd
python3 "$PROJECT_DIR/tests/reference_catalog_test.py"
run_check --quit-after 300
echo "Validation passed: import, immutable equipment pools/RNG, scoped local weapon damage and independent balance replay, shared fire defense and natural encounter, transaction-bounded progress flush/exact saved-byte equivalence, schema13 sixteen-support matrix/byte-exact v11-v12 migration, durable crafting/issued quotes/failure recovery, schema10 support vocabulary/schema9 equipment compatibility/byte-exact backups/protected saves/special passive grants/offline reference data and launch wiring, typed hit bases and previews, compiled supports/cast/UI, wide native camera/100 real enemies/spatial-reference equivalence, fantasy artwork/materials and bounded visual cues, build/save model, passive/jewel/balance invariants, shared mechanisms, monster lifecycle/scene, projectile/damage pipeline, combat/UI integration, and 300-frame startup."
