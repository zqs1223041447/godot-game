#!/usr/bin/env bash
set -euo pipefail
# Bounded same-dependencies HEAD Main vs candidate comparison. No saved progress
# or user data is used. Override BASELINE_REF only to a reviewed reward baseline.
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
BASELINE_REF="${BASELINE_REF:-180853467e352d84984471759366faeb633a19f5}"
QA_DIR="${REWARD_POLICY_QA_DIR:-$(mktemp -d /tmp/reward-policy-qa.XXXXXX)}"
mkdir -p "$QA_DIR"
QA_DIR="$(cd "$QA_DIR" && pwd)"
export XDG_CACHE_HOME="$QA_DIR/cache" XDG_CONFIG_HOME="$QA_DIR/config"
mkdir -p "$XDG_CACHE_HOME/fontconfig" "$XDG_CONFIG_HOME"
git show "$BASELINE_REF:scripts/main.gd" > "$QA_DIR/baseline_main.gd"
unset REWARD_POLICY_MAIN REWARD_POLICY_OUTPUT REWARD_POLICY_ORACLE
run_check() {
    local label="$1"; shift
    timeout 120 "$GODOT_BIN" --headless --path . --script "$@" > "$QA_DIR/$label.log" 2>&1
    cat "$QA_DIR/$label.log"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|FAIL:' "$QA_DIR/$label.log"; then return 1; fi
}
export XDG_DATA_HOME="$(mktemp -d /tmp/reward-policy-unit.XXXXXX)"
run_check unit res://tests/kill_reward_policy_test.gd
export XDG_DATA_HOME="$(mktemp -d /tmp/reward-policy-baseline.XXXXXX)"
export REWARD_POLICY_MAIN="$QA_DIR/baseline_main.gd" REWARD_POLICY_OUTPUT="$QA_DIR/baseline.json"
run_check baseline res://tests/kill_reward_equivalence_test.gd
export XDG_DATA_HOME="$(mktemp -d /tmp/reward-policy-candidate.XXXXXX)"
unset REWARD_POLICY_MAIN
export REWARD_POLICY_ORACLE="$QA_DIR/baseline.json" REWARD_POLICY_OUTPUT="$QA_DIR/candidate.json"
run_check candidate res://tests/kill_reward_equivalence_test.gd
cmp "$QA_DIR/baseline.json" "$QA_DIR/candidate.json"
sha256sum "$QA_DIR/baseline.json" "$QA_DIR/candidate.json"
printf 'Evidence: %s\n' "$QA_DIR"
