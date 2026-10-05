# v0.55 real model / main gameplay verification

Base: v0.54 `5e442d98e82b248efc3a553fdf9bf95733929096`.

Passing run: Godot 4.6.3, 374 checks, 0 failures, exit 0. No `ERROR:` or `SCRIPT ERROR:` lines. Source tree SHA-256: `067317c0f74ead693075a3286fe9cc80eab6ef814d6e6085cfa655592cf48959`. Full per-file hashes are in `gameplay-source-02.json`; exact console output, exit status and numeric output are `gameplay-02.console.txt`, `gameplay-02.exit` and `gameplay-result-02.json`.

The test was run after the parent's single coordinated import. It does not import, export, modify production or run the historical suite. Both attempts use independent `/tmp/godot-m1-v055-consumers-gameplay-*` data directories. The successful run also sets a writable isolated XDG cache.

## Covered paths

- 187 checks: actual canonical equipment and shard UIDs, all six existing crafts, magic/rare damage and critical reforge, existing exact prices (8/6/24/10/28/14 and 16/40), salvage 3+sum(tiers), same UID/footprint, legitimate result families, one save and one pair of revisions, no global RNG consumption, handle replay rejection and full snapshot reload
- 47 checks: disabled life/mana leech targets, no quote or RNG consumption, cancellation, changed selected item, save failure with same-handle recovery, stale full-build quote, foreign on-disk bytes and insufficient funds; complete in-memory and disk-byte preservation on rejection
- 61 checks: real Model, actual UID equips/unequips, real Compiler white/T1/T3 budget, global critical scope on all implemented damage skills, max mana and regeneration, existing legal runewood competitor, physical armour and fire resistance separately
- 64 checks: fresh main's safe town, explicit independent test-town entry, dynamically discovered 1×3 stock, real town-buy UID, real gem transfer and same-item crafting, legal Duelist class selection and connected source allocation using earned XP, explicit map entry, actual cleave command, front/rear sector geometry, one critical roll frozen across two actors, armour 80, shield then life, noninstant life and mana leech, cooldown rejection, runtime-only recovery, frozen old weapon packet after real unequip, capped overkill leech and exact saved/reloaded item/gem/source/compiled state
- 13 checks: canonical full 240-cell fixture, refusing a new 1×3 base with no loss of currency/serial/revision/pending state, successful same-UID in-place target craft and exact reload

Two additional actual-main/full-bag completion sentinels bring the total to 374; the other three section sentinels are included in their section counts. They detect a function aborted by a script exception. No player build stat is injected or overwritten. Enemy defence/resource values are deliberately controlled test inputs. The full bag is a validated fixture; ownership, crafting and equipment changes use their authoritative APIs.

## Budget interpretation and retained first failure

The contract's B18/no-extra-attribute numbers describe the compiled base before class attribute modifiers: bare 50.4, white 61.6, legal T1 rare 65.8–69.72, T3 86.8, T3 critical expectation 90.7494. The actual default class supplies 20 Strength and 20 Intelligence even with only its required source-tree start. That adds 4% melee physical damage and 10 maximum mana.

The passing test checks both layers explicitly. Actual default-class noncritical totals are bare 52.416, white 64.064, T1 rare 68.432–72.5088 and T3 90.272; actual T3 zero-defence single-hit expectation is 94.379376. Full T3 max mana is 132, including the original class contribution and the shortblade's +22. Mana regeneration is 10.26.

The legal four-affix runewood comparison is 90.384 before class attributes, with original-crit expectation 92.6436. Its actual default-class total is 93.072, because Strength affects only its 67.2 physical part, not its 23.184 fire part. With armour 80 and fire resistance 25%, its actual total is 74.256625931446. These are single-hit comparisons, not practical DPS.

Attempt 01 completed 364 checks with 11 failed expectations caused by omitting those inherent class attributes from the fixture oracle. All crafting, atomics, actual-main hit/crit/leech and full-bag behaviours passed on that attempt. No production change was needed. Its original failure log, result, exit and source hashes remain alongside attempt 02. Attempt 01 also logged fontconfig writable-cache messages; attempt 02 does not.

This is focused gameplay verification. It does not claim whole-history coverage, a timed stress run, new visual acceptance or Windows hardware performance.
