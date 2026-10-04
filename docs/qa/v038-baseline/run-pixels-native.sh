#!/bin/bash
set -eu
rootdir=/workspace/scratch/a51485f153de/v023-profile-users/v038-pixel
mkdir -p "$rootdir/data" "$rootdir/config" "$rootdir/cache"
cd /workspace/scratch/a51485f153de/v036-map-bosses
XDG_DATA_HOME="$rootdir/data" XDG_CONFIG_HOME="$rootdir/config" XDG_CACHE_HOME="$rootdir/cache" PIXEL_PROFILE_OUT=/workspace/scratch/a51485f153de/v038-diagnostics/render-pixels.json godot --path . --script /workspace/scratch/a51485f153de/v038-diagnostics/render_pixels_probe.gd > /workspace/scratch/a51485f153de/v038-diagnostics/render-pixels.log 2>&1
