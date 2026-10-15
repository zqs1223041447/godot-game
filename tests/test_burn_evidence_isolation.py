#!/usr/bin/env python3
"""Run serial Godot checks with retained /tmp output; never import or clean assets."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HISTORICAL = ROOT / "docs/qa/v063-settlement-rules"


def snapshots():
    return {
        str(path.relative_to(HISTORICAL)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in HISTORICAL.rglob("*")
        if path.is_file() and not path.name.endswith((".uid", ".import"))
    }


class BurnEvidenceIsolation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get("GODOT_BIN") or shutil.which("godot")
        if not cls.engine:
            raise RuntimeError("Godot required; set GODOT_BIN")
        cls.work = Path(tempfile.mkdtemp(prefix="godot-m1-v063-evidence-test-"))
        cls.original = snapshots()
        print(f"Retained test evidence: {cls.work}", flush=True)
        cls.serial = 0

    @classmethod
    def tearDownClass(cls):
        if snapshots() != cls.original:
            raise AssertionError("Historical evidence or frozen oracle changed")

    def run_engine(self, destination=None, success=False):
        type(self).serial += 1
        env = os.environ.copy()
        env.pop("BURN_EVIDENCE_DIR", None)
        for key, directory in (
            ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
            ("XDG_CACHE_HOME", "cache"),
        ):
            env[key] = str(self.work / directory)
        if destination is not None:
            env["BURN_EVIDENCE_DIR"] = str(destination)
        result = subprocess.run(
            [self.engine, "--headless", "--path", str(ROOT),
             "--script", "res://tests/burn_settlement_equivalence_test.gd"],
            env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=90, check=False,
        )
        (self.work / f"run-{self.serial:02}.log").write_text(result.stdout)
        self.assertNotIn("SCRIPT ERROR:", result.stdout, result.stdout)
        self.assertEqual(snapshots(), self.original)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("ERROR:", result.stdout)
            paths = [
                line.removeprefix("BURN_EVIDENCE_REPORT ")
                for line in result.stdout.splitlines()
                if line.startswith("BURN_EVIDENCE_REPORT ")
            ]
            self.assertEqual(len(paths), 1, result.stdout)
            report_path = Path(paths[0])
            report = json.loads(report_path.read_text())
            self.assertEqual(report["checks"], 58593)
            self.assertEqual(report["failures"], 0)
            self.assertTrue(report_path.is_relative_to("/tmp"))
            return report_path
        self.assertEqual(result.returncode, 73, result.stdout)
        self.assertIn("BURN_EVIDENCE_ERROR:", result.stdout)
        self.assertNotIn("BURN_SETTLEMENT_EQUIVALENCE ", result.stdout)
        return None

    def test_default_fresh_report(self):
        self.run_engine(success=True)

    def test_explicit_fresh_report_then_duplicate_refused(self):
        destination = self.work / "explicit"
        report = self.run_engine(destination, success=True)
        self.assertEqual(report, destination / "results.json")
        saved = report.read_bytes()
        self.run_engine(destination)
        self.assertEqual(report.read_bytes(), saved)

    def test_missing_parent_refused(self):
        destination = self.work / "missing-parent" / "report"
        self.run_engine(destination)
        self.assertFalse(destination.parent.exists())

    def test_invalid_and_historical_destinations_refused(self):
        for destination in (
            "res://docs/qa/v063-settlement-rules", HISTORICAL,
            "relative-report", self.work / ".." / "unsafe-report",
        ):
            with self.subTest(destination=str(destination)):
                self.run_engine(destination)

    def test_file_and_symlink_destinations_refused(self):
        occupied = self.work / "occupied"
        occupied.write_text("preserve this")
        self.run_engine(occupied)
        self.assertEqual(occupied.read_text(), "preserve this")
        link = self.work / "linked-repository"
        link.symlink_to(ROOT, target_is_directory=True)
        self.run_engine(link / "new-report")
        self.assertFalse((ROOT / "new-report").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
