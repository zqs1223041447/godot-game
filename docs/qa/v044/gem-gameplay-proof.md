# Normal gem trade actual-main integration

Final focused run: **166 checks, 0 failures; exit 0**, Godot 4.6.3 headless.

`gem-gameplay-attempt-02.log.txt` is the final console log and
`gem-gameplay-attempt-02.json` records every assertion, the two save-file hashes,
and SHA-256 hashes for 11 relevant source files before and after the run. All
source hashes were identical across that run. The preceding 137-check passing
iteration is retained as `gem-gameplay-attempt-01.*`; it has environment-only
Fontconfig cache warnings. The final run uses an isolated writable cache and has
no warnings or errors.

Command, from the project root, with a fresh isolated data directory:

```sh
timeout 120s env \
  XDG_DATA_HOME=/tmp/godot-m1-v044-gem-gameplay-02 \
  XDG_CACHE_HOME=/tmp/godot-m1-v044-gem-gameplay-cache \
  V044_GEM_GAMEPLAY_PROOF="$PWD/docs/qa/v044/gem-gameplay-attempt-02.json" \
  godot --headless --path . --script tests/normal_gem_trade_gameplay_test.gd
```

Coverage:

- Fresh real main scene with zero shards; formal merchant derives all 26 entries
  from the catalog, with definition identity, preview, and integer active-8 /
  support-4 prices
- Two actual old-garden tier-I runs: all three camp entrance triggers admit roots,
  root deaths unlock the boss gate, boss descendants delay completion, and the
  normal return/claim route earns the eight physical bag shards used for purchase
- Paid purchase through main: exact debit, one revision, one changed signal, one
  model persistence, no duplicate main autosave, and exact reload
- Bought level-1 / quality-0 UID equips into an actual group; real main cast admits
  it and uses the compiled projectile packet, recipe, count, mana and cooldown
- Bought selected UID returns to bag and recycles for exactly one shard while all
  other owned gem UIDs survive; equipped or already-recycled UID rejects
- Quotes reject in maps, map completion, practice and the test profile; captured
  unconsumed quotes cannot survive a leave/return or profile round trip, retired
  models cannot write, explicit cancel invalidates, and a world-context signal
  invalidates even when the world revision itself is unchanged
- Test supplier remains free, its newly owned gem cannot recycle into formal
  currency, and the normal and test save files remain isolated
- Every rejection compares the complete canonical build, observed run state,
  world state, save counters, and existence plus full bytes of both save files
- Successful trades preserve loot/combat RNG, flask runtime and cooldown debt

Limits: this is scene/API integration, not native GUI or player-input verification.
Map targets are defeated through the real damage and spawn-drain methods so the
focused check finishes quickly. Before the purchase, direct runtime calls seed
non-empty flask recovery and cooldown sentinels because the town correctly
blocks flask/cast input. No fabricated currency, catalog instances, production
edits, full-suite run, or all-map permutation sweep is used here. The model and
native-control suites provide separate coverage for their respective layers.
