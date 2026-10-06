# v065 external PCK probe preparation

Only the source syntax/load guard has been executed: **expected exit 78**, 1.144 seconds, zero script or engine errors. This result is not a packed-runtime pass. The final exported Windows PCK must be exercised separately by Linux Godot with this external probe.

- [Probe](../../../tools/v065_export_probe.gd)
- [Source-only command, isolation, duration, exit and hashes](probe-parse.json)
- [Source-only log](probe-parse.log.txt)

The probe contains 29 successful-path checks. It requires all five environment variables: `V065_PACK_QA`, `V065_MAIN_PACK`, `V065_SOURCE`, `V065_PACK_FONT_SHA256`, and `V065_OLD_SAVE`. The fixture is `docs/qa/v065-migration/fixtures/v40-frozen-v064.json`; the expected font hash is the SHA-256 of the original packaged font bytes. `V065_MAIN_PACK` must be an existing absolute path. `XDG_DATA_HOME` must start with `/tmp/godot-m1-v065-`, and the active user directory must reside below it. The globalized `res://` root must be empty, proving resource resolution is from a loaded PCK. Each failed check writes the report and exits 1 immediately; elapsed-time checks and a 30-second timer bound the probe.

The packed run loads the real main scene after installing the untouched frozen40 fixture. It checks schema41/source41/gear39 and an exact original40 byte backup, with both expected and actual snapshots passing through the same JSON boundary before strict comparison. It verifies the dynamic full status, exact Chinese rule, original font hash and required glyphs.

Preparation resolves every original pending item through real bag transactions, refunds the old IR route, and selects Marauder only when needed. It equips the fixture's existing legal `guardian_robe`, retaining level37 and its 41 earned points without rewriting the envelope or granting items. Twenty-two real allocations prepare the existing flat10, 1.8% regeneration and 4% shield branches; the 23rd allocates63425.

The bounded runtime checks cover authoritative final rates, unchanged independent recharge, no resource refill on allocation, real ticks during recharge wait, additive recharge, threshold crossing, real maximum-shield clamping, no life gain at full shield, the actual life flask, schema41 save/reload, refund and restored life regeneration. It finishes by rechecking the original backup bytes. Source-wide comparisons, leech, failure injection, pause and death behavior remain in the separately passing focused suites and are not rerun here.

No actual PCK runtime result was produced by the preparation worker.
