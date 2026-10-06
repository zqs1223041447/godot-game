#!/usr/bin/env python3
"""Freeze or verify the complete v62 defense preload closure from Git objects."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
COMMIT = "b93018005413444ad6f988974f4ef3ea09902c5e"
PREFIX = "res://docs/qa/v063-settlement-rules/frozen/"
REFERENCE = re.compile(r'(?:preload|load)\("res://([^\"]+)"\)')


def sha(data):
    return hashlib.sha256(data).hexdigest()


sources = {}
pending = ["scripts/mechanics/defense_rules.gd"]
while pending:
    path = pending.pop()
    if path in sources:
        continue
    data = subprocess.check_output(["git", "show", f"{COMMIT}:{path}"], cwd=ROOT)
    sources[path] = data
    pending.extend(REFERENCE.findall(data.decode()))

assert set(sources) == {
    "scripts/mechanics/defense_rules.gd", "scripts/combat/damage_resolver.gd"
}, "Review an unexpected dependency instead of silently broadening the oracle"

manifest = {
    "source_commit": COMMIT,
    "transformation": "Exact source bytes retained in source/*.gd.txt. Frozen copies only remove class_name lines and relocate every recursive preload/load reference; no production implementation is loaded.",
    "entries": [],
}
expected = {}
for path, data in sorted(sources.items()):
    code = re.sub(r"^class_name .*\n", "", data.decode(), flags=re.MULTILINE)
    for dependency in sources:
        code = code.replace(f'"res://{dependency}"', f'"{PREFIX}{dependency}"')
    frozen = code.encode()
    expected[OUT / "source" / (path + ".txt")] = data
    expected[OUT / "frozen" / path] = frozen
    manifest["entries"].append({
        "path": path, "source_sha256": sha(data), "frozen_sha256": sha(frozen)
    })
expected[OUT / "manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()

verify = "--verify" in sys.argv
for path, data in expected.items():
    if verify:
        assert path.read_bytes() == data, f"Oracle differs from pinned Git object: {path}"
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
print(f"{'Verified' if verify else 'Frozen'} {len(sources)} scripts from {COMMIT}")
for entry in manifest["entries"]:
    print(entry["path"], entry["source_sha256"], entry["frozen_sha256"])
