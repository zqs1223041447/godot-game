#!/bin/bash
set -eu
cd /workspace/scratch/a51485f153de/v036-map-bosses
for mode in crowd combat; do
  seconds=3
  if [ "$mode" = combat ]; then seconds=10; fi
  taskroot=/workspace/scratch/a51485f153de/v023-profile-users/v038-native-$mode
  mkdir -p "$taskroot/data" "$taskroot/config" "$taskroot/cache"
  XDG_DATA_HOME="$taskroot/data" XDG_CONFIG_HOME="$taskroot/config" XDG_CACHE_HOME="$taskroot/cache" COMBAT_PROFILE_MODE="$mode" COMBAT_PROFILE_COUNT=100 COMBAT_PROFILE_SECONDS="$seconds" COMBAT_PROFILE_OUT="/workspace/scratch/a51485f153de/v038-diagnostics/native-$mode.json" godot --path . --script /workspace/scratch/a51485f153de/v038-diagnostics/render_paths_probe.gd > "/workspace/scratch/a51485f153de/v038-diagnostics/native-$mode.log" 2>&1
done
printf 'v038 native diagnostics finished\n'
