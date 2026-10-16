# Transaction quick regression smoke

Current HEAD: c432c590bbf787c561f9da4204fd79a95fe408e3

Command: `python3 tools/run_transaction_regressions.py --mode quick --godot /usr/local/bin/godot --timeout 90`

Result: 15/15 passed; 1414 accepted / 1414 expected assertions; exit 0; 0 warnings; 69.104 accumulated subprocess seconds.

All 8758 tracked files, including 6264 QA files, have identical before/after SHA-256 hashes. HEAD and status unchanged.

Execution was serial, using runner-created fresh per-case XDG data/config/cache directories and strict summary/count/error/exit/timeout validation. No full profile, editor import, production edits, staging, commits, or remote operations. Godot version probe outside tests emitted fontconfig cache messages; all actual case logs passed strict error validation. This is representative quick coverage, not full-profile or Windows/UI acceptance.

Evidence: evidence/report.json and individual logs; verification.json; before-hashes.json; after-hashes.json.

Archive scope: this directory preserves case logs, runner report and verification summary. Full before/after tracked-file hash manifests and status dumps remain in /tmp/transaction-smoke-20261016 and are ephemeral, not included in Git or backup bundles. The verification was performed while those manifests were available; this compact archive alone does not reconstruct them. No additional test execution occurred during archival.
