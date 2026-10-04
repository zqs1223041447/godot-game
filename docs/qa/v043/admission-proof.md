# v0.43 staged camp admission

Validated 2026-10-04 against the source hashes in `admission-source.sha256`.

## Result

Godot 4.6.3: **10,042 checks, 0 failures; 160 staged groups and 120 rejected groups**, process exit 0. Raw final output is `admission-final.log`. This is a pure script test; no editor import, historical suite, or scene simulation was required.

```sh
mkdir -p /tmp/v043-camp-admission/{data,config,cache}
XDG_DATA_HOME=/tmp/v043-camp-admission/data \
XDG_CONFIG_HOME=/tmp/v043-camp-admission/config \
XDG_CACHE_HOME=/tmp/v043-camp-admission/cache \
timeout 45s godot --headless --path . \
  --script res://tests/map_camp_admission_test.gd
```

## Admission contract

`MapCampAdmission.plan(runtime, profile, entries, geometry, player_pos, available, context)` stages in a new `MonsterRuntime` constructed from the supplied runtime's templates. It restores a deep snapshot of existing queue, roots, trace, and next ID into that temporary factory, then uses the existing `MapAdmission.create_root` pipeline for every member. Success returns all enemies and the complete staged checkpoint. Every rejection returns an empty enemy list and empty checkpoint.

Ordinary groups require exactly 8 Old Garden or 12 Broken Ruins entries. Map bosses require exactly one entry with the compiled profile's boss template. Available capacity must be a real integer between group size and 100. Map profiles retain existing compiler validation plus a strict integer wave check. Member positions and the player must be finite Vector2 values; each body uses its actual factory radius for bounds/wall clearance and pairwise separation. Member centers must be at least 230 units from the player. No corrective position changes are performed.

The helper never commits live runtime or camp/run bookkeeping. The caller must finish its own bookkeeping validation and then atomically publish the returned checkpoint and enemies. A subsequent plan after a caller commit receives new IDs; once-only camp ownership is intentionally the caller's responsibility. Actor ratings are also left to the caller after pure validation; the helper retains source actor statistics and the catalog's 0.6-second spawn delay.

## Focused evidence

- Both maps; 8/12 ordinary roots and one map boss; fixed test profiles and all three normal progression tiers
- All six normal modifiers individually, three complementary pairs, every allowed template/defense special, and allowed normal-tier aegis profiles
- Full actor dictionaries byte-compared with the same existing map admission pipeline, including named boss attacks, elemental source fields, normal modifier source fields, rewards, wave, exact positions, radii and spawn delay
- Existing roots, processed lineage, pending descendants and trace retained; new IDs sequential and unique; explicit caller commit followed by a second plan never reuses IDs
- Every successful and failed plan byte-checks the original runtime checkpoint, templates, validation state, entries, profile, geometry snapshot, warmed route cache and player position; global RNG draw sequences remain identical
- First, second and last invalid templates, outside positions, nonfinite positions and close-to-player positions; both ruin walls are represented by the same authoritative geometry implementation (the first wall is used for kth-entry rejection fixtures)
- First valid member followed by invalid template, rarity, mechanism, missing field or overlap exposes no partial group
- Insufficient, negative, oversized, boolean, floating-point, string and null capacities; missing/incomplete/oversized groups; invalid context, profile/wave, optional admission index, map geometry and numeric template defense
- Exact tangency at 230 units, exact sum-of-radii tangency, absent optional indices, and exact boss footprint at the boundary are admitted; sub-radius boundary or overlap violations are rejected without clamping

`admission-initial.log` records the first passing test revision. The final test fixes an independent reference-checkpoint alias so existing-root checks cover only preexisting roots; this removes redundant assertions and explains its lower check count. The final source hash manifest and final log are authoritative.
