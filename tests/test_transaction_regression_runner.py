"""Runner tests use tiny fake executables only; no Godot or user save access."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("transaction_runner", Path(__file__).resolve().parents[1] / "tools/run_transaction_regressions.py")
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="runner-unit-", dir="/tmp")
        self.root = Path(self.temp.name)
        self.case = runner.Case("fake", "fake", "FAKE:", 3)
        self.fake = self.root / "fake-godot"

    def tearDown(self):
        self.temp.cleanup()

    def run_fake(self, source, timeout=5):
        self.fake.write_text("#!" + sys.executable + "\n" + source)
        self.fake.chmod(0o700)
        return runner.run_case(self.case, str(self.fake), self.root, self.root, timeout)

    def test_success_and_isolation(self):
        source = '''import os, pathlib
for k in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    p = pathlib.Path(os.environ[k])
    assert str(p).startswith('/tmp/godot-m1-transactions-') and p.is_dir()
assert 'BINDING_BASELINE_ONLY' not in os.environ
assert 'SAFE_EXIT_GROUP' not in os.environ
assert 'RETURN_CASE' not in os.environ
assert 'STARTUP_CASE' not in os.environ
assert 'STARTUP_RED_CONTROL' not in os.environ
assert 'BURN_EVIDENCE_DIR' not in os.environ
assert not (pathlib.Path(os.environ['XDG_DATA_HOME']) / 'build_save.json').exists()
print('FAKE: 3 checks, 0 failures')
'''
        with patch.dict(os.environ, {"BINDING_BASELINE_ONLY": "1", "SAFE_EXIT_GROUP": "unsafe", "RETURN_CASE": "bad", "STARTUP_CASE": "bad", "STARTUP_RED_CONTROL": "skip_recovery", "BURN_EVIDENCE_DIR": "/tmp/contaminated-burn"}):
            first = self.run_fake(source)
            second = self.run_fake(source)
        self.assertTrue(first["passed"])
        self.assertTrue(second["passed"])
        self.assertNotEqual(first["environment"], second["environment"])
        self.assertFalse(Path(first["environment"]["XDG_DATA_HOME"]).exists())
        self.assertTrue(Path(first["log"]).exists())

    def test_error_with_zero_exit_fails(self):
        for message in ("SCRIPT ERROR: invalid method", "ERROR: assertion"):
            result = self.run_fake(f"print('FAKE: 3 checks, 0 failures')\nprint({message!r})\n")
            self.assertFalse(result["passed"])
            self.assertEqual(result["reason"], "engine_error")
            self.assertEqual(result["returncode"], 0)

    def test_warning_is_disclosed_without_failing(self):
        result = self.run_fake("print('FAKE: 3 checks, 0 failures')\nprint('WARNING: sample')\n")
        self.assertTrue(result["passed"])
        self.assertEqual(result["warnings"], ["WARNING: sample"])

    def test_guard_exit_does_not_pass(self):
        result = self.run_fake("print('FAKE: 3 checks, 0 failures')\nraise SystemExit(78)\n")
        self.assertEqual(result["reason"], "guard_rejected")
        self.assertFalse(result["passed"])

    def test_guard_without_summary_is_classified(self):
        result = self.run_fake("raise SystemExit(78)\n")
        self.assertEqual(result["reason"], "guard_rejected")

    def test_malformed_numeric_suffixes_are_rejected(self):
        for summary in ("FAKE: -3 checks, 0 failures", "FAKE: checks=3 failures=0.5", "FAKE: 3 checks, 0 failures extra"):
            with self.assertRaises(ValueError):
                runner.parse_summary(self.case, summary)

    def test_timeout_even_after_success_output(self):
        result = self.run_fake("import time\nprint('FAKE: 3 checks, 0 failures', flush=True)\ntime.sleep(10)\n", timeout=0.1)
        self.assertEqual(result["reason"], "timeout")
        self.assertFalse(result["passed"])
        self.assertLess(result["seconds"], 3)

    def test_missing_duplicate_wrong_counts_and_failures(self):
        for output in ("", "FAKE: 3 checks, 0 failures\nFAKE: 3 checks, 0 failures", "FAKE: 2 checks, 0 failures", "FAKE: 3 checks, 1 failures"):
            with self.subTest(output=output):
                self.assertFalse(self.run_fake(f"print({output!r})\n")["passed"])

    def test_nonzero_exit(self):
        result = self.run_fake("print('FAKE: 3 checks, 0 failures')\nraise SystemExit(1)\n")
        self.assertEqual(result["reason"], "nonzero_exit")

    def test_missing_executable(self):
        result = runner.run_case(self.case, str(self.root / "missing"), self.root, self.root)
        self.assertFalse(result["passed"])
        self.assertTrue(result["reason"].startswith("launch_error:"))

    def test_timeout_budget_validation(self):
        for timeout in (0, -1, 91, float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                runner.run_case(self.case, str(self.fake), self.root, self.root, timeout)

    def test_json_summary_formats(self):
        case = runner.Case("fake", "fake", "JSON ", 3, json_summary=True)
        for failures in (0, []):
            self.assertEqual(runner.parse_summary(case, 'JSON ' + json.dumps({"checks": 3, "failures": failures})), (3, 0))
        for checks in (True, "3", 0):
            with self.assertRaises(ValueError):
                runner.parse_summary(case, 'JSON ' + json.dumps({"checks": checks, "failures": 0}))

    def test_report_does_not_count_failed_run_as_accepted(self):
        good = self.run_fake("print('FAKE: 3 checks, 0 failures')\n")
        bad = self.run_fake("print('FAKE: 3 checks, 0 failures')\nraise SystemExit(78)\n")
        report = runner.report([good, bad], "quick")
        self.assertEqual((report["cases"], report["passed"], report["failed"], report["observed_checks"], report["accepted_checks"]), (2, 1, 1, 6, 3))

    def test_matrix_and_baseline_totals(self):
        quick, full = runner.cases(), runner.cases("full")
        self.assertEqual((len(quick), len(full)), (15, 47))
        self.assertEqual(len({c.name for c in full}), len(full))
        self.assertEqual(sum(c.expected_checks for c in full if c.name.startswith("return_")), 387)
        self.assertEqual(sum(c.expected_checks for c in full if c.name.startswith("f6_")), 163)
        self.assertTrue(set(c.name for c in quick) <= set(c.name for c in full))


    def test_burn_full_only_matrix(self):
        burn = [c for c in runner.cases("full") if c.name.startswith("burn_")]
        self.assertEqual(len(burn), 2)
        self.assertFalse(any(c.name.startswith("burn_") for c in runner.cases()))
        self.assertEqual([(c.script, c.expected_checks, c.prefix, c.marker, c.json_summary, c.burn_evidence) for c in burn], [
            ("burn_state_copy_20261015", 892, "godot-m1-v050-", "Burn state copy equivalence:", False, False),
            ("burn_settlement_equivalence", 58593, "godot-m1-v063-", "BURN_SETTLEMENT_EQUIVALENCE ", True, True),
        ])
        self.assertEqual(sum(c.expected_checks for c in runner.cases()), 1414)
        self.assertEqual(sum(c.expected_checks for c in runner.cases("full")), 61824)

    def test_current_ui_full_only_matrix_and_exact_counts(self):
        expected = {
            "current_help_contract": ("Current Help contract:", 165),
            "encounter_ui_integration": ("Encounter UI integration:", 88),
        }
        selected = [c for c in runner.cases("full") if c.name in expected]
        self.assertEqual({c.name for c in selected}, set(expected))
        self.assertFalse(any(c.name in expected for c in runner.cases()))
        for case in selected:
            with self.subTest(case=case.name):
                marker, checks = expected[case.name]
                self.assertEqual((case.script, case.marker, case.expected_checks),
                                 (case.name, marker, checks))
                self.assertEqual(case.prefix, "godot-m1-transactions-")
                self.assertEqual(case.env, {})
                self.assertFalse(case.json_summary)
                self.assertFalse(case.burn_evidence)
                self.case = case
                source = f"""import os, pathlib
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    path = pathlib.Path(os.environ[key])
    assert str(path).startswith('/tmp/godot-') and path.is_dir()
assert not list(pathlib.Path(os.environ['XDG_DATA_HOME']).iterdir())
print({marker!r} + ' {checks} checks, 0 failures')
"""
                self.assertTrue(self.run_fake(source)["passed"])
                for wrong_count in (checks - 1, checks + 1):
                    result = self.run_fake(f"print({marker!r} + ' {wrong_count} checks, 0 failures')\n")
                    self.assertFalse(result["passed"])
                    self.assertEqual(result["reason"], "assertion_count_or_failure_mismatch")

    def test_burn_report_isolation_persistence_and_existing_refusal(self):
        self.case = next(c for c in runner.cases("full") if c.burn_evidence)
        source = f"""import os, pathlib, json
p = pathlib.Path(os.environ['BURN_EVIDENCE_DIR'])
assert p == pathlib.Path({str(self.root)!r}) / 'burn_settlement_equivalence-evidence'
assert not p.is_relative_to(pathlib.Path(os.environ['XDG_DATA_HOME']).parent)
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    assert os.environ[key].startswith('/tmp/godot-m1-v063-')
try:
    p.mkdir()
except FileExistsError:
    raise SystemExit(73)
report = {{'checks': 58593, 'failures': 0}}
(p / 'results.json').write_text(json.dumps(report))
print('BURN_SETTLEMENT_EQUIVALENCE ' + json.dumps(report))
"""
        with patch.dict(os.environ, {"BURN_EVIDENCE_DIR": "/tmp/contaminated-burn"}):
            first = self.run_fake(source)
            self.assertEqual(os.environ["BURN_EVIDENCE_DIR"], "/tmp/contaminated-burn")
            self.assertTrue(first["passed"], first)
            evidence = Path(first["evidence_dir"])
            original = (evidence / "results.json").read_bytes()
            self.assertFalse(Path(first["environment"]["XDG_DATA_HOME"]).exists())
            self.assertEqual(json.loads(original), {"checks": 58593, "failures": 0})
            second = self.run_fake(source)
            self.assertFalse(second["passed"])
            self.assertEqual(second["returncode"], 73)
            self.assertEqual((evidence / "results.json").read_bytes(), original)

    def test_startup_matrix_and_contaminated_environment(self):
        expected = {"start": 27, "leave": 26, "test": 26,
                    "completed_start": 25, "completed_leave": 24, "completed_test": 24}
        startup = [c for c in runner.cases("full") if c.name.startswith("startup_")]
        self.assertEqual({c.env["STARTUP_CASE"]: c.expected_checks for c in startup}, expected)
        self.assertEqual(sum(c.expected_checks for c in startup), 152)
        self.assertEqual([c.env["STARTUP_CASE"] for c in runner.cases() if c.name.startswith("startup_")],
                         ["start", "completed_test"])
        for case in startup:
            with self.subTest(case=case.name):
                self.assertEqual(case.script, "startup_recovery_failure")
                self.assertEqual(case.prefix, "godot-startup-recovery.")
                self.assertEqual(case.env, {"STARTUP_CASE": case.name.removeprefix("startup_")})
                self.assertEqual(case.marker, "STARTUP_RECOVERY " + case.env["STARTUP_CASE"] + " ")
                self.case = case
                source = f"""import os, pathlib
assert os.environ['STARTUP_CASE'] == {case.env['STARTUP_CASE']!r}
assert 'STARTUP_RED_CONTROL' not in os.environ
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    assert str(pathlib.Path(os.environ[key])).startswith('/tmp/godot-startup-recovery.')
print({case.marker!r} + '{case.expected_checks} checks, 0 failures')
"""
                with patch.dict(os.environ, {"STARTUP_CASE": "bad", "STARTUP_RED_CONTROL": "skip_recovery"}):
                    result = self.run_fake(source)
                    self.assertEqual(os.environ["STARTUP_CASE"], "bad")
                    self.assertEqual(os.environ["STARTUP_RED_CONTROL"], "skip_recovery")
                self.assertTrue(result["passed"], result)


if __name__ == "__main__":
    unittest.main()
