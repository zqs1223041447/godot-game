# v051 inventory component probe

Source: `7b1642d471872cfa6a24a7c897352db181915320`. Godot 4.6.3 stable, headless. One invocation, three panel samples and three small control/theme comparisons. Exit **0**; `breakdown.log` has no errors and `breakdown.json` has no failed checks. The shared import had already exited 0; `../v051/import.log` contained no ERROR, SCRIPT ERROR, Parse Error, or FAIL before the probe began.

This is **not** the production main/HUD first-I latency test. It creates the built-in 38-item canonical state, a legally themed ancestor, and a derived inventory panel. It does not instantiate main/HUD or the arena, perform reward deaths, simulate input/pause, save/load user builds, or measure rendering. All production files are unchanged by this probe. The old 43.731 ms result is a separate 43-item/main/HUD fixture recorded against a9a402d; its inspected inventory/HUD/catalog code is unchanged at the current source revision.

## Measured components

Times are milliseconds. Nested columns are **nonadditive**. Instrumentation overhead is included; per-kind item-definition timing includes a small amount of grouping bookkeeping beyond the all-kind timer.

| Component | Sample 1 | Sample 2 | Sample 3 |
|---|---:|---:|---:|
| Panel setup | 238.017 | 238.650 | 256.701 |
| Build including child ready | 61.297 | 9.544 | 10.303 |
| Initial dirty refresh | 176.700 | 229.091 | 246.380 |
| Item definitions, all 34 calls | 163.413 | 212.665 | 237.194 |
| Support gems, 16 calls | 162.659 | 212.165 | 236.511 |
| Crafting refresh | 7.732 | 13.231 | 7.119 |
| Crafting metadata | 0.121 | 0.152 | 0.122 |
| Confirmation dialog construction | 2.147 | 1.983 | 1.915 |
| Extra clean refresh | 0.003 | 0.003 | 0.003 |
| VisualTheme.create_theme | 0.174 | 0.153 | 0.160 |
| Fresh-theme CraftControls new/add/ready | 3.598 | 3.439 | 3.403 |
| Prepared-theme CraftControls new/add/ready | 3.193 | 2.919 | 3.251 |
| No-ancestor CraftControls fallback | 3.004 | 3.262 | 2.987 |

The resource context matters: each panel is freed between samples, releasing its held texture references. All samples share one process, but resources are not deliberately pinned. Therefore samples 2/3 are not a claim that all texture loads remain warm. In particular, standalone support-gem definition work cannot be extrapolated to main/HUD, which has other resource owners. Sample 1's larger build time is consistent with first-use script/resource work, but this probe does not split the runtime grid load from other construction and does not assign the difference to a measured subcomponent.

## Theme decision

Do **not** prioritize a theme-sharing production change from this evidence. A theme creation measured only 0.153–0.174 ms. Supplying an already-prepared, equivalent unscaled theme reduced control construction by 0.152–0.520 ms in these fixed-order samples, but the prepared theme's creation was intentionally outside the control timer. This is a small component comparison with order/cache noise, not a statistically established first-open improvement. No claim of a 43 ms theme cost is supported.

The probe retains standalone fallback and compares actual effective control/popup font, color, style-property, and minimum-size signatures. These matched for font scales 1.0 and 1.2. At 1.2, ancestor default font size was 19 while each local control theme and popup remained 16. Direct sharing of the scaled HUD theme would change that behavior. This was structural verification, **not** rendered pixel equivalence.

## Exact next targets and risks

1. `scripts/items/gem_catalog.gd`, `_skill_definition` / `_support_definition`: both load their texture on every definition resolution. `UnifiedItemCatalog.definition_for_instance` first validates, then `Gems.metadata_for_instance` validates again and resolves another definition, producing three definition/resource resolutions per valid gem. The measured support-gem projection cost makes this a better follow-up than theme sharing. A positive texture cache keyed by resource path, while keeping current catalog membership and payload checks, is a candidate; texture retention, hot-reload behavior, and malformed/missing-resource contracts must be considered. The current probe does not separately time texture loading and therefore cannot attribute all the cost to disk/decoding.
2. `scripts/ui/crafting_controls.gd:95–99`: apply DockStyle only when creating each operation button, rather than restyling all existing buttons on every metadata context. Canonical panel lines 218–219 then duplicate the first metadata update's salvage/recalibrate styling. Preserve the existing focus style, fonts, and legacy panel appearance if consolidating these calls. Savings remain unmeasured.
3. `scripts/ui/canonical_inventory_panel.gd:195`: split the runtime grid-script load from grid construction if investigating the first build. A preload only relocates work to startup and must not be presented as total work removed.
4. Keep `_refresh_dirty`, visibility behavior, input routing, model validation, and pause rules unchanged. There was exactly one dirty refresh plus one 3-us no-op per panel, so removing a supposed second full refresh is not justified.

## Reproduction

Run from this project with a fresh isolated root. This command mirrors the successful invocation; `mktemp` generates a new directory on rerun.

```bash
probe_root=$(mktemp -d /tmp/godot-m1-v051-inventory-breakdown-XXXXXX)
export XDG_DATA_HOME="$probe_root/data"
export XDG_CONFIG_HOME="$probe_root/config"
export XDG_CACHE_HOME="$probe_root/cache"
export INVENTORY_BREAKDOWN_OUT="$PWD/docs/qa/v051-inventory/breakdown.json"
export INVENTORY_BREAKDOWN_SOURCE=$(git rev-parse HEAD)
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot --headless --path "$PWD" --script res://tools/diagnostics/inventory_open_breakdown.gd > docs/qa/v051-inventory/breakdown.log 2>&1
probe_exit=$?
printf '%s\n' "$probe_exit" > docs/qa/v051-inventory/exit-code.txt
```

Actual isolated user directory: `/tmp/godot-m1-v051-inventory-breakdown-LR7t0c/data/godot-game-preview-v021`. The probe verified unchanged canonical state and no build save written. File checksums are recorded in `source-sha256.txt`.
