# Independent review: rejected burn prediction cache experiment

Reviewed 2026-10-15 against baseline 4e581e223bf012c04c94ec1f1a558021feeea03a. Read-only repository review; no Godot runs or additional benchmarks.

## Verdict

Rejection is supported. No production optimization should be accepted from this experiment. Evidence and diagnostic tooling are reasonable to retain with the documented limits. Production main.gd is restored byte-for-byte (SHA-256 98c1f36ce2d09bdf25d285a3e8a0ad6eec76221a8af94a02d1f27c4c85994252); no scripts/main.gd or defense_rules.gd tracked diff was present.

## Independently verified

- Both pairs' full frame-array binaries, post-save final observations, and save bytes match baseline versus candidate. All four clean runs per mode and the separate ember diagnostic match their mode baseline: 39 artifacts, 30 substantive cross-run comparisons (9 recorded checks compare baseline to itself).
- All 13 profile records contain 20 samples; recorded complete-frame and final hashes/sizes match actual archived bytes. Rechecked all 39 artifacts after movement to /tmp/burn-cache-20261015/observations.
- Ember mean tick reductions are 21.8548% and 16.5812%. No-burn mean increases are 5.6571% and 11.3596%. Ignite changes are -4.2620% and +0.6604%. These support failure of the control acceptance gate, not a causal attribution free of machine noise.
- Run-record file ordering supports baseline then candidate in pair 1 and candidate then baseline in pair 2; no additional timing runs were performed by this reviewer.
- Separate diagnostic records 37,160 hits, 1,222 misses/stores, max 4 call-local entries. Its timing is excluded from clean conclusions.
- Observer includes full explicitly captured actor/projectile/queue/trace/resource/RNG/save and expanded runtime/feedback/progress/world data; snapshots and serialization occur outside the timed tick. It is not every possible scene-node property.
- Corrected edge log reports 497 checks and zero failures; first failed-assumption log remains preserved. The corrections agree with source: negative resistance clamps to zero; var_to_bytes signed-zero equality is not IEEE bit preservation. Candidate comment is historically false and README explicitly says so.
- Focused scalar model tests preserve authoritative comparisons, invalid-input failure receipts and finite-cache gating. They are not claimed to be an extracted production implementation or an exhaustive scene boundary proof.

## Remaining documentation/reproducibility limits

1. Original per-run records do not capture source hashes. Manifest hashes are retrospective. README now clearly discloses this, along with harness selection changes. Future runner source hash does not establish historical provenance.
2. Raw historical artifacts live only in /tmp, outside the proposed repository evidence. Readers can inspect hashes and rerun the supplied harness, but cannot independently recompare historical bytes after that archive disappears. This should stay explicit; preserve a durable archive if historical independent verification is required.
3. README originally said 39 comparisons; exact accounting is 39 artifacts/30 nontrivial comparisons. Requested clarification from worker.
4. Reproduction clean baseline currently means checked-out production. Recreating this historical experiment requires the pinned baseline revision (given in README), not an arbitrary future main checkout.
5. Linux headless script CPU data does not establish Windows FPS/rendering gains; README explicitly limits the claim.

The tracked modification to docs/qa/v063-settlement-rules/results.json observed during this review is unrelated generated QA noise and should not be included in this experiment's publication. The root/worker owns cleanup and final staged-file audit.

## Final correction verification

Worker corrections reviewed after the initial report: tracked diff is now empty; historical QA was preserved in the dated evidence and restored exactly. README now explicitly counts 39 artifacts/30 nontrivial comparisons and labels raw /tmp evidence ephemeral. Prepare script pins 125112823ddf88784e2399c565e974ad04afdc49 and asserts the frozen main SHA before patching. Independently verified this commit and tested local 4e581e2 share tree 2d6d8804a83aeaa17185acc90e6ef729dd95e58f. Reconstructed candidate and instrumented files under /tmp/burn-cache-20261015-reproduce-zjiw3qr9 match original preserved source bytes exactly. No remaining publication blocker for an explicitly rejected experiment archive. Historical source provenance and ephemeral raw-data limitations remain honestly documented.
