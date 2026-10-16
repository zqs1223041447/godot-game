#!/usr/bin/env python3
"""Sequential, isolated transaction and startup recovery acceptance. Standard library only; Linux /tmp."""
import argparse
from dataclasses import dataclass, field
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Case:
    name: str
    script: str
    marker: str
    expected_checks: int
    prefix: str = "godot-m1-transactions-"
    env: dict = field(default_factory=dict)
    json_summary: bool = False
    burn_evidence: bool = False
    user_args: tuple = ()


def cases(mode="quick"):
    result = [
        Case("atomic", "skill_transaction_atomicity", "skill_transaction_atomicity:", 108),
        Case("ui_feedback", "canonical_ui_feedback_recovery", "CANONICAL_UI_FEEDBACK_RECOVERY ", 19, "godot-ui-feedback.", json_summary=True),
        Case("group_cast", "canonical_group_cast", "Canonical group cast:", 35),
        Case("support_ui", "skill_support_ui", "Skill support UI:", 368),
        Case("picker", "owned_gem_picker", "OWNED_GEM_PICKER ", 39, "godot-owned-gem-picker-", json_summary=True),
        Case("store", "canonical_build_store", "Canonical build store:", 40),
        Case("catalog", "gem_catalog", "Gem catalog: 10 skills, 24 supports;", 598),
        Case("binding", "skill_binding_keys", "SKILL_BINDING_KEYS ", 57, "godot-skill-binding-", json_summary=True),
    ]
    return_counts = {"first_clear": 22, "second_clear": 22, "second_retry": 17,
                     "second_kill": 18, "second_reload": 16, "control": 18}
    combinations = [(f, m) for f in ("free", "paid", "affixed") for m in return_counts]
    if mode == "quick":
        combinations = [("free", "second_clear"), ("paid", "second_retry"), ("affixed", "control")]
    for fixture, action in combinations:
        result.append(Case("return_" + fixture + "_" + action, "return_transaction_failure",
                           "RETURN_RESULT " + fixture + "/" + action + " ",
                           return_counts[action] + (0 if fixture == "free" else 4),
                           env={"RETURN_FIXTURE": fixture, "RETURN_CASE": action}))
    pairs = [(u, f) for u in (0, 1) for f in range(5)] if mode == "full" else [(0, 1), (1, 2)]
    for unbound, fault in pairs:
        result.append(Case(f"f6_{unbound}_{fault}", "tornado_example_failure",
                           f"TORNADO_RESULT unbound={'true' if unbound else 'false'} fail={fault} ",
                           (14 if fault == 0 else 17 if fault == 1 else 16) + unbound,
                           env={"TORNADO_UNBOUND": str(unbound), "TORNADO_FAIL": str(fault)}))
    if mode == "full":
        result.append(Case("safe_exit", "safe_map_exit", "SAFE_MAP_EXIT ", 120, "godot-m1-v099-"))
    startup_counts = {"start": 27, "leave": 26, "test": 26,
                      "completed_start": 25, "completed_leave": 24, "completed_test": 24}
    startup_actions = startup_counts if mode == "full" else ("start", "completed_test")
    for action in startup_actions:
        result.append(Case("startup_" + action, "startup_recovery_failure",
                           "STARTUP_RECOVERY " + action + " ", startup_counts[action],
                           "godot-startup-recovery.", env={"STARTUP_CASE": action}))
    if mode == "full":
        result.extend([
            Case("current_help_contract", "current_help_contract", "Current Help contract:", 165),
            Case("encounter_ui_integration", "encounter_ui_integration", "Encounter UI integration:", 88),
            Case("encounter_controls", "encounter_controls", "Encounter controls:", 3918),
            Case("pause_keyboard_scroll", "pause_keyboard_scroll", "Pause keyboard scroll:", 1070),
            Case("settings_keyboard_scroll", "settings_keyboard_scroll", "Settings keyboard scroll:", 1025),
            Case("skill_binding_focus_capacity10", "skill_binding_focus", "Skill binding focus:",
                 3303, "godot-skill-focus-"),
            Case("skill_binding_focus_capacity11", "skill_binding_focus", "Skill binding focus:",
                 3629, "godot-skill-focus-", user_args=("--capacity11",)),
            Case("talent_details_focus", "talent_details_focus", "Talent details focus:",
                 5219, "godot-talent-focus-"),
            Case("burn_state_copy", "burn_state_copy_20261015", "Burn state copy equivalence:",
                 892, "godot-m1-v050-"),
            Case("burn_settlement_equivalence", "burn_settlement_equivalence",
                 "BURN_SETTLEMENT_EQUIVALENCE ", 58593, "godot-m1-v063-",
                 json_summary=True, burn_evidence=True),
        ])
    return result


def parse_summary(case, output):
    lines = [line for line in output.splitlines() if line.startswith(case.marker)]
    if len(lines) != 1:
        raise ValueError("expected exactly one suite summary")
    tail = lines[0][len(case.marker):]
    if case.json_summary:
        data = json.loads(tail)
        checks, failures = data["checks"], data["failures"]
        if isinstance(failures, list):
            failures = len(failures)
    else:
        match = re.fullmatch(r"(\d+) checks, (\d+) failures|checks=(\d+) failures=(\d+)", tail.strip())
        if not match:
            raise ValueError("malformed suite summary")
        checks, failures = map(int, match.group(1, 2) if match.group(1) else match.group(3, 4))
    if type(checks) is not int or type(failures) is not int or checks < 1 or failures < 0:
        raise ValueError("invalid assertion counts")
    return checks, failures


def run_case(case, godot, project, output_dir, timeout=90):
    if not math.isfinite(timeout) or not 0 < timeout <= 90:
        raise ValueError("timeout must be > 0 and <= 90 seconds")
    log_path = output_dir / (case.name + ".log")
    start = time.monotonic()
    record = {"name": case.name, "expected_checks": case.expected_checks, "checks": 0,
              "failures": None, "passed": False, "returncode": None, "log": str(log_path)}
    with tempfile.TemporaryDirectory(prefix=case.prefix, dir="/tmp") as directory:
        base = Path(directory)
        env = os.environ.copy()
        # Never inherit scenario switches or artifact destinations from another run.
        for key in ("RETURN_CASE", "RETURN_FIXTURE", "TORNADO_UNBOUND", "TORNADO_FAIL",
                    "STARTUP_CASE", "STARTUP_RED_CONTROL", "BURN_EVIDENCE_DIR",
                    "BINDING_BASELINE_ONLY", "BINDING_REPORT", "BINDING_CAPTURE_DIR",
                    "GEM_PICKER_REPORT", "GEM_PICKER_CAPTURE_DIR", "SAFE_EXIT_GROUP", "SAFE_EXIT_OUTPUT"):
            env.pop(key, None)
        for key, relative in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            path = base / relative
            path.mkdir()
            env[key] = str(path)
        (base / "cache/fontconfig").mkdir()
        env.update(case.env)
        env["BINDING_REPORT"] = str(output_dir / (case.name + "-binding.json"))
        env["GEM_PICKER_REPORT"] = str(output_dir / (case.name + "-picker.json"))
        env["SAFE_EXIT_OUTPUT"] = str(output_dir / (case.name + "-safe-exit.json"))
        if case.burn_evidence:
            # The suite atomically reserves this fresh destination; never mkdir here.
            # Keep reports beside logs, outside the disposable XDG tree.
            env["BURN_EVIDENCE_DIR"] = str(output_dir / (case.name + "-evidence"))
            record["evidence_dir"] = env["BURN_EVIDENCE_DIR"]
        command = [godot, "--headless", "--path", str(project), "--script", f"tests/{case.script}_test.gd"]
        if case.user_args:
            command.extend(["--", *case.user_args])
        record.update(command=command, environment={key: env[key] for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")}, scenario=case.env)
        with log_path.open("wb") as log:
            try:
                process = subprocess.Popen(command, cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    record["returncode"] = process.wait(timeout=timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    if isinstance(error, KeyboardInterrupt):
                        raise
                    record["reason"] = "timeout"
            except OSError as error:
                record["reason"] = "launch_error: " + str(error)
        output = log_path.read_text(errors="replace")
        record["warnings"] = [line for line in output.splitlines() if re.search(r"\bWARNING\b", line)]
        if record["returncode"] != 0:
            record.setdefault("reason", "guard_rejected" if record["returncode"] == 78 else "nonzero_exit")
        try:
            record["checks"], record["failures"] = parse_summary(case, output)
        except (ValueError, KeyError, TypeError) as error:
            record.setdefault("reason", "summary_error: " + str(error))
        if re.search(r"\b(?:SCRIPT ERROR|ERROR)\b", output):
            record.setdefault("reason", "engine_error")
        if record["checks"] != case.expected_checks or record["failures"] != 0:
            record.setdefault("reason", "assertion_count_or_failure_mismatch")
        record["passed"] = "reason" not in record
    record["seconds"] = round(time.monotonic() - start, 3)
    return record


def report(results, mode):
    return {"mode": mode, "cases": len(results), "passed": sum(r["passed"] for r in results),
            "failed": sum(not r["passed"] for r in results),
            "observed_checks": sum(r["checks"] for r in results),
            "accepted_checks": sum(r["checks"] for r in results if r["passed"]), "results": results}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("quick", "full"), default="quick")
    parser.add_argument("--godot", default="godot", help="executable path/name, not a shell command")
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--list", action="store_true", help="list cases without launching Godot")
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 90:
        parser.error("--timeout must be > 0 and <= 90 seconds")
    selected = cases(args.mode)
    if args.list:
        print(json.dumps([c.__dict__ for c in selected], indent=2))
        return 0
    # Retained evidence uses a fresh directory; never overwrite or delete user paths.
    output_dir = Path(tempfile.mkdtemp(prefix="transaction-regressions-", dir="/tmp"))
    print(f"Evidence: {output_dir}", flush=True)
    results = []
    for case in selected:
        result = run_case(case, args.godot, ROOT, output_dir, args.timeout)
        results.append(result)
        (output_dir / "report.json").write_text(json.dumps(report(results, args.mode), indent=2) + "\n")
        print(f"{case.name}: {'PASS' if result['passed'] else 'FAIL'} ({result['checks']} checks)", flush=True)
    print(json.dumps(report(results, args.mode), indent=2))
    return 1 if any(not r["passed"] for r in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
