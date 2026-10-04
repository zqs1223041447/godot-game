# Journey/schema26 focused verification

- Baseline: untouched `v040-dual-resource-leech`, commit `8e5f4fb3612077e31f2744450d5036972c73b9cf`, application0.40.0/schema25
- Fixture capture: external exporter run against that baseline before schema26 edits; default and real reachable leech allocation, original leading whitespace and CRLF; no user saves accessed
- Godot:4.6.3, Linux headless, isolated `/tmp/godot-m1-v041-*` XDG data/config/cache
- Pure state test:351 checks,0 failures; wall under1 second
- Migration/store test:132 checks,0 failures; focused invocation completed within45-second safety timeout (not a fixed wait)
- No editor import by this worker; existing shared imports sufficed; no600-second or historical aggregate suites

During development, the first pure-test parse needed one explicit Dictionary annotation. The first store-test parse required an explicit constant field array rather than array concatenation. The first migration probe identified Godot's new-key dot assignment creating a StringName key; migration now inserts the required field with `candidate["journey"]`. These failures were fixed before the recorded passing runs. No source passive vocabulary edits were made.

Passing commands:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v041-journey-data XDG_CONFIG_HOME=/tmp/godot-m1-v041-journey-config XDG_CACHE_HOME=/tmp/godot-m1-v041-journey-cache godot --headless --path . --script res://tests/normal_journey_state_test.gd
XDG_DATA_HOME=/tmp/godot-m1-v041-migration-data XDG_CONFIG_HOME=/tmp/godot-m1-v041-migration-config XDG_CACHE_HOME=/tmp/godot-m1-v041-migration-cache timeout 45s godot --headless --path . --script res://tests/normal_journey_migration_test.gd
```

Use a new isolated directory when rerunning the migration test; its deliberate conflicting backups are retained as evidence. The test writes only inside Godot's verified isolated user-data directory.
