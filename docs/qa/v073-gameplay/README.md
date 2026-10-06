# v073 actual Main Frost Lock verification

Accepted result: **328 checks, 0 accepted failures across seven sections**. `acceptance-summary.json` identifies the exact retained attempt for every section and verifies that production input hashes match between them.

The single concentrated run (`attempts/20261006T074500.621859Z`) passed six sections. Its one pursuit assertion incorrectly treated native projectile knockback as autonomous movement. The feature intentionally preserves external impulse. The test now zeros that impulse for the isolated pursuit assertion; the separate external-impulse checks continue to verify original movement and decay. Only `current_boundary_and_contacts` was retried (`attempts/20261006T074557.092484Z`): 24 checks, no failures, empty stderr. No production code changed during this work.

## Coverage

- Lawful connected passive source budget; pending recovery resolved before a genuine owned Frost Lock award and slot-index-2 move; wrong-skill and Lingering Chill moves reject atomically
- Exact selected mana payment, native five pellets/two pierce/three-second slow/four-second cooldown, 0.75 primary-hit multiplier, and full atomic mana/cooldown/whole-volley-capacity refusals
- Actual in-flight Frost projectile retains its support, source critical and gear snapshot after real source refund, unlink and weapon swap; positive shield-only cold loss freezes; current settlement boundary is authoritative; returned status data is detached
- Real Main settlement for normal/magic/rare/boss durations, no refresh while frozen or immune, hidden thawed immunity, later reapplication, and birth/zero/no-cold/secondary/DOT/lethal/absent-policy exclusions
- Enemy contact already executed in the frame stays executed; subsequent contact timer and pursuit pause; partial thaw consumes only active time; original frost slow still scales movement; repeated real 1/60 ticks use exact frame starts
- A projectile freeze blocks new end-tick telegraphs; existing windup pauses with attack identity, locked center and authored recovery intact, then resumes partially and resolves once; monster frost attack receives no player freeze metadata
- Actual burn settlement, shock aging and shock damage amplification continue; energy-shield recharge, knockback, original decay, spatial separation and wall clipping continue
- Reward death runs once and clears freeze; Main reaches 100 active statuses; death frees capacity for a new target; player death, restart, town/profile/map entry and map completion clear statuses

## Checked fixture

`fixtures/selected.json` is a lawful schema47 build saved by the already exercised actual Main owned-item scenario. `fixtures/selected-casts.json` contains its stats, basic cast, owned Frost cast and unselected Frost comparison for F8 inspection. A read-only model reload validated the schema and selected cast before export. The successful exporter log is in `export-attempt-02`; it reports four checks and empty stderr. The first export attempt omitted disposable XDG roots, so Godot could not create its user-data/cache directories; its raw failure remains in `export-attempt-01`. The retry supplied isolated writable roots and succeeded without code changes.

## Reproduce

Run the coordinator's shared import first, then:

```
python tools/run_frost_lock_gameplay.py
python tools/run_frost_lock_gameplay.py --sections current_boundary_and_contacts
```

The runner isolates all Godot XDG directories, stores stdout/stderr and before/after hashes for each attempt, and requires all requested sections to complete without engine/script errors. A successful full run also exports its checked legal fixture.

No legacy full-history run, 90-tick old-byte oracle, UI test or exported executable was run here. The coordinator owns the existing old-byte artifacts, and the separate scheduler test covers exhaustive pause ordering and echo behavior.
