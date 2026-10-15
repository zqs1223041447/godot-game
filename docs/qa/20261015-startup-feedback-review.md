# Independent startup recovery and trial-label review

Reviewed branch `dot/20261015-startup-recovery-coverage`, baseline `e9a0c95`, plus the working-tree startup test, label test and `scripts/main.gd` failure-label diff on 2026-10-15.

## Result

No blocking findings. Production change is limited to the failed equipment operation's notification label; transaction order, persistence, early return and success feedback are unchanged.

## Startup recovery

- Fixture history uses real canonical admission, completion, claim and root milestone operations. It persists a paid receipt before constructing Main with a fresh model; Main's actual `_ready()` loads it. World mode and active receipt fields are not fabricated.
- IO fault injection delegates normal abandonment to production and changes only `_write_bytes`; counters establish that startup attempted real recovery, while snapshot and disk equality establish failure atomicity.
- Expected fees, balances and next-run-ID arithmetic are asserted independently. Pending rewards, best tiers, duplicate old receipt rejection and persisted reload are checked across transitions. The test-profile case keeps the original model reference and normal-save path while separately asserting Main switched to a distinct profile.
- Wrong revisions and actual failed transitions retain exact observations. Positive retries exercise actual Main handlers, rather than merely model methods.
- The deliberately broken recovery subclass is test-local and activated only by `STARTUP_RED_CONTROL=skip_recovery`. It cannot affect production startup. The existing negative-control log records the intended missing-abandon failure, 13 checks / 1 failure; it was inspected, not independently rerun.
- Fresh-data and expected-prefix guards execute before fixture writes. No source/import changes were made by this review.

## Failure label

- `state.item_definition(id)` is the authoritative instance definition lookup. Its name is used only after equip fails; missing, whitespace-only or non-string values use `所需装备` rather than the raw ID.
- Current catalog names and three failure positions are explicitly represented in the new label test. The test opens the real F6 combat panel and emits the visible action button signal, then verifies footer text, no raw IDs or false success claim, stopped writes, exact disk/live preservation, previously committed equipment and successful retry.
- The test's malformed-name override is restricted to the failed-write state, so it does not bypass equipment validation during fixture preparation.

## Independent execution

Godot 4.6.3, fresh isolated /tmp XDG directories, 90-second process deadlines, no editor import:

- `STARTUP_CASE=start`: 27 checks, zero failures, exit 0; `/tmp/review-startup-start.log`
- `STARTUP_CASE=completed_test`: 24 checks, zero failures, exit 0; `/tmp/review-startup-completed_test.log`
- `TORNADO_LABEL_STAGE=2 TORNADO_LABEL_MODE=null`: 21 checks, zero failures, exit 0; `/tmp/review-tornado-label.log`
- `git diff --check -- scripts/main.gd`: clean

This is independent representative headless verification and source review, not a claim of independently rerunning all six startup or twelve label combinations or visual screenshot acceptance. Existing generated .uid/.import working-tree files were observed and left untouched; exclude unrelated generated artifacts from the final batch.
