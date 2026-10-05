# v0.56 ordinary forgeblade melee rules

Production scope: `combat_data.gd`, `skill_compiler.gd`, `weapon_local_rules.gd`.
A validated forgeblade profile selects the new `basic` direct packet. Its authored
recipe is `CombatData.BASIC_MELEE`: melee delivery, 60 px reach, PI/4 half-angle,
one target. The packet has exactly hit/attack/melee tags and both coefficients 1.
The existing weapon-local stage contributes W once. Critical has only a primary
profile; the existing hit-based life/mana leech profile and settlement are reused.
There is no mana/cooldown field, projectile, secondary, area scaling or projectile
speed scaling. Invalid raw statistics still pass through all existing validation.

The direct frozen getter admits only a packet with a validated forgeblade weapon
trace and the authored tags/coefficients. It consults the packet's frozen source,
so later equipment changes cannot reinterpret either a melee hit or an old arrow.
The old projectile/secondary getter and non-forgeblade compiler paths are intact.

`run_rules.py` runs one released-v055 probe and one current consumer test after the
parent's unified import. It reuses the already imported complete published v0.55
source tree at commit `63d84b2db67feb51595caf786e0c311736f08a74`; no old production
file is rewritten, faked, selectively transplanted, or copied into a new tree.
Every baseline production source is checked against the release manifest before
execution and checked unchanged afterward. The same external probe resolves each
project's native `res://` preloads. Current test inputs are hashed before/after.

The binary oracle stores complete original returned Variants, preserving types,
field order, nested shape, and error strings. It includes all existing v0.54 local
weapon cases plus wider v0.55 non-blade basic, all other skill and blade-cleave
cases. Separately, 24 genuine released basic projectile snapshots (including the
v0.55 blade-equipped arrow) are replayed through current frozen getters and the
actual projectile runtime. Full carrier/event bytes cover no effect, return,
flight-end explosion, both effects, and actual contacts. Both oracle and current
run verify that global RNG is untouched.

The new test covers white/T1/T3 local damage, external added physical/fire,
applicable/non-applicable damage and spatial scopes, primary critical, actual
shield+health leech settlement excluding overkill, invalid source/stat rejection,
recompilation rejection, direct-provenance forgery, and deep-copy isolation.

## Verified result

- Released capture: 4,431 complete returned Variants and 24 original in-flight
  carriers; all baseline production files match the published source manifest.
- Current focused suite: 4,623 checks, zero failures. No engine/script errors.
- Passing evidence: `20261005T180040597719Z-results.json`. Both current test inputs
  and the complete baseline production sources stayed unchanged during execution.
- The first report, `20261005T175946636611Z-results.json`, is retained. Its only
  failure was a test fixture that converted an invalid StringName base into a
  valid String while adapting bow profiles. Requiring the original String type
  fixes that fixture. No production code changed in response to the failure.
- The passing replay reuses the initial binary oracle after checking its hash,
  successful original capture record, base commit, and all baseline source hashes.
  `--reuse-oracle` makes this focused retry reproducible without running a second
  released capture.
