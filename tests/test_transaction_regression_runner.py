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
        self.assertEqual((len(quick), len(full)), (15, 68))
        self.assertEqual(len({c.name for c in full}), len(full))
        self.assertEqual(sum(c.expected_checks for c in full if c.name.startswith("return_")), 387)
        self.assertEqual(sum(c.expected_checks for c in full if c.name.startswith("f6_")), 163)
        self.assertTrue(set(c.name for c in quick) <= set(c.name for c in full))


    def test_burn_full_only_matrix(self):
        burn = [c for c in runner.cases("full") if c.name in ("burn_state_copy", "burn_settlement_equivalence")]
        self.assertEqual(len(burn), 2)
        self.assertFalse(any(c.name.startswith("burn_") for c in runner.cases()))
        self.assertEqual([(c.script, c.expected_checks, c.prefix, c.marker, c.json_summary, c.burn_evidence) for c in burn], [
            ("burn_state_copy_20261015", 892, "godot-m1-v050-", "Burn state copy equivalence:", False, False),
            ("burn_settlement_equivalence", 58593, "godot-m1-v063-", "BURN_SETTLEMENT_EQUIVALENCE ", True, True),
        ])
        self.assertEqual(sum(c.expected_checks for c in runner.cases()), 1414)
        self.assertEqual(sum(c.expected_checks for c in runner.cases("full")), 83206)

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

    def test_controls_and_scroll_full_only_matrix_and_positive_arguments(self):
        expected = {
            "encounter_controls": ("Encounter controls:", 3918),
            "pause_keyboard_scroll": ("Pause keyboard scroll:", 1070),
            "settings_keyboard_scroll": ("Settings keyboard scroll:", 1025),
        }
        selected = [c for c in runner.cases("full") if c.name in expected]
        self.assertEqual({c.name for c in selected}, set(expected))
        self.assertFalse(any(c.name in expected for c in runner.cases()))
        self.assertEqual(sum(c.expected_checks for c in selected), 6013)
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
                source = f"""import os, pathlib, sys
assert sys.argv[1:] == ['--headless', '--path', {str(self.root)!r}, '--script', 'tests/{case.script}_test.gd']
assert '--disable-follow-focus' not in sys.argv
assert '--' not in sys.argv
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    path = pathlib.Path(os.environ[key])
    assert str(path).startswith('/tmp/godot-') and path.is_dir()
assert not list(pathlib.Path(os.environ['XDG_DATA_HOME']).iterdir())
print({marker!r} + ' {checks} checks, 0 failures')
"""
                first, second = self.run_fake(source), self.run_fake(source)
                self.assertTrue(first["passed"], first)
                self.assertTrue(second["passed"], second)
                self.assertNotEqual(first["environment"], second["environment"])
                self.assertNotIn("--disable-follow-focus", first["command"])
                for wrong_count in (checks - 1, checks + 1):
                    result = self.run_fake(f"print({marker!r} + ' {wrong_count} checks, 0 failures')\n")
                    self.assertFalse(result["passed"])
                    self.assertEqual(result["reason"], "assertion_count_or_failure_mismatch")

    def test_focus_full_only_matrix_arguments_and_strict_results(self):
        expected = {
            "skill_binding_focus_capacity10": ("skill_binding_focus", "Skill binding focus:", 3303, "godot-skill-focus-", ()),
            "skill_binding_focus_capacity11": ("skill_binding_focus", "Skill binding focus:", 3629, "godot-skill-focus-", ("--capacity11",)),
            "talent_details_focus": ("talent_details_focus", "Talent details focus:", 5219, "godot-talent-focus-", ()),
        }
        selected = [c for c in runner.cases("full") if c.name in expected]
        self.assertEqual({c.name for c in selected}, set(expected))
        self.assertFalse(any(c.name in expected for c in runner.cases()))
        self.assertEqual(sum(c.expected_checks for c in selected), 12151)
        self.assertTrue(all(not c.user_args for c in runner.cases("full") if c.name != "skill_binding_focus_capacity11"))
        for case in selected:
            with self.subTest(case=case.name):
                self.assertEqual((case.script, case.marker, case.expected_checks, case.prefix, case.user_args), expected[case.name])
                self.assertEqual(case.env, {})
                self.assertFalse(case.json_summary)
                self.assertFalse(case.burn_evidence)
                self.case = case
                argv = ['--headless', '--path', str(self.root), '--script', f'tests/{case.script}_test.gd']
                if case.user_args:
                    argv += ['--', *case.user_args]
                source = f"""import os, pathlib, sys
assert sys.argv[1:] == {argv!r}
assert '--disable-follow-focus' not in sys.argv
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    path = pathlib.Path(os.environ[key])
    assert str(path).startswith('/tmp/{case.prefix}') and path.is_dir()
assert not list(pathlib.Path(os.environ['XDG_DATA_HOME']).iterdir())
print({case.marker!r} + ' {case.expected_checks} checks, 0 failures')
"""
                first, second = self.run_fake(source), self.run_fake(source)
                self.assertTrue(first["passed"], first)
                self.assertTrue(second["passed"], second)
                self.assertNotEqual(first["environment"], second["environment"])
                self.assertFalse(Path(first["environment"]["XDG_DATA_HOME"]).exists())
                for wrong_count in (case.expected_checks - 1, case.expected_checks + 1):
                    result = self.run_fake(f"print({case.marker!r} + ' {wrong_count} checks, 0 failures')\n")
                    self.assertFalse(result["passed"])
                    self.assertEqual(result["reason"], "assertion_count_or_failure_mismatch")
                for code, reason in ((1, "nonzero_exit"), (78, "guard_rejected")):
                    result = self.run_fake(source + f"raise SystemExit({code})\n")
                    self.assertFalse(result["passed"])
                    self.assertEqual(result["reason"], reason)

    def test_recovery_crafting_full_only_matrix_and_strict_results(self):
        expected = {
            "recovery_currency_compaction": ("Recovery currency compaction:", 308),
            "jewel_crafting": ("Ordinary jewel crafting:", 1375),
            "crafting_growth_transactions": ("Crafting growth transactions:", 286),
            "normal_gem_trade_transactions": ("Normal gem trade transactions:", 330),
        }
        selected = [c for c in runner.cases("full") if c.name in expected]
        self.assertEqual({c.name for c in selected}, set(expected))
        self.assertEqual(sum(c.expected_checks for c in selected), 2299)
        self.assertFalse(any(c.name in expected for c in runner.cases()))
        for case in selected:
            with self.subTest(case=case.name):
                self.assertEqual((case.script, case.marker, case.expected_checks),
                                 (case.name, *expected[case.name]))
                self.assertEqual(case.prefix, "godot-m1-transactions-")
                self.assertEqual((case.env, case.user_args, case.json_summary,
                                  case.burn_evidence, case.evidence_env, case.report_env),
                                 ({}, (), False, False, "", ""))
                self.case = case
                source = f"""import os, pathlib, sys
assert sys.argv[1:] == ['--headless', '--path', {str(self.root)!r}, '--script', 'tests/{case.script}_test.gd']
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    path = pathlib.Path(os.environ[key])
    assert str(path).startswith('/tmp/godot-m1-transactions-') and path.is_dir()
assert not list(pathlib.Path(os.environ['XDG_DATA_HOME']).iterdir())
for key in ('BURN_EVIDENCE_DIR', 'EQUIPMENT_EVIDENCE_DIR', 'FLASK_TRANSACTION_REPORT',
            'FLASK_GAMEPLAY_REPORT', 'JEWEL_TRANSACTION_REPORT', 'JEWEL_GAMEPLAY_REPORT'):
    assert key not in os.environ
print({case.marker!r} + ' {case.expected_checks} checks, 0 failures')
"""
                with patch.dict(os.environ, {"EQUIPMENT_EVIDENCE_DIR": "/tmp/contaminated-recovery"}):
                    first, second = self.run_fake(source), self.run_fake(source)
                    self.assertEqual(os.environ["EQUIPMENT_EVIDENCE_DIR"], "/tmp/contaminated-recovery")
                self.assertTrue(first["passed"], first)
                self.assertTrue(second["passed"], second)
                self.assertNotEqual(first["environment"], second["environment"])
                self.assertFalse(Path(first["environment"]["XDG_DATA_HOME"]).exists())
                self.assertNotIn("report_path", first)
                self.assertNotIn("evidence_dir", first)
                good = case.marker + f" {case.expected_checks} checks, 0 failures"
                for output in ("", good + "\n" + good,
                               case.marker + f" {case.expected_checks - 1} checks, 0 failures",
                               case.marker + f" {case.expected_checks + 1} checks, 0 failures",
                               case.marker + f" {case.expected_checks} checks, 1 failures",
                               good + "\nSCRIPT ERROR: invalid method"):
                    self.assertFalse(self.run_fake(f"print({output!r})\n")["passed"])
                for code, reason in ((1, "nonzero_exit"), (78, "guard_rejected")):
                    result = self.run_fake(source + f"raise SystemExit({code})\n")
                    self.assertFalse(result["passed"])
                    self.assertEqual(result["reason"], reason)

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

    def test_purchase_full_only_matrix_and_strict_counts(self):
        expected = {
            "equipment_purchase_transactions": (115, "godot-m1-transactions-", "Equipment purchase transactions:", False, "", ""),
            "equipment_purchase_gameplay": (73, "godot-m1-transactions-", "Equipment purchase gameplay:", False, "EQUIPMENT_EVIDENCE_DIR", ""),
            "flask_purchase_transactions": (58, "godot-m1-flask-purchase.", "FLASK_PURCHASE_TRANSACTIONS ", True, "", "FLASK_TRANSACTION_REPORT"),
            "flask_purchase_gameplay": (79, "godot-m1-flask-purchase.", "FLASK_PURCHASE_GAMEPLAY ", True, "", "FLASK_GAMEPLAY_REPORT"),
            "jewel_purchase_transactions": (48, "godot-m1-transactions-", "JEWEL_PURCHASE_TRANSACTIONS ", True, "", "JEWEL_TRANSACTION_REPORT"),
            "jewel_purchase_gameplay": (43, "godot-m1-jewel-purchase.", "JEWEL_PURCHASE_GAMEPLAY ", True, "", "JEWEL_GAMEPLAY_REPORT"),
        }
        selected = [c for c in runner.cases("full") if c.name in expected]
        self.assertEqual(len(selected), 6)
        self.assertEqual(sum(c.expected_checks for c in selected), 416)
        self.assertFalse(any(c.name in expected for c in runner.cases()))
        for case in selected:
            with self.subTest(case=case.name):
                self.assertEqual((case.expected_checks, case.prefix, case.marker, case.json_summary,
                                  case.evidence_env, case.report_env), expected[case.name])
                self.assertEqual(case.script, case.name)
                self.assertEqual((case.env, case.user_args, case.burn_evidence), ({}, (), False))
                self.case = case
                for count in (case.expected_checks - 1, case.expected_checks, case.expected_checks + 1):
                    tail = json.dumps({"checks": count, "failures": 0}) if case.json_summary else f"{count} checks, 0 failures"
                    result = self.run_fake(f"print({case.marker + tail!r})\n")
                    self.assertEqual(result["passed"], count == case.expected_checks, result)

    def test_purchase_report_environment_isolation_and_persistence(self):
        keys = ("EQUIPMENT_EVIDENCE_DIR", "FLASK_TRANSACTION_REPORT", "FLASK_GAMEPLAY_REPORT",
                "JEWEL_TRANSACTION_REPORT", "JEWEL_GAMEPLAY_REPORT")
        contaminated = {key: str(self.root / (key + "-sentinel")) for key in keys}
        for value in contaminated.values():
            Path(value).write_text("must not change")
        selected = [self.case] + [c for c in runner.cases("full") if "purchase" in c.name]
        for case in selected:
            with self.subTest(case=case.name), patch.dict(os.environ, contaminated):
                self.case = case
                active = case.report_env or case.evidence_env
                tail = json.dumps({"checks": case.expected_checks, "failures": 0}) if case.json_summary else f"{case.expected_checks} checks, 0 failures"
                source = f"""import os, pathlib, json, sys
assert sys.argv[1:] == ['--headless', '--path', {str(self.root)!r}, '--script', 'tests/{case.script}_test.gd']
for key in {keys!r}:
    assert (key in os.environ) == (key == {active!r})
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    assert os.environ[key].startswith('/tmp/{case.prefix}')
assert not list(pathlib.Path(os.environ['XDG_DATA_HOME']).iterdir())
if {bool(active)!r}:
    target = pathlib.Path(os.environ[{active!r}])
    assert not target.exists()
    assert not target.is_relative_to(pathlib.Path(os.environ['XDG_DATA_HOME']).parent)
    if {bool(case.evidence_env)!r}:
        target.mkdir()
        target /= 'results.json'
    target.write_text('retained report')
print({case.marker + tail!r})
"""
                first = self.run_fake(source)
                self.assertTrue(first["passed"], first)
                self.assertFalse(Path(first["environment"]["XDG_DATA_HOME"]).exists())
                if active:
                    report = Path(first.get("report_path", str(Path(first.get("evidence_dir", "")) / "results.json")))
                    self.assertEqual(report.read_text(), "retained report")
                    second = self.run_fake(source)
                    if case.report_env:
                        self.assertTrue(second["passed"], second)
                        self.assertNotEqual(first["report_path"], second["report_path"])
                    else:
                        self.assertFalse(second["passed"])
                    self.assertEqual(report.read_text(), "retained report")
                for key, value in contaminated.items():
                    self.assertEqual(os.environ[key], value)
                    self.assertEqual(Path(value).read_text(), "must not change")

    def test_live_combat_full_only_contracts_and_strict_results(self):
        expected = {
            "map_pending_death_boundary": ("MAP_PENDING_DEATH_BOUNDARY ", 107, "godot-m1-map-death-boundary-", "EXPLORATION_MAIN_OUTPUT"),
            "canonical_game_state": ("Canonical game state:", 27, "godot-m1-transactions-", ""),
            "combat_pipeline": ("Combat pipeline:", 305, "godot-m1-transactions-", ""),
            "ember_event_clock": ("Ember event clock:", 45, "godot-m1-v050-", ""),
            "burn_same_time_cleanup": ("Burn same-time cleanup:", 19, "godot-m1-v050-", ""),
        }
        selected = [c for c in runner.cases("full") if c.name in expected]
        self.assertEqual({c.name for c in selected}, set(expected))
        self.assertEqual(sum(c.expected_checks for c in selected), 503)
        self.assertFalse(any(c.name in expected for c in runner.cases()))
        for case in selected:
            with self.subTest(case=case.name):
                self.assertEqual((case.marker, case.expected_checks, case.prefix,
                                  case.fresh_evidence_env), expected[case.name])
                self.assertEqual(case.script, case.name)
                self.assertEqual((case.env, case.user_args, case.json_summary,
                                  case.burn_evidence, case.evidence_env, case.report_env),
                                 ({}, (), False, False, "", ""))
                self.case = case
                good = case.marker + f"checks={case.expected_checks} failures=0"
                source = f"""import os, pathlib, sys
assert sys.argv[1:] == ['--headless', '--path', {str(self.root)!r}, '--script', 'tests/{case.script}_test.gd']
for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
    path = pathlib.Path(os.environ[key])
    assert str(path).startswith('/tmp/{case.prefix}') and path.is_dir()
assert not list(pathlib.Path(os.environ['XDG_DATA_HOME']).iterdir())
assert 'EXPLORATION_MAIN_INPUT_ONLY' not in os.environ
assert 'EXPLORATION_MAIN_SAVE_ONLY' not in os.environ
assert ('EXPLORATION_MAIN_OUTPUT' in os.environ) == {bool(case.fresh_evidence_env)!r}
print({good!r})
"""
                with patch.dict(os.environ, {"EXPLORATION_MAIN_OUTPUT": "/tmp/unsafe-history",
                                             "EXPLORATION_MAIN_INPUT_ONLY": "1",
                                             "EXPLORATION_MAIN_SAVE_ONLY": "1"}):
                    result = self.run_fake(source)
                    self.assertTrue(result["passed"], result)
                for output in ("", good + "\n" + good,
                               case.marker + f"checks={case.expected_checks - 1} failures=0",
                               case.marker + f"checks={case.expected_checks + 1} failures=0",
                               case.marker + f"checks={case.expected_checks} failures=1",
                               good + " trailing", good + "\nERROR: invalid state"):
                    self.assertFalse(self.run_fake(f"print({output!r})\n")["passed"])
                for code, reason in ((1, "nonzero_exit"), (78, "guard_rejected")):
                    result = self.run_fake(source + f"raise SystemExit({code})\n")
                    self.assertFalse(result["passed"])
                    self.assertEqual(result["reason"], reason)

    def test_map_evidence_is_fresh_existing_retained_and_never_overwrites(self):
        self.case = next(c for c in runner.cases("full") if c.name == "map_pending_death_boundary")
        historical = self.root / "historical"
        historical.mkdir()
        sentinel = historical / "pending-death-boundary.json"
        sentinel.write_text("historical evidence")
        source = f"""import os, pathlib
p = pathlib.Path(os.environ['EXPLORATION_MAIN_OUTPUT'])
assert p.is_dir() and not list(p.iterdir())
assert p.parent == pathlib.Path({str(self.root)!r})
assert p.name.startswith('map_pending_death_boundary-evidence-')
assert not p.is_relative_to(pathlib.Path(os.environ['XDG_DATA_HOME']).parent)
(p / 'pending-death-boundary.json').write_text('new evidence')
print('MAP_PENDING_DEATH_BOUNDARY checks=107 failures=0')
"""
        with patch.dict(os.environ, {"EXPLORATION_MAIN_OUTPUT": str(historical)}):
            first = self.run_fake(source)
            second = self.run_fake(source)
            self.assertEqual(os.environ["EXPLORATION_MAIN_OUTPUT"], str(historical))
        self.assertTrue(first["passed"], first)
        self.assertTrue(second["passed"], second)
        self.assertNotEqual(first["evidence_dir"], second["evidence_dir"])
        self.assertNotEqual(first["environment"], second["environment"])
        for result in (first, second):
            self.assertEqual((Path(result["evidence_dir"]) / sentinel.name).read_text(), "new evidence")
            self.assertFalse(Path(result["environment"]["XDG_DATA_HOME"]).exists())
        self.assertEqual(sentinel.read_text(), "historical evidence")

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
