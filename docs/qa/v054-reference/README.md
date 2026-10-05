# v0.54.0 faster burning offline reference evidence

Result: PASS on the first run. A single Godot headless export regenerated the catalog and source-tree coverage together in 11.854 seconds, exit 0, with empty stderr and no script errors/assertions. The exporter inputs remained unchanged during export and at final verification. No Godot import, additional Godot test, historical full suite, screenshot, font/image change, Git operation or network request was used for this reference work.

## Verified scope

- Source 3.29.1 remains pinned to original SHA256 `7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122`. All original English names/stats, mastery records, geometry, adjacency and old unrelated execution records remain exact
- Exactly 11364 (+5%), 43684 (+5%) and 59766 (+15%) become complete. Every class has exactly 685→688 reachable ordinary nodes; all 21 paths pass the real complete-build validator, and schema32 rejects them. There are no additional newly reachable old nodes or mastery effects
- Matching standard 48823 Deadly Draw remains partial because Bow Skill DoT is unsupported. Matching nonstandard 19686 Wasting Affliction remains partial because increased Ailment Damage is unsupported. Neither becomes allocatable
- Eight real compiler comparisons cover M=0/M=0.10, F=0.25, Meteor/Tornado and Ignite/Ember. All actual compiler roles are displayed, with effective DPS, compressed duration and total consumed directly. F is the additive fraction, not a second presentation multiplier
- With M=0.10, Meteor Ignite changes from 106.42500000000001 DPS for 3 seconds to 133.03125 DPS for 2.4 seconds. Exported theoretical totals are 319.27500000000003 and 319.275. Tests compare them with tolerance `max(1e-9, 1e-12*abs(old_total))`, without replacing production values with an idealized constant
- One complete legal class4 branch includes all three nodes, costs 14 points and is available from level10. The full build preserves every route grant and compiles the actual resulting 25% faster burn
- Ember with M=0.10/F=0.25 starts at 10, expires at 12.4 and transfers at 11.75 with about 0.65 seconds remaining. Source and recipient use the same already-computed 88.6875 DPS and absolute expiry. Transfer at expiry is empty
- Absent and explicit zero F have byte-identical current compiled structures. Both M=0 and nonzero M=0.10 structures also match the published v53 catalog, including omission of optional faster/base-duration keys
- Direct-hit packets, recipes, mana, cooldown, shock and enemy burn remain unchanged. The source stat is currently consumed only by player burning; this does not implement bleeding, poison or a full damaging-ailment system
- Strict schema32→33 migration evidence changes only version, with item count and talents preserved
- 123 rendered values, all internal links, local assets and deterministic build match the exported data. All 67 preexisting PNG fingerprints are unchanged

## Published baseline and explicit differences

The reference baseline was captured before export from the v0.53.0/schema32 catalog on the parent-verified base `e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a`. `v053-reference-baseline.json` records its full catalog hash, 58 catalog-section hashes, published compiler examples, graph reachability and image hashes.

The focused comparison restores only enumerated current-version metadata, excludes four explicitly updated explanatory text fields, and allows the new zero-valued `damaging_ailments_faster` field in 11 derived-stat examples: canonical default stats, fresh configuration, six old monster-attack defense dictionaries and three historical Fire DoT legal-build stats dictionaries. Complete compiled snapshots are checked separately and retain their old structures at zero F. All other compared old catalog data is unchanged.

The historical Fire DoT exporter now checks its coverage report against its actual schema32 introduction version rather than the current schema33 version. Its old examples and source evidence remain intact; the page identifies its coverage counts as historical and links to the new faster-burning section.

## Commands and evidence

The bounded runner was `python3 docs/qa/v054-reference/run-reference-checks.py --export`. It refuses to overwrite existing evidence. No retry or failed check occurred.

| Check | Exit | Seconds |
| --- | ---: | ---: |
| Godot headless `tools/export_reference.gd` | 0 | 11.854 |
| `python3 tools/build_reference.py` | 0 | 0.416 |
| `python3 tools/build_reference.py --check` | 0 | 0.417 |
| `python3 tests/faster_burn_reference_test.py` | 0 | 1.940 |
| `node --check docs/reference/reference.js` | 0 | 0.065 |

- `godot-export-result.json` and its stdout/stderr: actual command, isolated XDG directory, exit, duration and source stability
- `export-source-sha256.json`: project, all runtime scripts, JSON source data, exporter and coverage input fingerprints at export
- `python-validation-results.json` and each check's stdout/stderr: exact validation commands and results
- `final-artifact-sha256.json`: final reference code, generated documents, baseline and test fingerprints
- `summary.json`: machine-readable result and final source-fingerprint verification

These are static/structural reference checks plus a runtime export. They do not claim browser visual acceptance or a historical full-suite pass.
