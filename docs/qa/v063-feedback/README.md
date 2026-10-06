# Dense-combat feedback cost investigation (no production candidate)

Base: frozen/published v62 b93018005413444ad6f988974f4ef3ea09902c5e. All499 production inputs remain byte-identical. This branch adds diagnostic tools/evidence only; it is not an optimized game version.

The hypothesis was that constructing six-field feedback dictionaries and then re-reading/validating their fields on every positive burn fragment might remove meaningful cost. This path and CombatFeedbackRuntime are unchanged from v50. The old clean v50 diagnosis counted79,129 positive burn settlements; its settlement subtotal did not separately attribute feedback. It was not evidence that feedback caused the whole peak.

The existing bounded scene was reused:100 catalog monsters,180 controlled real runtime carriers; no-burn24ticks and one initial volley followed by150ticks of actual burning/death/one-hop propagation. Real AI, collisions, attacks and27 eligible root rewards remain. The player is explicitly protected for sampling. This is not a recording of natural map play. Only the main feedback entry has a timing wrapper; production Model/BurnRuntime and all other main methods are unwrapped. Timer overhead is included.

| Clean case | Tick mean / p95 / max ms | Feedback mean / p95 / max ms | Feedback calls | Mean fraction |
|---|---|---|---|---|
| no-burn24ticks | 56.277 / 63.369 / 82.735 | 3.714 / 4.684 / 5.814 | 8,359 hit | 6.60% |
| death/propagation150ticks | 48.965 / 168.988 / 739.815 | 4.982 / 18.762 / 83.697 | 79,129 burn +1,458 hit | 10.17% |

These are inclusive components of the total, not additive. Their maxima need not occur in the same tick. Complete samples, mean/median/p95/max and threshold counts are in each JSON. Both clean runs exit0/no errors,4.112/9.930seconds wall time. The timing wrapper is not an optimized after-arm; no speedup claim is made.

Decision: do not implement a shared scalar interface from this evidence alone. All feedback together is10.17% of the mean in the dense case, including required validation, numeric accumulation, capacity policy and output state. Only an unmeasured fraction is removable dictionary construction/field lookup. It does not explain the approximately740ms residual peak. No scheduler, burn-rate helper, scalar state projection, aggregation/addition order, death/expiry/reward/RNG, population or visual behavior was changed. No600-second or historical full regression.

Initial diagnostic failure is preserved: a combined two-case process completed its first no-burncase, then tried to save a fresh model over the preceding case's existing user://build_save.json. The existing external-change guard correctly rejected it; the inherited assertion did not terminate the script, so the Python60-second safety timeout killed it. The original engine log was recovered byte-for-byte from that isolated XDG user log; it is not claimed to be the discarded Python stdout capture. Its partial metrics are excluded from conclusions. The corrected harness adds fail-fast save handling and runner gives every case its own fresh XDG; it also watches errors and terminates immediately. The60/45second limits are failure bounds, not intentional waits.

Reproduction: `python3 docs/qa/v063-feedback/run_profile.py`. It creates isolated XDG for each case, records original stdout, exit metadata and the exact diagnostic script hash, and stops at first error. Raw observations remain locally; tracked gzip copies roundtrip exactly with sizes/hashes in observation-archives.json. No real user save or frozen release package was edited.
