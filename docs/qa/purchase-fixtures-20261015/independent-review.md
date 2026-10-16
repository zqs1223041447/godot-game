# Independent purchase fixture review

Reviewed 2026-10-15/16 UTC. Decision: ACCEPT scoped test-only changes; no blocking findings.

## Scope and static review

Read repository AGENTS.md and ACTIVE_WORK.zh-CN.md. Inspected the two gameplay diffs, new Python evidence-isolation regression, and docs/qa/purchase-fixtures-20261015/README.md plus its manifests. No repository edits, editor imports, staging, commits or remote operations were performed by this reviewer.

- Flask changes only the obsolete schema literal 55 to inherited Model.Rules.VERSION (currently 61) and associated label. Exact eight-shard debit, single successful save, one new serial/UID, repeated callback handling, replay/boundary checks, persisted state, RNG and runtime assertions are preserved.
- Equipment gameplay assertions remain intact. Report path is established before arena/save construction. Fresh atomic directory reservation rejects occupied paths; normalization, /tmp restriction, repository exclusion, and symlink-ancestor checks prevent accidental historical evidence overwrite. Missing/inaccessible parent or reservation failure exits 73. Report open/flush error handling exits 74; success is printed only after successful write.
- Native screenshot and JSON share the fresh evidence directory. Native rendering was not run: screenshot isolation was reviewed statically, not presented as screenshot/Windows acceptance.
- Reservation is an accidental-overwrite safeguard, not protection against a hostile same-user process swapping files/symlinks after validation. No concurrent attacker resistance is claimed or required for this fixture.

## Independent execution

All Godot calls use fresh XDG paths and a 90-second process timeout. No editor imports.

1. Python evidence isolation suite: six tests, thirteen Godot invocations, PASS. Two successful equipment gameplay runs each report 73 checks / zero failures, current schema 61. Eleven rejected destinations cover occupied directory/file/report, malformed and repository paths, missing parent, direct/ancestor/dangling symlink. Rejections exit 73 before arena/save creation; sentinel bytes and historical evidence remain unchanged. Retained log: /tmp/purchase-fixture-review/isolation.log. Retained per-call logs: /tmp/godot-m1-equipment-evidence-test-zvk5a47j/.
2. Flask gameplay: 79 checks / zero failures, exit 0, no script/runtime errors. Retained log: /tmp/purchase-fixture-review/flask.log. An initial reviewer command used the wrong required XDG prefix and correctly exited 78 without gameplay; it was corrected and is not counted as a gameplay pass. Rejection log retained separately.
3. Ten historical equipment evidence files independently hashed before execution and matched afterward. All 36 entries across equipment/flask/jewel in the implementation worker's historical manifest independently matched current files. The latter is manifest verification, not an independent pre-run snapshot for flask/jewel.
4. The independent guard run briefly overlapped the worker's separately isolated guard run. Functional tests only; no timing/performance conclusions. Final standalone flask run followed the worker's completion.
5. git diff --check passed. All three source/test hashes remained stable across execution and match the implementation worker's manifest.

## Final source/test SHA-256

f8f567c25f3660288f7486b53c6492c9034ca9d613ab40b214fcbaec60881b12  tests/flask_purchase_gameplay_test.gd
1589eede1da96cecc5b0034a2a45c4d80b01902e6b543560b79dc6fbcf9408b2  tests/equipment_purchase_gameplay_test.gd
1e2c3359a0079e5adf15e192f3d93644d8087c00a5c327ee5e3aa84d8b6f9ace  tests/test_equipment_evidence_isolation.py

## Final QA document SHA-256

24095a54c81866badda70113cba3daa1c93f61282df18869a3c95ec94d9abd7a  docs/qa/purchase-fixtures-20261015/README.md
5fe88aee6ba1e787803b606c53649f750f434911444d2433e5a58cec45f56bfc  docs/qa/purchase-fixtures-20261015/equipment-gameplay.log
2b54495023c4c9bed1c0dbdae7475184cb792f6086487bf8367fa93e2a624b0d  docs/qa/purchase-fixtures-20261015/equipment-transactions.log
4e20d15ba4d32c013749f273f8f213a44ee432ae521602e1fbf08f3d583217b9  docs/qa/purchase-fixtures-20261015/flask-gameplay.log
08e64876fbd47c677b28b566279ada6b1e47d264c3939c68024e10ac05ca6dd8  docs/qa/purchase-fixtures-20261015/flask-transactions.log
97c218053254f7569638c99056ad2b7505f3f1f2c025c87b9306ce1c05a9a91a  docs/qa/purchase-fixtures-20261015/isolation-regression.log
dd49a694155209a30a842b3eeb27551b4e1ff785f7e967aeb59df916fb8d5b7c  docs/qa/purchase-fixtures-20261015/jewel-gameplay.log
f028f76372dede90b07349e14d42e306bbb43dc0221745275326e82ea3a83f26  docs/qa/purchase-fixtures-20261015/jewel-transactions.log
665ce0d8a44a48381f58b50b53c9698ea39cafbc25edb4b057cfa37dfe4e90be  docs/qa/purchase-fixtures-20261015/summary.json
d2b82d40739d7cbc5835376f42a5a7fb951282a31ea5b3736438d25b5ea8231c  docs/qa/purchase-fixtures-20261015/test-sha256.json
