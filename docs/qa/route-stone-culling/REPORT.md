# Route-stone native culling, 2026-10-11

## Decision
Accepted a small renderer-only optimization after isolated proof. Production changes are `scripts/visuals/fantasy_environment.gd`, `scripts/visuals/static_arena_layer.gd`, plus focused `tests/route_culling_test.gd`. No commit, push, export, installation, network operation, art, camera, collision, actor, RNG or save behavior change.

Every route stone retains the exact original three draw commands and global tint index, in original order and world coordinates. Separate CanvasItems allow Godot to cull their native polygon/AA-line bounds against the entire viewport. Parent owns floor/borders/corners; stone children follow; one details child owns daylight/walls/camp ground/text; existing flag child follows. WorldDepth, foreground, HUD are unchanged. No camera-dependent visibility math or per-frame rebuilding. Maps without routes and shader study-ground maps retain their old path. Parts rebuild only when bounds/font/geometry changes, not on encounter-state changes.

## Native evidence
Godot 4.6.3 debug, real dot Linux desktop, OpenGL 4.5 Compatibility, Mesa llvmpipe software rasterizer. Native UI selected Prepare/Open for authored old_garden tier I (25 initial actors, no fake carriers). Existing isolated QA save was copied. Save writes occurred only in the new QA copy. This is not Windows, release-build, hardware-GPU or sustained-load evidence.

The first bounded experiment suppressed routes only as a diagnostic on a frozen actual scene, alternated baseline/suppressed/baseline/suppressed, 60 measured frames/block after 10 warmup frames. Baseline draw calls 1513; suppressed 1082. Median frame intervals 27.548 vs 23.475 ms. Suppression was restored and is absent from production.

Then retained independent-stone candidate vs baseline alternated A/B/A/B, 90 measured frames/block after 10 warmup frames. Entry and first native-input awakened combat scenes were frozen for causal comparison; simulation and HUD processing disabled equally, with no actor spawning, seeding, protection, damage injection, or gameplay-method shortcuts. Raw frame intervals use monotonic timestamps across process-frame signals; they are application cadence, not presentation or GPU timers.

| Frozen scene | Samples per mode | Baseline median / p95 ms | Candidate median / p95 ms | Draw calls baseline → candidate |
|---|---:|---:|---:|---:|
| Entry | 180 | 30.387 / 37.856 | 27.239 / 33.041 | 1513 → 1216 |
| Combat | 180 | 29.298 / 39.619 | 25.540 / 32.982 | 1511 → 1214 |

215 stones add 216 nodes including the details layer (443 → 659 total nodes in this scene). Prototype node construction/rebuild median was 1.031 ms at entry and 1.166 ms in combat. Prototype switch-back destruction was separately 1.348/2.656 ms; these costs are not steady-state frame costs. Production uses deferred destruction and does not switch modes. Actual final production rebuild timing was not separately measured.

One separate bounded live movement observation alternated A/B for eight 60-frame blocks, discarding first 10 frames of each block. Native D was held 7 seconds then A 7 seconds; ordinary auto-attack and combat advanced. Moving samples: baseline 200, candidate 163; median 31.645 → 29.046 ms, p95 39.427 → 34.135 ms, median draw calls 1428 → 1141. All four adjacent block comparisons favored candidate. Sequential live samples involve different positions and evolving combat and therefore do not isolate cause as cleanly as frozen A/B. Remaining stationary samples remain in raw moving.json. No extra timing runs were done to seek a better result.

## Pixel, command and state proof
- 30 native full-viewport byte comparisons on prototype: entry and awakened combat × 1280×720, 960×540, 1366×768 × entry camera, map center/intersection, both map corners/edges, fractional (+0.25,+0.75) camera offset. All identical.
- All corresponding snapshot state hashes remained equal: RNG state, player position, health/mana/elapsed, enemies, projectiles, particles, world geometry/context, kills. The optional `state.to_dict()` branch is absent if unsupported; this hash is not an exhaustive serialization of every gameplay object. Source diff confines production changes to rendering.
- Final lifecycle implementation independently compared against original monolithic source at entry, center/intersection, fractional position and two window sizes: 6/6 native byte-identical viewport pairs. These final checks were after helper extraction and lifecycle conversion, not inferred from prototype results.
- Flattened high-level calls and all arguments match original source across old_garden (1886 commands, 215 stones), broken_ruins (2250, 265), sunwell_terrace (2122, 271), ginkgo_arcade (2363, 248). Recorder is generated from source with only canvas type substitutions; candidate route helper is actual final source. Texture repeat state equal. This checks high-level commands, not a GPU instruction trace.
- Targeted lifecycle: old_garden → empty → old_garden, stable identities on unchanged configure/set_geometry, global indices, flag ordering, expected node counts, successful cleanup. Pass in isolated copy and exact production code.
- Existing exploration_route_visual_test: 570 checks, zero failures.
- git diff --check passes. Final production source bytes match the final native-tested copy (verification.json).

## Known test limitation
The old m0_scene_cache_test uses a legacy BuildState fixture. It fails identically on unchanged baseline and candidate with `Invalid access to property or key 'ok'` in Main._ready line 229 and one failed resume assertion (14 checks, 1 failure). It was not repaired as part of this renderer-only task and is not reported as passing. Full suite intentionally not run. Initial parse-only editor invocation reported inability to save editor settings to an empty path; no source parse errors. Later checks used explicit isolated XDG directories.

## Evidence

The parent retains this report, summary.json, results.json, moving.json, final-pixels.json, command-oracle.json, final-oracle.log, lifecycle.log and verification.json in the repository. The complete experiment and other files described below remain in the separate local QA directory; they are not all included here.
results.json / summary.json: attribution and frozen timing data plus 30 pixel/state records. moving.json: all live alternating samples. final-pixels.json: final 6 comparisons. command-oracle.json and final-oracle.log: four-map flattened call proof. pixels-runtime.log, moving-runtime.log, runtime.log: native renderer logs. PNGs: entry/combat baseline/candidate at each tested window size. pixel_observer.gd / moving_observer.gd / project/observer_main.gd: respective harnesses. prototype-source: original instrumented implementation used for timing. project contains final native-tested implementation. lifecycle and route-visual logs preserve targeted results; cache-baseline.log/cache-test.log preserve known identical failure.
