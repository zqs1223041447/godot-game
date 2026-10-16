# Spatial membership diagnostic — 2026-10-15

## Decision
Reject pursuing a no-op guard under the predeclared diagnostic gate in `predeclared-audit.md`. Same-footprint frequency passes the ≥50% opportunity gate, but original remove/reinsert work reaches only 12.63% of measured AI budget, below the ≥20% threshold. No optimization candidate or acceptance benchmark was implemented.

## Frozen source and scenario
Actual current HEAD: `7c4b3fd7ddeec9fecd7396c80573c332bb47a4e0`. All 238 production scripts plus one existing harness entry (239 manifest entries total) in `source-before.json` remained byte-identical; temporary harness/Main/index copies also remained byte-identical after execution. `verification.json` contains readback results. Main SHA256: `d891b9bd0a50b3992bfdad08636778844a15076d2b7256bc8bc56365669ba7ed`. Spatial index SHA256: `7f1b14e9f340b0740b6c19288f015a572eea6edf20f73693179e8565ccda8ef4`.

The existing `burn_prediction_cache_20261015.gd` 20-tick no-burn fixture was copied to /tmp. Uses 100 real catalog monsters, 180 controlled tornado projectiles per tick, normal geometry, AI/movement/attacks enabled, fixed seeds, protected player, and actual final save. Baseline uses current production Main. Instrumented run uses a temporary current Main copy and temporary index copy only for enemy_spatial; projectile index unchanged. The harness JSON retains its historical base_commit metadata and is NOT provenance for this run; current source-before manifest and hashes above are authoritative.

Exactly one clean run and one instrumentation-only run, in that order, with fresh per-run XDG data/config/cache/state/runtime directories and `timeout 90`. Both exit 0, expected completion markers, no script errors. Parent confirmed no competing benchmark workers. Headless CPU diagnostic only, no GPU/Windows claims. During the diagnostic: no production edits, staging, commits, or remote writes. This later archive is a documentation-only local commit.

## Observations across 20 ticks
- 2,000 update calls / 2,000 alias updates
- 1,851 identical old/new footprints (92.55%); comparison includes overflow status and exact ordered memberships after original validated insertion
- 4,521 bucket memberships removed; 4,513 inserted
- Overflow before/after and transitions: all zero
- Original remove+insert loop: 8,444 µs total, 422.2 µs/frame
- AI inclusive: 71,846 µs total, 3,592.3 µs/frame
- Separately timed footprint snapshot/comparison/count work: 4,999 µs total, 249.95 µs/frame
- AI minus that measured diagnostic work: 66,847 µs total, 3,342.35 µs/frame
- remove+insert loop / adjusted AI: 12.6318%

Loop timing includes original validation and insertion as well as removal. Diagnostic snapshots/comparisons are outside that timer. Timer/counter overhead remains, so these are diagnostic estimates, not claimed production savings. No-op validation itself would still cost work. A rough whole-update cost budget is only 0.422 ms per frame; it cannot explain or remediate residual ~550 ms burn peaks. Historical AI ~2.7 ms is likewise an independent small budget, not a source attribution for those peaks.

Clean whole-tick mean/max: 45.69445 / 57.676 ms. Instrumented whole-tick mean/max: 41.5629 / 52.328 ms. The apparent speed difference is uncontrolled single-pair variability, not optimization evidence; mutation behavior was unchanged. Even removing all measured update-loop time would be only 0.924% of this clean mean; a real guard would save less.

## Exact equivalence
20-frame typed observation bytes: equal (26,714,556 bytes). Final observation bytes: equal (1,349,116 bytes). Actual saved bytes: equal (12,222 bytes). All comparison hashes in verification.json. Instrumentation therefore preserved observed state for this fixture; this is not exhaustive candidate correctness coverage.

## Evidence
Preserved here: `clean.json`, `instrumented.json`, both logs (per-frame cumulative counts), `setup.py`, `run.py`, `harness.gd`, `spatial.gd`, `instrumented-main.patch`, source/copy hash manifests, corrected `verification.json`, predeclared gate and compact timing summary. Full typed binary observations, actual save files and temporary instrumented `main.gd` remain only in `/tmp/spatial-diagnostic-20261015`; they are ephemeral and excluded from the commit/bundles. `archive-readback.json` records independent byte comparison and both hashes while those artifacts were present. Hashes preserve identity/equality evidence but cannot reconstruct omitted bytes or independently re-prove byte equality after those files are lost. No additional experiments are justified by this gate result.
