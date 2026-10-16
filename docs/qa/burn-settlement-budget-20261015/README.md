# Burn settlement budget archive — 2026-10-15

## Decision and measurement limits

**Diagnostic only; no new safe optimization established or implemented.** Settlement instrumentation materially perturbs timing: mean +26.09%, peak +31.72%; measured bookkeeping 15.57% of inclusive settlement, with 4.09% unattributed. One ordered clean/instrumented pair cannot separate environment variation from instrumentation or object-lifetime effects. Do not subtract uncalibrated remainder or mix timing denominators between the two diagnostics. PERF-001 remains open. Previously rejected prediction-cache, scalar-feedback, trusted-interface and defense-profile shortcuts remain excluded.

REPORT.md is the original run report, written before this archive commit. Its “no commit / only temporary writes” statements describe that diagnostic run, not subsequent archival. Its next-step text is historical: the settlement breakdown has now also been completed, without proving a safe candidate.

## What was preserved and checked

The 239-file manifest covers 238 production GDScript files plus the existing diagnostic fixture, not assets/imports/the full tree. Archive readback verified every entry against frozen commit b436cd2cf36fcd3f33326e05aa1b46d78ebe3108, the current checkout, and this experiment’s frozen copy. Instrumentation hashes match and the patch reconstructs executed main.gd byte-for-byte. All 20 paired observer hashes and three complete binary/save pairs were reread and matched; see archive-readback.json. This is an evidence readback, not a rerun or new gameplay test. Observer equality covers its enumerated fields only.

Current executed harness metadata correctly identifies b436cd2. The upstream fixture’s historical 4e581e2 label is preserved in that upstream file and must not be treated as this experiment’s source revision. See archive-provenance.json.

Raw observations (~31 MB per run), final binary, actual save, frozen project and imported caches remain only at /tmp/burn-settlement-budget-20261015. They are ephemeral and **not preserved in Git or bundles**. Hash receipts cannot reconstruct them after deletion. Compact JSON contains per-frame samples, timing and observer hashes; logs, manifests, original helpers and executed harness are retained here. archive-files-sha256.json hashes all archive files except itself.

## Reproduction recipe (not executed during archive)

1. In a fresh scratch directory, materialize the frozen commit, including tracked assets. Resolve/install the recorded Godot 4.6.3 engine and import assets if needed; imports/cache differences may affect timing.
2. Verify its script/fixture files against frozen-manifest.json. Keep that project unmodified for the clean run. Apply instrumented-main.patch to a separate copy of scripts/main.gd; verify the result against instrumentation-manifest.json. Use archived harness.gd unchanged.
3. Adapt only path constants in archived run.py to fresh scratch paths: repo points to the clean frozen project, main.gd to the reconstructed instrumented file, harness.gd to this archived harness. Preserve clean-then-instrumented order, fresh XDG for each run, 20 ticks and timeout 90. Never execute the archived original setup.py/run.py directly against existing evidence paths: they contain original absolute paths and can overwrite evidence.
4. Adapt verify.py paths to the fresh output and frozen project before checking hashes, complete artifact bytes, all 20 frames, sentinel and error-free logs. Record both process exit codes separately; successful log sentinel alone does not prove exit 0. Do not overwrite this archive or seek favorable samples. A future rerun is new evidence, not a recreation of the original timing.

No production changes, Windows rendering/FPS claim, full-suite claim, remote delivery or new optimization acceptance is implied by this archive.
