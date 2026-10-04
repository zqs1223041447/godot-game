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
M0_VALIDATION_DIR="$(mktemp -d /tmp/godot-m0-scene-XXXXXX)"
M1_VALIDATION_DIR="$(mktemp -d /tmp/godot-m1-batch.XXXXXX)"
mkdir -p /tmp/godot-currency-dev
CURRENCY_VALIDATION_DIR="$(mktemp -d /tmp/godot-currency-dev/batch.XXXXXX)"
ROOT_CRAFT_DIR="$(mktemp -d /tmp/godot-root-craft-ui-batch.XXXXXX)"
TOWN_UI_DIR="$(mktemp -d /tmp/v28root-ui-batch.XXXXXX)"
MAP_DEATH_UI_DIR="$(mktemp -d /tmp/v29root-death-batch.XXXXXX)"
trap 'rm -rf -- "$VALIDATION_DIR" "$PIERCE_VALIDATION_DIR" "$CRAFT_VALIDATION_DIR" "$M0_VALIDATION_DIR" "$M1_VALIDATION_DIR" "$CURRENCY_VALIDATION_DIR" "$ROOT_CRAFT_DIR" "$TOWN_UI_DIR" "$MAP_DEATH_UI_DIR"' EXIT

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
			res://tests/map_death_return_ui_test.gd)
				export XDG_DATA_HOME="$MAP_DEATH_UI_DIR/check-$CHECK_INDEX/data"
				unset PIERCE_QA_ROOT
				;;
			res://tests/town_ui_wiring_test.gd)
				export XDG_DATA_HOME="$TOWN_UI_DIR/check-$CHECK_INDEX/data"
				unset PIERCE_QA_ROOT
				;;
			res://tests/map_modifier_batch_gameplay_test.gd|res://tests/map_aegis_gameplay_test.gd|res://tests/map_geometry_integration_test.gd|res://tests/map_terrain_edge_test.gd|res://tests/terrain_crowd_and_blast_test.gd|res://tests/town_*|res://tests/reserved_hotkey_migration_test.gd|res://tests/map_runtime_boundaries_test.gd|res://tests/crafting_operations_test.gd|res://tests/crafting_growth_*|res://tests/canonical_*|res://tests/offense_skill_*|res://tests/elemental_encounter_*|res://tests/flask_*|res://tests/save_receipt_revision_test.gd|res://tests/source_*|res://tests/independent_menus_test.gd)
				export XDG_DATA_HOME="$M1_VALIDATION_DIR/check-$CHECK_INDEX/data"
				unset PIERCE_QA_ROOT
				;;
			res://tests/crafting_metadata_ui_test.gd)
				export XDG_DATA_HOME="$ROOT_CRAFT_DIR/check-$CHECK_INDEX/data"
				unset PIERCE_QA_ROOT
				;;
			res://tests/currency_transaction_test.gd)
				export XDG_DATA_HOME="$CURRENCY_VALIDATION_DIR/check-$CHECK_INDEX/data"
				unset PIERCE_QA_ROOT
				;;
			res://tests/pierce_integration_test.gd|res://tests/pierce_ui_test.gd)
				export XDG_DATA_HOME="$PIERCE_VALIDATION_DIR/check-$CHECK_INDEX"
				export PIERCE_QA_ROOT="$XDG_DATA_HOME"
				;;
			res://tests/crafting_state_test.gd|res://tests/crafting_integration_test.gd|res://tests/crafting_ui_integration_test.gd|res://tests/crafting_controls_test.gd)
				export XDG_DATA_HOME="$CRAFT_VALIDATION_DIR/check-$CHECK_INDEX/data"
				export GODOT_CRAFTING_TEST_ROOT="$CRAFT_VALIDATION_DIR/check-$CHECK_INDEX"
				unset PIERCE_QA_ROOT
				;;
			res://tests/m0_scene_cache_test.gd)
				export XDG_DATA_HOME="$M0_VALIDATION_DIR/check-$CHECK_INDEX/data"
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

# The default gate is the current batch and its direct dependencies, not an
# accumulating history of every test. Pass explicit test resource paths to run
# a changed dependency only. Successful identical-input evidence may be reused.
# The retired 600-second equipment soak is intentionally not an available gate.
if (( $# > 0 )); then
  for resource in "$@"; do
    if [[ "$resource" != res://tests/*_test.gd || "$resource" == *equipment_soak* ]]; then
      echo "Expected an explicit current test resource: $resource" >&2
      exit 2
    fi
    run_check --script "$resource"
  done
  echo "Selected checks passed."
  exit 0
fi

echo "Godot version: $("$GODOT_BIN" --version)"
python3 "$PROJECT_DIR/tools/check_font_coverage.py"
run_check --editor --import
run_check --script res://tests/map_modifier_batch_rules_test.gd
run_check --script res://tests/map_modifier_batch_gameplay_test.gd
run_check --script res://tests/map_modifier_atomic_test.gd
run_check --script res://tests/map_modifier_text_test.gd
run_check --script res://tests/map_modifier_layout_test.gd
run_check --script res://tests/map_modifier_reference_test.gd
python3 "$PROJECT_DIR/tools/check_item_transparency.py"
python3 "$PROJECT_DIR/tests/reference_catalog_test.py"
run_check --quit-after 300
echo "Current-batch validation passed: four ordinary modifiers, all154 map choices, actual contact/telegraph/shield/armour consumers, atomic admission, current UI and reference/font/assets, and startup."
