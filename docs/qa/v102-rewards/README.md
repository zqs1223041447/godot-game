# v102 reward-claim feedback: focused receipt and interaction evidence

All three groups passed on their first run: **262 checks, zero failures**. Godot
4.6.3 headless completed the full/capacity/persistence groups in 5.743 / 8.154 /
6.390 seconds. Logs contain no script, parse, engine-error, or leaked-object
diagnostics. `verification.json` verifies the tested source hashes against the
current files. No old test suite, long combat simulation, Windows export, or
additional editor import was run.

## Actual boundary under test

`tests/reward_claim_feedback_test.gd` instantiates the real Main script through a
small recording subclass. Main is **not added to the SceneTree and does not run
`_ready()`**. Its `claim_normal_rewards()`, `world_context()`, and recovery methods
run unchanged. The recording override calls `super` and returns that exact result.

A real `TownServicePanel` is added to the SceneTree and initialized with this Main
instance. Its claim button's `pressed` signal invokes the production handler,
which calls actual Main and canonical persistence. The test checks both
`_reward_status.text` and emitted `feedback`, waits one process frame, and verifies
that queued UI refresh does not overwrite the result or emit it twice. The world
change signal is connected to the panel's real `refresh_world()`.

This is targeted headless interaction acceptance. It is not a complete
`main.tscn` launch, HUD input-routing test, native graphical review, or played
combat flow. The only v102 production change is TownServicePanel; Main/model
receipt and economy rules remain unchanged. Pure formatter coverage is owned by
the separate root UI test and is not duplicated here.

## Fixtures and coverage

The reward fixture uses `compile_normal("old_garden", 1, [], [])`, real canonical
`normal_start_map()` / `normal_complete_map()` transactions, and sixty
`add_normal_root_xp(0)` calls followed by the normal save. It does not fabricate
map receipts, milestone counters, reward ordinals, or currency. Transaction
success is checked before reading returned fields.

Only full-bag occupancy is synthetic and explicitly labeled in the test. It
copies a real one-cell gem envelope from the current Gems catalog, uses current
ItemLocationRules dimensions, and validates the entire candidate in one canonical
commit. No literal schema version or obsolete cell budget is embedded, and no
per-cell full metadata sorting is performed. Space is subsequently released with
real `discard_item()` transactions.

- **Full, 59 checks:** detached pending/world projections; four shards, two gems,
  one flask; exact frozen milestone definitions; post-commit world context;
  persisted state; stale world/model revision rejection; fresh repeated button
  event after all rewards are exhausted
- **Capacity, 139 checks:** nothing fits; atomic bag-full rejection; reload and
  Main recovery preserve all pending rewards; one freed cell claims map shards
  only; another two cells claim gems only; a vertical pair finally admits the
  flask; pending categories, status text, and repeated failures remain exact
- **Persistence, 64 checks:** injected `_write_bytes()` failure after a valid
  candidate; no visible credit; full pending quantities in feedback; exact disk
  and in-memory rollback; real reload plus Main recovery; successful later claim
  and safe repeated event

Every failure compares the full serialized snapshot, all relevant serials and
claimed ordinals, shard balance, exact disk bytes, actual Main RNG state, world
context, successful-save count, and model/world notification counts. A simulated
write failure increments the attempt counter once; it never counts as a
successful save. Other failures do not attempt persistence.

## Evidence

Each `*-attempt1/` folder preserves its test source, stdout/stderr, invocation,
duration, isolated XDG directory, exit code, assertion results, source hashes, and
actual Main/model receipts. There were no failed attempts or reruns to discard.

`actual-receipts.json` combines the recorded results for reuse by UI review. It
includes the actual Main result, actual model result when called, pre-click and
fresh world contexts, pending projection, status text, feedback, balance, RNG
state, and disk hash.

Two stale-world cases intentionally call Main directly: the real button fetches
the current world revision, so it cannot manufacture a stale revision. These
API-only calls do not request a new panel message; their recorded status/feedback
are the unchanged prior UI values. All success, partial, bag-full, save-failure,
and fresh-repeat cases are actual panel button events. Replay tests emit the
signal directly even after the button hides, exercising a queued/repeated event
without pretending it is a user click on a hidden control.

## Reproduce a group

Use the already prepared Godot resource cache and a fresh isolated directory for
each group. The test refuses non-v102 XDG paths, existing save files, and unknown
group names.

```bash
run_dir=$(mktemp -d /tmp/godot-m1-v102-rewards-XXXXXX)
mkdir -p "$run_dir/data" "$run_dir/config" "$run_dir/cache"
XDG_DATA_HOME="$run_dir/data" \
XDG_CONFIG_HOME="$run_dir/config" \
XDG_CACHE_HOME="$run_dir/cache" \
V102_REWARD_REPORT="$run_dir/result.json" \
/usr/local/bin/godot --headless --path . \
  --script res://tests/reward_claim_feedback_test.gd -- --group=full
```

Repeat with `capacity` or `persistence`, each with a new directory. Re-run only a
group whose tested source or behavior is affected by a later change.
