#!/usr/bin/env python3
"""Fail-closed, Linux-only execution of the audited v0.13 validate.sh plan."""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import BinaryIO


# These hashes cover the shell setup/function/version command and success banner,
# NOT the command list. Commands are parsed below and checked against the complete
# audited inventory. A new shell grammar or release needs an explicit new audit.
HEADER_SHA256 = "631c122fd5c6e0a43642e2b68430d2c77a51787e7d54521eb139954d74ca8ff8"
BANNER_SHA256 = "54098f00111150a66aa6836f22511923e976b63881a8893e840c6c8524f19475"
PROJECT_SHA256 = "cacdf0c5b157f767ab0e793f49eb7b1a19209f49ff37b2d3cb1a63123a77cd2f"
VERSION_COMMAND = 'echo "Godot version: $("$GODOT_BIN" --version)"'
SCRIPT_NAMES = tuple("""
build equipment_catalog typed_affix_catalog defense_rules defense_equipment_catalog
defense_equipment_state local_weapon_compiler local_weapon_catalog local_weapon_state
local_weapon_integration local_weapon_budget fire_defense_integration damage_base
damage_preview typed_damage_state typed_damage_integration save_guard_integration
progress_batch equipment_state equipment_integration skill_compiler skill_support_state
skill_support_integration skill_support_ui equipment_soak passive_jewel special_jewel
special_jewel_integration special_jewel_ui reference_export reference_launch
mechanic_registry passive_balance monster_system monster_integration combat_pipeline
spatial_collision projectile_schedule density_integration world_view fire_visual
combat_integration smoke visual_settings combat_cues combat_cues_integration
fantasy_actor equipment_art material_frame grimoire_ui equipment_painterly_art
""".split())
SERIAL_SCRIPTS = {
    "local_weapon_budget_test.gd": "complete budget replay / elapsed measurement",
    "equipment_soak_test.gd": "600 simulated seconds (36,000 ticks)",
    "spatial_collision_test.gd": "reference/indexed timing comparison",
    "projectile_schedule_test.gd": "reference/cached timing comparison",
}
ERROR_PATTERN = re.compile(rb"(^|\s)(SCRIPT ERROR:|ERROR:)")
POLL_SECONDS = 0.02
TERMINATE_GRACE_SECONDS = 0.3


class PlanError(ValueError):
    """Nothing is executed when the source or isolation cannot be audited."""


@dataclass(frozen=True)
class Check:
    index: int
    name: str
    kind: str
    args: tuple[str, ...]
    source_line: int
    serial_reason: str | None = None
    # The audited shell has no timeout. Do not confuse simulated time with one.
    declared_timeout_seconds: float | None = None


@dataclass(frozen=True)
class Plan:
    source_sha256: str
    checks: tuple[Check, ...]


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def project_file(project: Path, relative: str) -> Path:
    candidate = project / relative
    if not candidate.is_file() or not candidate.resolve().is_relative_to(project):
        raise PlanError(f"Missing check/resource or path outside project: {relative}")
    return candidate


def parse_plan(project: Path) -> Plan:
    """Parse every executable check; never source/eval or regex-extract a subset."""
    project = project.resolve()
    source = project_file(project, "tools/validate.sh").read_bytes()
    try:
        lines = source.decode("utf-8").splitlines(keepends=True)
    except UnicodeError as exc:
        raise PlanError("validate.sh must be the audited UTF-8 shell source") from exc
    markers = [i for i, line in enumerate(lines) if line == VERSION_COMMAND + "\n"]
    if len(markers) != 1:
        raise PlanError("Unknown validate.sh version/preflight structure")
    boundary = markers[0] + 1
    if (digest("".join(lines[:boundary]).encode()) != HEADER_SHA256
            or digest(lines[-1].encode()) != BANNER_SHA256):
        raise PlanError("Unknown validate.sh setup, run_check, timeout or banner structure")

    checks = []
    for line_number, line in enumerate(lines[boundary:-1], boundary + 1):
        command = line.removesuffix("\n")
        reason = None
        if command == "run_check --editor --import":
            name, kind, args = "import", "godot", ("--editor", "--import")
            reason = "import must finish before all other checks"
        elif match := re.fullmatch(r"run_check --script res://(tests/[a-z0-9_]+_test\.gd)", command):
            relative = match[1]
            path = project_file(project, relative)
            name, kind, args = relative, "godot", ("--script", "res://" + relative)
            reason = SERIAL_SCRIPTS.get(path.name)
            # Conservatively serialize a newly introduced direct timing measurement
            # even when the inventory/name has not changed.
            if "Time.get_ticks_" in path.read_text(encoding="utf-8"):
                reason = reason or "script measures elapsed time"
        elif command == 'python3 "$PROJECT_DIR/tests/reference_catalog_test.py"':
            name, kind, args = "tests/reference_catalog_test.py", "python", ()
            project_file(project, name)
        elif command == "run_check --quit-after 300":
            name, kind, args = "startup-300-frames", "godot", ("--quit-after", "300")
            reason = "complete 300-frame startup"
        else:
            raise PlanError(f"Unknown executable structure at validate.sh:{line_number}: {command}")
        checks.append(Check(len(checks) + 1, name, kind, args, line_number, reason))

    expected = Counter(["import", "tests/reference_catalog_test.py", "startup-300-frames"]
                       + [f"tests/{name}_test.gd" for name in SCRIPT_NAMES])
    actual = Counter(check.name for check in checks)
    if actual != expected:
        raise PlanError(f"Incomplete/changed v0.13 inventory; missing={list((expected - actual).elements())}; "
                        f"extra={list((actual - expected).elements())}")
    if checks[0].name != "import" or checks[-1].name != "startup-300-frames":
        raise PlanError("Import must be first and complete startup must be last")
    return Plan(digest(source), tuple(checks))


def audit_platform(project: Path, engine: str, jobs: int, cpu_set: str | None) -> tuple[str, tuple[int, ...]]:
    if sys.platform != "linux":
        raise PlanError("Execution requires audited Linux XDG isolation. Windows userdata isolation "
                        "has not been audited; refusing before any engine process. Do not change HOME/APPDATA.")
    if jobs not in (1, 2):
        raise PlanError("Only one or two concurrent check processes are supported")
    if digest(project_file(project, "project.godot").read_bytes()) != PROJECT_SHA256:
        raise PlanError("project.godot differs from audited v0.13 userdata settings")
    if (project / "override.cfg").exists():
        raise PlanError("Unaudited override.cfg could bypass XDG userdata isolation")
    resolved = shutil.which(engine)
    if not resolved:
        raise PlanError(f"Godot executable not found: {engine}")
    engine_path = Path(resolved).resolve()
    for directory in {Path(resolved).absolute().parent, engine_path.parent}:
        if any((directory / marker).exists() for marker in ("._sc_", "_sc_")):
            raise PlanError("Godot self-contained mode bypasses the audited XDG paths")
    allowed = sorted(os.sched_getaffinity(0))
    try:
        cpus = tuple(int(value) for value in cpu_set.split(",")) if cpu_set else tuple(allowed[:jobs])
    except ValueError as exc:
        raise PlanError("--cpu-set must be comma-separated CPU integers") from exc
    if len(cpus) != jobs or len(set(cpus)) != jobs or not set(cpus).issubset(allowed):
        raise PlanError(f"Choose exactly {jobs} distinct allowed CPUs from {allowed}")
    if jobs == 2:
        sibling_file = Path(f"/sys/devices/system/cpu/cpu{cpus[0]}/topology/thread_siblings_list")
        if not sibling_file.is_file():
            raise PlanError("CPU topology is unknown; refusing two workers without an SMT audit")
        siblings = set()
        for part in sibling_file.read_text().strip().split(","):
            ends = [int(value) for value in part.split("-")]
            siblings.update(range(ends[0], ends[-1] + 1))
        if cpus[1] in siblings:
            raise PlanError("Worker CPUs share an SMT core; choose separate cores for timing isolation")
    return str(engine_path), cpus


def cpu_snapshot(cpus: tuple[int, ...]) -> dict:
    def read(path: str) -> str | None:
        try:
            return Path(path).read_text().strip()
        except OSError:
            return None
    stat = read("/proc/stat") or ""
    return {
        "loadavg": list(os.getloadavg()),
        "cgroup_cpu_max": read("/sys/fs/cgroup/cpu.max"),
        "cgroup_cpu_stat": read("/sys/fs/cgroup/cpu.stat"),
        "cpu_ticks_user_nice_system_idle_iowait_irq_softirq_steal": {
            line.split()[0]: [int(value) for value in line.split()[1:]]
            for line in stat.splitlines() if line.split()[0] in {f"cpu{cpu}" for cpu in cpus}
        },
        "thread_siblings": {str(cpu): read(f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list")
                            for cpu in cpus},
    }


@dataclass
class Active:
    check: Check
    process: subprocess.Popen
    log: BinaryIO
    result: dict
    started: float
    stop_reason: str | None = None
    stop_at: float | None = None


def signal_group(process: subprocess.Popen, value: int) -> None:
    try:
        os.killpg(process.pid, value)
    except ProcessLookupError:
        pass


class Runner:
    def __init__(self, project: Path, plan: Plan, engine: str, cpus: tuple[int, ...],
                 log_root: Path, timeout_seconds: float | None = None):
        if timeout_seconds is not None and (not math.isfinite(timeout_seconds) or timeout_seconds <= 0):
            raise PlanError("An optional timeout must be positive and finite")
        self.project, self.plan, self.engine, self.cpus = project, plan, engine, cpus
        self.root, self.timeout = log_root, timeout_seconds
        self.cancel_signal = None
        self.started = time.monotonic()
        self.results: dict[int, dict] = {}
        self.probe = None
        self.peak = 0

    def cancel(self, signum: int, _frame=None) -> None:
        self.cancel_signal = self.cancel_signal or signum

    def launch(self, check: Check, slot: int) -> Active | None:
        label = f"{check.index:02d}-{Path(check.name).stem}"
        directory = self.root / label
        directory.mkdir()
        environment = os.environ.copy()
        paths = {f"XDG_{kind.upper()}_HOME": str(directory / kind) for kind in ("data", "config", "cache")}
        for path in paths.values():
            Path(path).mkdir()
        (directory / "cache/fontconfig").mkdir()
        environment.update(paths)
        # Preserve HOME, APPDATA and all caller globals. Only child XDG changes.
        if check.kind == "python":
            command = [sys.executable, str(self.project / check.name)]
        elif check.kind == "version":
            command = [self.engine, "--version"]
        else:
            command = [self.engine, "--headless", "--path", str(self.project), *check.args]
        cpu = self.cpus[slot]
        result = {**asdict(check), "command": command, "cpu": cpu, "xdg": paths,
                  "log": str(directory / "check.log"), "status": "running", "raw_returncode": None,
                  "exit_code": None, "error_log_match": False,
                  "started_seconds": time.monotonic() - self.started,
                  "effective_timeout_seconds": self.timeout}
        self.results[check.index] = result
        log = (directory / "check.log").open("wb")
        print(f"[{check.index:02d}/{len(self.plan.checks)}] start {check.name} CPU {cpu}", flush=True)
        try:
            # The scheduler has no threads; preexec affinity applies to all engine
            # threads/descendants. Each engine gets its own killable POSIX session.
            process = subprocess.Popen(command, cwd=self.project, env=environment, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
                                       preexec_fn=lambda: os.sched_setaffinity(0, {cpu}))
        except (OSError, subprocess.SubprocessError) as exc:
            log.write(str(exc).encode("utf-8", errors="replace"))
            log.close()
            result.update(status="spawn_failed", exit_code=127, elapsed_seconds=0.0,
                          ended_seconds=time.monotonic() - self.started)
            return None
        return Active(check, process, log, result, time.monotonic())

    def finish(self, active: Active) -> None:
        raw = active.process.wait()
        # Do not leave helpers alive after the engine exits, including on success.
        signal_group(active.process, signal.SIGKILL)
        active.log.close()
        error_match = False
        if active.check.kind != "python":
            with Path(active.result["log"]).open("rb") as log:
                error_match = any(ERROR_PATTERN.search(line) for line in log)
        effective = raw if raw >= 0 else 128 - raw
        status = "passed" if raw == 0 and not error_match else "failed"
        if error_match and effective == 0:
            effective = 1
        if active.stop_reason:
            status = active.stop_reason
            effective = 124 if status == "timed_out" else 128 + self.cancel_signal
        active.result.update(status=status, raw_returncode=raw, exit_code=effective, error_log_match=error_match,
                             elapsed_seconds=time.monotonic() - active.started,
                             ended_seconds=time.monotonic() - self.started)
        print(f"[{active.check.index:02d}/{len(self.plan.checks)}] {status} {active.check.name} "
              f"exit={effective} raw={raw}", flush=True)

    def schedule(self, checks: tuple[Check, ...]) -> None:
        cursor = 0
        running: dict[int, Active] = {}
        try:
            while cursor < len(checks) or running:
                now = time.monotonic()
                for slot, active in list(running.items()):
                    if self.cancel_signal and not active.stop_reason:
                        active.stop_reason, active.stop_at = "cancelled", now
                        signal_group(active.process, signal.SIGTERM)
                    elif (self.timeout is not None and now - active.started >= self.timeout
                          and not active.stop_reason and active.process.poll() is None):
                        active.stop_reason, active.stop_at = "timed_out", now
                        signal_group(active.process, signal.SIGTERM)
                    if active.stop_at is not None and now - active.stop_at >= TERMINATE_GRACE_SECONDS:
                        signal_group(active.process, signal.SIGKILL)
                    if active.process.poll() is not None:
                        self.finish(active)
                        del running[slot]
                if self.cancel_signal and not running:
                    break
                if (self.results.get(1, {}).get("name") == "import"
                        and self.results[1]["status"] not in ("running", "passed")):
                    break
                while cursor < len(checks) and len(running) < len(self.cpus) and not self.cancel_signal:
                    check = checks[cursor]
                    # Serial checks are barriers on BOTH sides, at their original
                    # position. Import and timing cannot overlap even short checks.
                    if running and (check.serial_reason or any(a.check.serial_reason for a in running.values())):
                        break
                    slot = 0 if check.serial_reason else next(i for i in range(len(self.cpus)) if i not in running)
                    active = self.launch(check, slot)
                    cursor += 1
                    if active:
                        running[slot] = active
                        self.peak = max(self.peak, len(running))
                    if check.serial_reason:
                        break
                if running:
                    time.sleep(POLL_SECONDS)
        finally:
            # Unexpected Python exceptions must also leave no owned engine group.
            for active in running.values():
                signal_group(active.process, signal.SIGKILL)
                active.process.wait()
                active.log.close()

    def run(self) -> dict:
        before = cpu_snapshot(self.cpus)
        old_handlers = {s: signal.signal(s, self.cancel) for s in (signal.SIGINT, signal.SIGTERM)}
        try:
            version = Check(0, "version", "version", ("--version",), 34, "isolated version preflight")
            self.schedule((version,))
            self.probe = self.results.pop(0, None)
            if self.probe and self.probe["status"] == "passed" and not self.cancel_signal:
                version_text = Path(self.probe["log"]).read_text(errors="replace").strip()
                print(f"Godot version: {version_text}", flush=True)
                if version_text.startswith("4.6.3."):
                    self.schedule(self.plan.checks)
                else:
                    self.probe.update(status="failed", exit_code=1, reason="Only audited Godot 4.6.3 is supported")
            blocked_reason = ("cancelled" if self.cancel_signal else "import or version preflight failed")
            for check in self.plan.checks:
                if check.index not in self.results:
                    self.results[check.index] = {**asdict(check), "status": "not_run", "reason": blocked_reason,
                                                 "raw_returncode": None, "exit_code": None}
        finally:
            for signum, handler in old_handlers.items():
                signal.signal(signum, handler)
        ordered = [self.results[check.index] for check in self.plan.checks]
        failures = [row["name"] for row in ordered if row["status"] != "passed"]
        failed_probe = self.probe and self.probe["status"] != "passed"
        first_error = next((row["exit_code"] for row in ordered if row["exit_code"]), 1)
        exit_code = (128 + self.cancel_signal if self.cancel_signal else
                     self.probe["exit_code"] if failed_probe else first_error if failures else 0)
        report = {
            "source_sha256": self.plan.source_sha256, "project": str(self.project),
            "jobs": len(self.cpus), "worker_cpus": list(self.cpus), "peak_check_processes": self.peak,
            "timeout_override_seconds": self.timeout, "wallclock_seconds": time.monotonic() - self.started,
            "cpu_before": before, "cpu_after": cpu_snapshot(self.cpus),
            "cpu_isolation": "one distinct non-SMT CPU per check; serial barriers use first CPU; "
                             "affinity does not reserve host CPUs or eliminate VM/cgroup interference",
            "version_preflight": self.probe, "results": ordered, "failed_checks": failures,
            "complete": all(row["status"] != "not_run" for row in ordered), "exit_code": exit_code,
        }
        (self.root / "summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-dir", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--jobs", type=int, choices=(1, 2), default=2)
    parser.add_argument("--cpu-set", help="exactly one distinct non-SMT CPU per worker, e.g. 0,1")
    parser.add_argument("--timeout-seconds", type=float, help="explicit per-process timeout override; default: none")
    parser.add_argument("--log-dir", type=Path, help="parent of a unique retained run directory (default: system temp)")
    parser.add_argument("--print-plan", action="store_true", help="audit and print the entire plan without execution")
    args = parser.parse_args(argv)
    try:
        project = args.project_dir.resolve()
        plan = parse_plan(project)
        if args.print_plan:
            print(json.dumps(asdict(plan), ensure_ascii=False, indent=2))
            return 0
        engine, cpus = audit_platform(project, args.godot, args.jobs, args.cpu_set)
        if args.timeout_seconds is not None and (not math.isfinite(args.timeout_seconds) or args.timeout_seconds <= 0):
            raise PlanError("An optional timeout must be positive and finite")
        if args.log_dir:
            args.log_dir.mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix="validate-parallel-", dir=args.log_dir)).resolve()
        print(f"Retained logs and isolated userdata: {root}", flush=True)
        report = Runner(project, plan, engine, cpus, root, args.timeout_seconds).run()
        print(f"Wallclock: {report['wallclock_seconds']:.3f}s; "
              f"{len(report['results']) - len(report['failed_checks'])}/{len(plan.checks)} passed; "
              f"summary: {root / 'summary.json'}", flush=True)
        if report["failed_checks"]:
            print("Failed/not run: " + ", ".join(report["failed_checks"]), file=sys.stderr)
        return report["exit_code"]
    except (PlanError, OSError) as exc:
        print(f"Validation refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
