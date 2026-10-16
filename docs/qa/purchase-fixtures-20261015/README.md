# Purchase fixture repair and evidence isolation

2026-10-15 UTC; local source base `e7e7e6a`. Production code is unchanged.

## Changes

- Flask gameplay now compares the stored schema against `Model.Rules.VERSION` (currently 61), rather than historical literal 55. The same assertion still requires exactly one successful save and exactly one newly allocated UID after repeated confirmation callbacks.
- Equipment gameplay no longer overwrites historical `docs/qa/equipment-purchase` reports. It reserves a fresh `/tmp` directory by default, or accepts `EQUIPMENT_EVIDENCE_DIR` naming a new normalized absolute directory under `/tmp` with an existing parent. This follows the established burn-evidence isolation implementation. Existing files/directories, repository destinations, non-normalized paths, missing parents and symlink ancestors/destinations are rejected before gameplay starts, with exit 73. Open/write errors exit 74.
- JSON reports and the optional native screenshot both use the reserved directory. The report location is printed as `EQUIPMENT_EVIDENCE_REPORT`. Native rendering/screenshot capture was not executed in this batch.

## Verification

The legacy `tools/validate_{equipment,flask,jewel}_purchase.sh` wrappers were inspected but not executed: they have 45-second limits and clean their temporary output. Instead, each of six direct headless calls used a fresh matching XDG data/config/cache root, retained logs, and a 90-second timeout. Optional flask/jewel report environment variables were removed to avoid inherited output destinations. No editor import was used. The six purchase cases ran serially. The final guard regression briefly overlapped an independent reviewer’s separately isolated headless guard run; neither run is timing/performance evidence.

| Family | Transactions | Gameplay | Failures |
| --- | ---: | ---: | ---: |
| Equipment | 115 | 73 | 0 |
| Flask | 58 | 79 | 0 |
| Jewel | 48 | 43 | 0 |

All six processes exited 0 with no `ERROR:` or `SCRIPT ERROR:`. The 416 assertions are a focused purchase regression, not a full suite, native display or Windows acceptance result. `summary.json` includes each isolated run location and the before/after-verified SHA-256 manifest for all three historical purchase evidence directories. The gameplay logs also record production source hashes; `test-sha256.json` records final fixture/test hashes.

The dedicated regression is run with `python3 tests/test_equipment_evidence_isolation.py`; it retains its own fresh XDG directories and logs under `/tmp`. Coverage includes default and explicit fresh output, duplicate output, empty occupied directory, occupied file, repository and malformed destinations, missing parent, direct/ancestor/dangling symlinks, historical hash preservation, and rejection before arena or save creation. All six Python tests passed (13 bounded Godot invocations); see `isolation-regression.log` for final results. Guard tests include repeated equipment gameplay verification and are not added to the 416 distinct assertions above.

Historical evidence is preserved as it was before this batch; its contents are not regenerated or represented as current gameplay evidence. No stage, commit, push or merge was performed by this implementation worker.
