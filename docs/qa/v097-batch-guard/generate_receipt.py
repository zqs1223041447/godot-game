"""Package already observed validation evidence; this does not execute a test."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
evidence = root / "docs/qa/v097-batch-guard"
full = json.loads((evidence / "results.json").read_text())
assert full["checks"] == 78 and full["failures"] == 0
focused = json.loads((evidence / "critical-metadata-results.json").read_text())
assert focused["checks"] == 11 and focused["failures"] == 0
prior = json.loads((evidence / "full-run-receipt.json").read_text())

def sha(path):
    return hashlib.sha256((root / path).read_bytes()).hexdigest()

assert sha("docs/qa/v097-batch-guard/pre-critical-metadata-guard.gd.txt") == prior["guard_sha256"]
assert sha("docs/qa/v097-batch-guard/pre-critical-metadata-test.gd.txt") == prior["test_sha256"]

receipt = {
    "suite": "burn_batch_guard_test.gd",
    "checks": focused["checks"],
    "failures": focused["failures"],
    "process_exit_code": 0,
    "process_wall_time_seconds": 0.492499938,
    "exit_evidence": "Standalone functions.exec/exec_command result, chunk ace94c; no trailing command masked the Godot exit",
    "test_command": "V097_GUARD_CRITICAL_ONLY=1 XDG_DATA_HOME=/tmp/godot-m1-v097-guard-data XDG_CONFIG_HOME=/tmp/godot-m1-v097-guard-config XDG_CACHE_HOME=/tmp/godot-m1-v097-guard-cache godot --headless --path . --script tests/burn_batch_guard_test.gd > docs/qa/v097-batch-guard/critical-metadata-after.log 2>&1",
    "generation_command": "python3 docs/qa/v097-batch-guard/generate_receipt.py",
    "guard_sha256": sha("tools/diagnostics/burn_batch_guard.gd"),
    "test_sha256": sha("tests/burn_batch_guard_test.gd"),
    "scope": "Final source: eleven-check focused compiler-metadata/critical-validation regression only; no subsequent full-suite rerun",
    "prior_full_validation": {"checks": 78, "failures": 0, "process_exit_code": 0, "receipt": "full-run-receipt.json", "guard_sha256": prior["guard_sha256"], "test_sha256": prior["test_sha256"]},
    "focused_failure_before_fix": {"checks": 4, "failures": 1, "process_exit_code": 1, "wall_time_seconds": 0.512153301, "exit_evidence": "exec_command chunk 250986", "guard_source": "pre-critical-metadata-guard.gd.txt", "test_source": "whitelist-only-test.gd.txt", "test_sha256": sha("docs/qa/v097-batch-guard/whitelist-only-test.gd.txt")},
    "whitelist_only_validation": {"checks": 4, "failures": 0, "process_exit_code": 0, "receipt": "whitelist-only-receipt.json"},
    "history": "Initial 77/1; corrected overlapping full run 77/0; expanded overlapping full run 78/0; focused metadata before4/1 and whitelist-only4/0; validators focused11/0 then strengthened-assertion focused11/0. Counts are not added.",
}
(evidence / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
paths = [root / "tools/diagnostics/burn_batch_guard.gd", root / "tests/burn_batch_guard_test.gd"]
paths += sorted(path for path in evidence.iterdir() if path.is_file() and path.name != "sha256sums.txt")
(evidence / "sha256sums.txt").write_text("".join(f"{sha(path.relative_to(root))}  {path.relative_to(root)}\n" for path in paths))
print(json.dumps({"focused_checks": focused["checks"], "failures": focused["failures"], "receipt": str(evidence / "receipt.json")}, indent=2))
