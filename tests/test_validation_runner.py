#!/usr/bin/env python3
"""Runner integration tests use real fake-engine processes, never game saves."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "tools/validate_parallel.py"
SPEC = importlib.util.spec_from_file_location("validation_runner", RUNNER_PATH)
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)

FAKE_ENGINE = r'''#!/usr/bin/env python3
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

args = sys.argv[1:]
if "--version" in args:
    name = "version"
elif "--editor" in args:
    name = "import"
elif "--script" in args:
    name = args[args.index("--script") + 1].removeprefix("res://")
elif "--quit-after" in args:
    name = "startup-300-frames"
else:
    name = "tests/reference_catalog_test.py"

def record(event, **extra):
    row = {"event": event, "name": name, "pid": os.getpid(), "time": time.monotonic(),
           "args": args, "cwd": os.getcwd(), "affinity": sorted(os.sched_getaffinity(0)),
           "home": os.environ.get("HOME"), "appdata": os.environ.get("APPDATA"),
           "xdg": {k: os.environ[k] for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")}, **extra}
    with open(os.environ["FAKE_TRACE"], "a") as out:
        fcntl.flock(out, fcntl.LOCK_EX)
        out.write(json.dumps(row) + "\n")
        out.flush()
        fcntl.flock(out, fcntl.LOCK_UN)

def selected(variable):
    return name in os.environ.get(variable, "").split(",")

record("start")
for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
    Path(os.environ[key], "same-name-save").write_text(name)
if name != "version":
    print("stdout: " + name, flush=True)
    print("stderr: " + name, file=sys.stderr, flush=True)
if selected("FAKE_CHILD"):
    child = subprocess.Popen([sys.executable, "-c",
        "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"])
    record("child", child_pid=child.pid)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
if selected("FAKE_HANG"):
    while True:
        time.sleep(0.1)
time.sleep(0 if name == "version" else float(os.environ.get("FAKE_DELAY", "0.015")))
if name == "version":
    print(os.environ.get("FAKE_VERSION", "4.6.3.fake"), flush=True)
if selected("FAKE_SCRIPT_ERROR"):
    print("SCRIPT ERROR: synthetic exception with successful exit", flush=True)
if selected("FAKE_ERROR"):
    print("\tERROR: synthetic import/runtime failure", file=sys.stderr, flush=True)
if selected("FAKE_NON_ERROR"):
    print("FILE_ERROR: an identifier, not the engine error prefix", flush=True)
if selected("FAKE_SIGNAL"):
    os.kill(os.getpid(), signal.SIGTERM)
record("end")
sys.exit(7 if selected("FAKE_FAIL") else 0)
'''


@unittest.skipUnless(sys.platform == "linux" and hasattr(os, "sched_getaffinity"), "Linux process/XDG tests")
class ValidationRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="validation-runner-tests-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "project"
        (self.project / "tools").mkdir(parents=True)
        (self.project / "tests").mkdir()
        (self.project / "tools/validate.sh").write_bytes((ROOT / "tools/validate.sh").read_bytes())
        (self.project / "project.godot").write_bytes((ROOT / "project.godot").read_bytes())
        for name in runner.SCRIPT_NAMES:
            (self.project / f"tests/{name}_test.gd").write_text("# fake engine fixture\n")
        (self.project / "tests/reference_catalog_test.py").write_text(FAKE_ENGINE)
        self.engine = self.base / "bin/fake-godot"
        self.engine.parent.mkdir()
        self.engine.write_text(FAKE_ENGINE)
        self.engine.chmod(0o755)
        self.trace = self.base / "trace.jsonl"
        self.logs = self.base / "logs"
        self.cpus = sorted(os.sched_getaffinity(0))[:2]
        if len(self.cpus) < 2:
            self.skipTest("Two allowed CPUs are required for the concurrency tests")

    def command(self, jobs=2, extra=()):
        return [sys.executable, str(RUNNER_PATH), "--project-dir", str(self.project),
                "--godot", str(self.engine), "--jobs", str(jobs),
                "--cpu-set", ",".join(map(str, self.cpus[:jobs])), "--log-dir", str(self.logs), *extra]

    def environment(self, overrides=None):
        env = os.environ.copy()
        env.update(FAKE_TRACE=str(self.trace))
        env.update(overrides or {})
        return env

    def events(self):
        import fcntl
        if not self.trace.exists():
            return []
        with self.trace.open() as source:
            fcntl.flock(source, fcntl.LOCK_SH)
            return [json.loads(line) for line in source]

    def run_fake(self, overrides=None, jobs=2, extra=()):
        completed = subprocess.run(self.command(jobs, extra), env=self.environment(overrides),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        reports = list(self.logs.glob("*/summary.json"))
        self.assertEqual(len(reports), 1, completed.stdout + completed.stderr)
        return completed, json.loads(reports[0].read_text()), reports[0].parent

    def assert_no_live_process(self, pid):
        status = Path(f"/proc/{pid}/stat")
        if status.exists():
            self.assertEqual(status.read_text().split(") ")[1].split()[0], "Z", f"Process {pid} still live")

    def test_parse_full_plan_order_and_absent_timeouts(self):
        plan = runner.parse_plan(self.project)
        source = (self.project / "tools/validate.sh").read_text().splitlines()
        self.assertEqual(len(plan.checks), 54)
        self.assertEqual(plan.checks[0].name, "import")
        self.assertEqual(plan.checks[-2].name, "tests/reference_catalog_test.py")
        self.assertEqual(plan.checks[-1].args, ("--quit-after", "300"))
        self.assertTrue(all(check.declared_timeout_seconds is None for check in plan.checks))
        self.assertEqual([check.source_line for check in plan.checks], list(range(35, 89)))
        self.assertTrue(all(source[check.source_line - 1].startswith(("run_check ", "python3 "))
                            for check in plan.checks))
        path = self.project / "tools/validate.sh"
        a, b = "run_check --script res://tests/build_test.gd", "run_check --script res://tests/equipment_catalog_test.gd"
        text = path.read_text().replace(a, "TEMP").replace(b, a).replace("TEMP", b)
        path.write_text(text)
        reordered = runner.parse_plan(self.project)
        self.assertEqual([check.name for check in reordered.checks[1:3]],
                         ["tests/equipment_catalog_test.gd", "tests/build_test.gd"])

    def test_reject_missing_duplicate_unknown_or_changed_shell_checks(self):
        path = self.project / "tools/validate.sh"
        original = path.read_text()
        command = "run_check --script res://tests/build_test.gd\n"
        variants = [original.replace(command, ""), original.replace(command, command * 2),
                    original.replace(command, "if true; then\n" + command + "fi\n"),
                    original.replace(command, command.rstrip() + " -- --samples=1\n"),
                    original.replace(command, "timeout 1 " + command),
                    original.replace('"$GODOT_BIN" --headless', 'timeout 1 "$GODOT_BIN" --headless'),
                    original.replace(command, "run_check --script res://tests/unknown_test.gd\n"),
                    original.replace('python3 "$PROJECT_DIR/tests/reference_catalog_test.py"\n', "")]
        for value in variants:
            with self.subTest(value=value[-180:]):
                path.write_text(value)
                with self.assertRaises(runner.PlanError):
                    runner.parse_plan(self.project)
        self.assertFalse(self.trace.exists())

    def test_missing_check_file_refuses_before_launch(self):
        (self.project / "tests/build_test.gd").unlink()
        completed = subprocess.run(self.command(), env=self.environment(), capture_output=True, text=True)
        self.assertEqual(completed.returncode, 2)
        self.assertIn("Missing check/resource", completed.stderr)
        self.assertFalse(self.trace.exists())
        self.assertFalse(self.logs.exists())

    def test_max_two_processes_serial_barriers_and_isolated_paths(self):
        completed, report, root = self.run_fake()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertTrue(report["complete"])
        self.assertEqual(report["failed_checks"], [])
        self.assertEqual(report["peak_check_processes"], 2)
        self.assertEqual(len(report["results"]), 54)
        self.assertTrue(all(row["status"] == "passed" for row in report["results"]))
        self.assertTrue(all(row["effective_timeout_seconds"] is None for row in report["results"]))
        self.assertEqual([row["started_seconds"] for row in report["results"]],
                         sorted(row["started_seconds"] for row in report["results"]))
        events = self.events()
        starts = {event["name"]: event for event in events if event["event"] == "start"}
        ends = {event["name"]: event for event in events if event["event"] == "end"}
        self.assertEqual(len(starts), 55)  # version preflight + all 54 checks
        live, peak = set(), 0
        serial = {row["name"] for row in report["results"] if row["serial_reason"]} | {"version"}
        for event in sorted(events, key=lambda item: item["time"]):
            if event["event"] == "start":
                if event["name"] in serial:
                    self.assertFalse(live)
                self.assertFalse(live & serial)
                live.add(event["name"])
                peak = max(peak, len(live))
            elif event["event"] == "end":
                live.remove(event["name"])
        self.assertEqual(peak, 2)
        self.assertFalse(live)
        self.assertLessEqual(ends["import"]["time"], min(event["time"] for name, event in starts.items()
                                                         if name not in ("import", "version")))
        seen = set()
        for event in starts.values():
            self.assertEqual(event["home"], os.environ.get("HOME"))
            self.assertEqual(event["appdata"], os.environ.get("APPDATA"))
            self.assertEqual(event["cwd"], str(self.project))
            self.assertEqual(len(event["affinity"]), 1)
            for path in event["xdg"].values():
                isolated = Path(path)
                self.assertTrue(isolated.is_absolute() and isolated.is_relative_to(root))
                self.assertNotIn(path, seen)
                seen.add(path)
                self.assertEqual((isolated / "same-name-save").read_text(), event["name"])
        for row in report["results"]:
            self.assertEqual(starts[row["name"]]["affinity"], [row["cpu"]])
            text = Path(row["log"]).read_text()
            self.assertIn("stdout: " + row["name"], text)
            self.assertIn("stderr: " + row["name"], text)
        self.assertGreater(report["wallclock_seconds"], 0)
        self.assertIn("cgroup_cpu_stat", report["cpu_after"])

    def test_one_worker_runs_complete_same_inventory(self):
        completed, report, _root = self.run_fake(jobs=1)
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(report["peak_check_processes"], 1)
        self.assertEqual(len(report["results"]), 54)

    def test_positive_exit_and_zero_exit_script_error_both_fail_without_omissions(self):
        completed, report, _root = self.run_fake({
            "FAKE_FAIL": "tests/build_test.gd", "FAKE_SCRIPT_ERROR": "tests/equipment_catalog_test.gd",
            "FAKE_ERROR": "tests/typed_affix_catalog_test.gd", "FAKE_NON_ERROR": "tests/defense_rules_test.gd"})
        self.assertEqual(completed.returncode, 7)
        self.assertTrue(report["complete"])
        self.assertEqual(len(report["results"]), 54)
        rows = {row["name"]: row for row in report["results"]}
        self.assertEqual(rows["tests/build_test.gd"]["raw_returncode"], 7)
        for name in ("tests/equipment_catalog_test.gd", "tests/typed_affix_catalog_test.gd"):
            self.assertEqual(rows[name]["raw_returncode"], 0)
            self.assertEqual(rows[name]["exit_code"], 1)
            self.assertTrue(rows[name]["error_log_match"])
        self.assertEqual(rows["tests/defense_rules_test.gd"]["status"], "passed")
        self.assertEqual(rows["startup-300-frames"]["status"], "passed")

    def test_python_exit_gate_does_not_invent_engine_log_errors(self):
        completed, report, _root = self.run_fake({"FAKE_SCRIPT_ERROR": "tests/reference_catalog_test.py"})
        self.assertEqual(completed.returncode, 0)
        self.assertFalse(report["results"][-2]["error_log_match"])

    def test_signal_exit_preserves_raw_returncode(self):
        completed, report, _root = self.run_fake({"FAKE_SIGNAL": "tests/build_test.gd"})
        self.assertEqual(completed.returncode, 143)
        self.assertEqual(report["results"][1]["raw_returncode"], -signal.SIGTERM)
        self.assertTrue(report["complete"])

    def test_success_also_cleans_up_surviving_helper(self):
        completed, report, _root = self.run_fake({"FAKE_CHILD": "tests/build_test.gd"})
        self.assertEqual(completed.returncode, 0)
        self.assertTrue(report["complete"])
        children = [e["child_pid"] for e in self.events() if e["event"] == "child"]
        self.assertEqual(len(children), 1)
        self.assert_no_live_process(children[0])

    def test_import_failure_blocks_every_dependent_check(self):
        completed, report, _root = self.run_fake({"FAKE_SCRIPT_ERROR": "import"})
        self.assertEqual(completed.returncode, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(report["results"][0]["status"], "failed")
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"][1:]))
        self.assertEqual([e["name"] for e in self.events() if e["event"] == "start"], ["version", "import"])

    def test_version_failure_blocks_import(self):
        completed, report, _root = self.run_fake({"FAKE_VERSION": "4.7.0.fake"})
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(report["version_preflight"]["status"], "failed")
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"]))
        self.assertEqual(len([e for e in self.events() if e["event"] == "start"]), 1)

    def test_timeout_kills_engine_and_descendants_but_continues_complete_plan(self):
        completed, report, _root = self.run_fake({"FAKE_HANG": "tests/build_test.gd",
            "FAKE_CHILD": "tests/build_test.gd"}, extra=("--timeout-seconds", "0.8"))
        self.assertEqual(completed.returncode, 124)
        row = report["results"][1]
        self.assertEqual(row["status"], "timed_out")
        self.assertEqual(row["raw_returncode"], -signal.SIGKILL)
        self.assertEqual(row["effective_timeout_seconds"], 0.8)
        self.assertTrue(all(r["declared_timeout_seconds"] is None for r in report["results"]))
        self.assertTrue(report["complete"])
        for event in self.events():
            self.assert_no_live_process(event["pid"])
            if event["event"] == "child":
                self.assert_no_live_process(event["child_pid"])

    def test_sigint_and_sigterm_cancel_no_more_dispatch_and_reap_groups(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum):
                self.trace.unlink(missing_ok=True)
                old_reports = set(self.logs.glob("*/summary.json"))
                env = self.environment({"FAKE_HANG": "tests/build_test.gd,tests/equipment_catalog_test.gd",
                                        "FAKE_CHILD": "tests/build_test.gd"})
                with (self.base / "cancel-output.log").open("w") as out:
                    process = subprocess.Popen(self.command(), env=env, stdout=out, stderr=out)
                    try:
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            events = self.events()
                            if len([e for e in events if e["event"] == "start"]) == 4 and any(
                                    e["event"] == "child" for e in events):
                                break
                            if process.poll() is not None:
                                self.fail((self.base / "cancel-output.log").read_text())
                            time.sleep(0.02)
                        else:
                            self.fail("fake engines did not reach the cancellable state")
                        process.send_signal(signum)
                        self.assertEqual(process.wait(timeout=10), 128 + signum)
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.wait()
                reports = set(self.logs.glob("*/summary.json")) - old_reports
                self.assertEqual(len(reports), 1)
                report = json.loads(reports.pop().read_text())
                self.assertFalse(report["complete"])
                self.assertEqual([r["status"] for r in report["results"][:3]], ["passed", "cancelled", "cancelled"])
                self.assertTrue(all(r["status"] == "not_run" for r in report["results"][3:]))
                self.assertEqual(len([e for e in self.events() if e["event"] == "start"]), 4)
                for event in self.events():
                    self.assert_no_live_process(event["pid"])
                    if event["event"] == "child":
                        self.assert_no_live_process(event["child_pid"])

    def test_platform_project_override_and_portable_engine_guards(self):
        with patch.object(sys, "platform", "win32"):
            with self.assertRaisesRegex(runner.PlanError, "Windows userdata isolation"):
                runner.audit_platform(self.project, str(self.engine), 2, None)
        with patch.object(sys, "platform", "darwin"):
            with self.assertRaises(runner.PlanError):
                runner.audit_platform(self.project, str(self.engine), 2, None)
        is_file = Path.is_file
        with patch.object(Path, "is_file", autospec=True, side_effect=lambda path:
                          False if path.name == "thread_siblings_list" else is_file(path)):
            with self.assertRaisesRegex(runner.PlanError, "CPU topology is unknown"):
                runner.audit_platform(self.project, str(self.engine), 2, None)
        override = self.project / "override.cfg"
        override.write_text("[application]\nconfig/use_custom_user_dir=true\n")
        with self.assertRaisesRegex(runner.PlanError, "override.cfg"):
            runner.audit_platform(self.project, str(self.engine), 2, None)
        override.unlink()
        marker = self.engine.parent / "._sc_"
        marker.touch()
        with self.assertRaisesRegex(runner.PlanError, "self-contained"):
            runner.audit_platform(self.project, str(self.engine), 2, None)
        marker.unlink()
        (self.project / "project.godot").write_text("[application]\nconfig/use_custom_user_dir=true\n")
        with self.assertRaisesRegex(runner.PlanError, "userdata settings"):
            runner.audit_platform(self.project, str(self.engine), 2, None)
        self.assertFalse(self.trace.exists())

    def test_invalid_limits_refuse_before_engine(self):
        for extra in (("--jobs", "3"), ("--cpu-set", f"{self.cpus[0]},{self.cpus[0]}"),
                      ("--timeout-seconds", "nan"), ("--timeout-seconds", "inf"), ("--timeout-seconds", "0")):
            with self.subTest(extra=extra):
                completed = subprocess.run(self.command(extra=extra), env=self.environment(),
                                           capture_output=True, text=True, timeout=10)
                self.assertEqual(completed.returncode, 2)
                self.assertFalse(self.trace.exists())
        self.assertFalse(self.logs.exists())


if __name__ == "__main__":
    unittest.main()
