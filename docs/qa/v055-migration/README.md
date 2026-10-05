# v0.55 schema34 migration evidence

Scope: equipment vocabulary extension only. Schema 33 is completely validated under its native item and source-tree rules before version-only conversion to 34. Source-tree execution stays at 33. The existing 32→33 step now validates its result with frozen `reason_v33`, independent of current `VERSION`.

## Genuine published input

`capture_released_v54.gd` ran against the already imported `v054-final-source-snapshot`, release commit `5e442d98e82b248efc3a553fdf9bf95733929096`. All 175 native GDScript, runtime JSON data, and project configuration files were checked against that commit by Git object hashes before execution. It did not import or edit the old project or access production user data.

Both fixtures are exact bytes written by the actual v0.54 save API, not dictionaries with their version changed:

- `fixtures/v33-default.json`: native fresh default
- `fixtures/v33-active-allocated.json`: native class change and progress APIs, actual allocations through 11364/43684/59766, an actual 100-shard currency stack, generated old-pool rare equipment, and an actual F1 group binding

See `fixtures/manifest.json` for the command, isolated `/tmp` user directory, source commit, SHA256 and sizes; `capture-46cz6d_f.log` records the one successful capture.

## Focused verification

`run-focused.py` runs only `tests/forgeblade_migration_test.gd`, after the parent's shared initial import. Every attempt gets a distinct log and evidence file; failures are preserved. Coverage:

- Genuine default/allocated 33→34 changes only version; source/RNG, every content field, revisions, UID ordering, layouts, talents, currency and grants remain unchanged
- Raw backup bytes match source; current reload neither repeats migration nor rewrites
- Current-positive metadata cache cannot smuggle forgeblade into 33; permissive optional callbacks cannot bypass native old talent legality
- Whole-envelope malformed types, future versions, identity, talent and journey rejection before backup/write
- Backup collision/failure, source disk edit during backup, real atomic temp collision, retry and retained receipt on failed replacement
- Current 34 forgeblade round-trip and actual item-move transaction failure/retry; external disk edits remain protected
- Genuine 32 fixture passes frozen 32→33→34 once with original 32 backup; built-in full history reaches 34 with exactly the published 33 default content

Execution result: **155 checks, 0 failures**, exit0, 9.417s on Godot 4.6.3, after the shared initial import. `forgeblade-migration-og4jvepj.log` and `evidence-og4jvepj.json` retain output, command, isolation, exact tested source hashes and error scan. No SCRIPT/Parse/ERROR markers occurred. All recorded tested input hashes still matched after the run. Historical broad suites and 600-second simulations are outside scope.
