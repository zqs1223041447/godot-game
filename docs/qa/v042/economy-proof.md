# v0.42 current-vocabulary crafting economy and reachability

Final focused run: **302,609 checks, 0 failures**, exit 0, **32.615 seconds** with Godot 4.6.3. All nine direct/transitive source files in the SHA-256 map were unchanged between the captured pre-run inputs and the post-run verification. This is a focused pure-rule review, not a full game, save, transaction, UI, export, or release acceptance run.

## Evidence

- Test: [`../../../tests/build_affix_economy_test.gd`](../../../tests/build_affix_economy_test.gd)
- Final raw stdout/stderr: [`economy-run-final.log`](economy-run-final.log)
- Exact command, isolated XDG location, timing, exit and engine version: [`economy-run-final.json`](economy-run-final.json)
- Base checkout SHA and every direct/transitive source SHA-256: [`economy-source-sha256.json`](economy-source-sha256.json)
- Earlier, superseded focused run: [`economy-run-01.log`](economy-run-01.log), 301,457 checks / 0 failures; the final run includes the additional source-domain, overflow, and forced-family completion checks

The test uses `Catalog.current_pool_for_base` throughout the proof and output checks. It explicitly compares that resolution with vocabulary 27 and the production crafting `_pool`. The old reference test uses historical `pool_for_base` and therefore cannot by itself establish this batch's new-family coverage. Historical v26 pool checks here only verify that the four new families are absent; historical replay/migration acceptance belongs to its separate review.

## Coverage and finite proof domain

- Fourteen existing bases; no base added by this batch
- Every positive-weight tier unlock is read from the current profile, producing exactly 42 base/level intervals: 1–7, 8–15, 16–30 for each base
- Both ends of every interval have identical eligible family/tier pools; all positive-weight unlock thresholds are included, so no interior level can change that pool
- Fourteen per-base group/kind topology classes; the topology is checked to remain constant across the three tier intervals
- 21,402 exhaustive legal retained `(group, kind)` source states, covering magic 1/2 and rare 4/5/6 and every legal prefix/suffix split
- 756 representative source fixtures at interval endpoints; 6,084 counted successful actual plan checks, including calibration. Deterministic replay and explicit-v27 comparisons make additional calls that are not included in this plan count
- 96 single-new-family source cases: four allowed bases × four families × the eligible tier choices at each interval start (1 + 2 + 3)
- 480 forced-new-family/tier completion checks: each of the 96 cases can be completed to magic 1/2 and rare 4/5/6, under actual group and slot limits

Eligible new families are exactly `attack_life_leech`, `attack_mana_leech`, `global_critical_chance`, and `global_critical_multiplier`, on exactly `wayglass_token`, `pulse_seed`, `nine_slot_etched_ring`, and `nine_slot_threaded_gloves`. The leech families use prefix slots; the critical families use suffix slots. All four coexist in valid rare 2-prefix/2-suffix sources.

The proof reads every eligible current source family and checks that its tiers have positive weight and the supported ordered tier domain. Completion availability depends only on the retained groups and kind counts. Retained tier and value differences cannot change eligibility of another family or the remaining slots. Affix order also cannot change that completion set. Enumerating one catalog-valid representative of each retained group/kind set therefore covers those source equivalence classes without enumerating every integer value or permutation.

The independent extremum solver processes one exclusion group at a time. Its state is the added prefix/suffix count; it permits skipping the group or selecting one eligible kind and a minimum/maximum tier from it. A synthetic shared prefix/suffix group verifies that a group cannot be selected twice. It respects initial retained slots, exact requested additions and rarity capacities. This derives reachable counts and tier-sum extrema separately from the production boolean completion solver.

Every enumerated magic source advertises and independently admits rare counts 4, 5 and 6. Every unsaturated legal source admits exactly one-affix augmentation; saturated magic 2 and rare 6 sources have no legal completion and fail without a partial transaction payload. No quoted target count disagrees with the independent completion model.

Fixing each new family/tier first and solving the remaining slots proves legal result-count witnesses without seeds. Removing that forced entry from magic-2 or rare-5/6 witnesses yields legal augment source counts; retaining another entry in a rare witness yields a legal magic source for elevation. The new entry is present with positive weight in the verified production pool. “Reachable” here means a nonempty legal completion admitted by the planner's family/group/slot model, not a claim that every possible full value tuple has a known seed or that the 64-bit seed mapping is surjective.

## Economy bounds

Salvage potential is `0` for a normal item and `rarity units + sum(tier)` for eligible magic/rare items, with rarity units 1/3. Integer affix values, percentage units, basis-point units and combat effects do not enter that formula. The new families therefore introduce no additional salvage coefficient.

| Operation | Cost | Max salvage increase, levels 1–7 | Levels 8–15 | Levels 16–30 | Minimum cost minus gain |
| --- | ---: | ---: | ---: | ---: | ---: |
| Enchant | 8 | 3 | 5 | 7 | 1 |
| Elevate | 24 | 7 | 12 | 17 | 7 |
| Augment | 6 | 1 | 2 | 3 | 3 |
| Reforge magic | 10 | 1 | 3 | 5 | 5 |
| Reforge rare | 28 | 2 | 8 | 14 | 14 |

All 42 per-base bound rows are emitted in the raw log. These values come from catalog-constrained tier-sum extrema, not observed seeds:

- Enchant: maximum legal magic salvage minus normal potential 0
- Elevate: retained tiers cancel; the gain is rarity increase 2 plus the maximum sum of newly added tiers. The test enumerates every legal retained magic group/kind set and every rare target count. It obtains 17 at T3; it does not subtract an unrelated minimum magic source from a maximum rare output
- Augment: rarity and retained entries cancel; one newly added tier contributes at most 1/2/3
- Reforge: rarity cancels; legal maximum output tier sum minus legal minimum source tier sum. Reforge replaces all affixes, so the source and output extrema do not need compatible retained groups
- Calibration: cost is exactly twice salvage yield, while family, tier, count, order and rarity remain unchanged. Its salvage-potential increase is zero
- Salvage: the material credit is exactly the consumed item's potential; its quote contains no replacement item

Thus each crafting operation strictly decreases `wallet shards + held-item salvage potential`, if its quoted debit and replacement are committed correctly. Salvage converts potential to shards without increasing that sum. This rules out a pure crafting/salvage profit cycle under these rules and inputs. Wallet atomicity and persistence are deliberately outside this pure-rule proof and require their separate integration checks. This is not a claim that the prototype costs are optimal gameplay balance.

## Actual-operation and rejection checks

Seeded plans supplement the proof with negative, zero and positive seeds. All 6,084 counted outputs pass the actual current catalog, including serialization roundtrip for the expansion operations; they keep item identity/base/level and satisfy current-pool membership, eligible tiers, inclusive integer value ranges, family/group exclusivity and prefix/suffix capacities. Preserving operations retain prior entries and order byte-for-byte. Augment adds exactly one entry. Repeated source/seed plans are deterministic and actual salvage gains remain below prices.

Every new family/tier is exercised as a source through salvage, calibration, elevation, augmentation and reforge; explicit vocabulary 27 matches the default current path. Quote payloads remain economics-only with empty replacement/definition fields. Quote and plan calls leave source bytes unchanged; mutating returned nested calibration quote metadata cannot mutate its source.

Negative checks reject same-family/different-tier duplication, new T2 below 8, new T3 below 16, two prefixes or suffixes on magic, and four prefixes or suffixes on otherwise six-entry rare fixtures. Full magic/rare augmentation rejects with `no_legal_result`; malformed slot/family sources reject with `invalid_instance` and no usable partial transaction fields.

## Reproduce

Run from the checkout with writable isolated directories:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v042-economy/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v042-economy/config \
XDG_CACHE_HOME=/tmp/godot-m1-v042-economy/cache \
godot --headless --path . --script tests/build_affix_economy_test.gd
```

No production, UI, index or fixture files were edited by this review. No commit was created.
