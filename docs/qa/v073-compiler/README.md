# Frost Lock compiler and schema47 evidence

Base: `70b75bc255c3f54c8365f959c046934e61759f6e` (schema46).

Two focused Godot 4.6.3 headless checks ran after the shared import. Both exited 0, logged no script or engine errors, and retained identical before/after dependency hashes. This folder contains the actual output, check reports and execution receipts. No historical aggregate suite was run.

| Check | Result | Elapsed | Receipt |
| --- | --- | --- | --- |
| Support/compiler | 2,920 checks; 0 failures | 1.788 seconds | `20261006T074351264435Z-compiler-receipt.json` |
| Schema migration/economy | 345 checks; 0 failures | 15.872 seconds | `20261006T074353056849Z-migration-receipt.json` |

## Compiler contract

- Only `frost` accepts `frost_lock`, in the existing two/five support-slot limits. `lingering_chill` is rejected with explicit feedback in either ordering.
- Eleven valid new-support compositions verify 0.75 primary-hit damage, unchanged secondary explosion, 1.20 mana, unchanged carrier recipe, detached exact freeze policy/profile and deterministic support ordering.
- The single-support native recipe remains five projectiles, pierce2, slow3 seconds and cooldown4 seconds.
- Raw `freeze_policy` and `freeze_profile` are rejected, with or without the new support, before resource-cost compilation. Basic compilation rejects them too.
- 879 old legal zero/one/two-support selections and five-slot representatives across every current active skill and three source configurations match the actual previous compiler and registry byte-for-byte. Basic compilation also matches. These old selections add no freeze fields.
- `frozen/manifest.json` records original and adapted source hashes. The copied base sources only remove the global class declarations; the copied compiler points its support preload at the copied old registry. Other unchanged mechanism dependencies remain the project sources captured in the receipt.

## Save and economy contract

- Schema47 adds the fixed level1/quality0 gem. Source execution policy remains45 and equipment vocabulary remains46.
- All five native46 fixtures from `docs/qa/v072-gameplay/fixtures/` migrate by changing only `version`; old gloves/rings, stat oracles and all other fields remain exact. Their original byte lengths and SHA256 values are in the check report.
- Complete frozen46 validation rejects a new Frost Lock gem in recovery or an equipped support slot, malformed envelope fields and invalid source allocations before optional callbacks. Warm item metadata does not bypass the old gem gate.
- The previous glove/ring migration remains an exact45→46 step. The actual45 loader and fresh constructor complete the full chain to47 without new gifts.
- Successful loads back up original bytes before one atomic commit, emit once, and reopen without rewriting. Backup failure, conflicting backup, external writer and real `.tmp` write failure leave live state unpublished; removing the write fault allows a safe retry.
- The actual formal merchant buys one Frost Lock for four calibration fragments, persists it and rejects reused quote handles. The existing test merchant and seeded random test reward discover it dynamically; the free test offer cannot alter the formal profile.
- The frozen26 normal reward catalog and ordinals are unchanged. An actual first-milestone transaction still yields `support:efficiency`.

Reproduction: after one shared asset import, run `python3 docs/qa/v073-compiler/run-focused.py`. Optional arguments `compiler` or `migration` run just that affected test. The runner creates separate `/tmp` XDG profiles and records the exact command, logs, dependency hashes, result and elapsed time.
