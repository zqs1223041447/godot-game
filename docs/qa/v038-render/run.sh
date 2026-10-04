#!/bin/bash
set -eu
r=/workspace/scratch/a51485f153de/v023-profile-users/v038-render-final
mkdir -p "$r/data" "$r/config" "$r/cache"
cd /workspace/scratch/a51485f153de/v036-map-bosses
XDG_DATA_HOME="$r/data" XDG_CONFIG_HOME="$r/config" XDG_CACHE_HOME="$r/cache" RENDER_BATCH_OUT=/workspace/scratch/a51485f153de/v038-render-validation godot --path . --script /workspace/scratch/a51485f153de/v038-render-validation/render_batch.gd > /workspace/scratch/a51485f153de/v038-render-validation/run.log 2>&1
