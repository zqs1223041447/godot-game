#!/usr/bin/env python3
"""Pin the ten-script v64 SourceTree preload closure, without a project copy."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
COMMIT = subprocess.check_output(["git", "rev-parse", "23983fe^{commit}"], cwd=ROOT).decode().strip()
PREFIX = "res://docs/qa/v065-source/frozen/"
REFERENCE = re.compile(r'(?:preload|load)\("res://([^\"]+)"\)')
EXPECTED = {
    "scripts/items/item_location_rules.gd", "scripts/jewel_data.gd",
    "scripts/mechanics/mechanic_registry.gd", "scripts/mechanics/passive_balance_adapter.gd",
    "scripts/passive_data.gd", "scripts/passives/source_stat_patterns.gd",
    "scripts/passives/source_tree_allocation_rules.gd", "scripts/passives/source_tree_data.gd",
    "scripts/passives/source_tree_runtime.gd", "scripts/mechanics/iron_reflexes_rules.gd",
}


def original(path):
    return subprocess.check_output(["git", "show", f"{COMMIT}:{path}"], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


sources = {}
pending = ["scripts/passives/source_tree_runtime.gd"]
while pending:
    path = pending.pop()
    if path in sources:
        continue
    data = original(path)
    sources[path] = data
    pending.extend(REFERENCE.findall(data.decode()))
assert set(sources) == EXPECTED, "Review changed preload closure instead of copying the project"
manifest = {
    "source_commit": COMMIT,
    "source_version": "v64", "save_version": 40, "source_execution_policy": 40,
    "transformation": "Only remove class_name declarations and relocate every recursive preload/load into frozen/. No production script is loaded by the oracle. Shared unchanged JSON inputs are pinned separately.",
    "entries": [], "shared_inputs": [],
}
outputs = {}
for path, data in sorted(sources.items()):
    code = re.sub(r"^class_name .*\n", "", data.decode(), flags=re.MULTILINE)
    for dependency in sources:
        code = code.replace(f'"res://{dependency}"', f'"{PREFIX}{dependency}"')
    frozen = code.encode()
    outputs[OUT / "frozen" / path] = frozen
    manifest["entries"].append({"path": path, "source_sha256": sha(data), "frozen_sha256": sha(frozen)})
for path in ["data/passive_balance.json", "data/passives/official_tree_runtime.json"]:
    data = original(path)
    assert (ROOT / path).read_bytes() == data, f"Shared source changed: {path}"
    manifest["shared_inputs"].append({"path": path, "sha256": sha(data)})
manifest["source_bytes"] = sum(map(len, sources.values()))
outputs[OUT / "manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
verify = "--verify" in sys.argv
for path, data in outputs.items():
    if verify:
        assert path.read_bytes() == data, f"Frozen oracle differs from Git: {path}"
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
print(f"{'Verified' if verify else 'Frozen'} {len(sources)} scripts, {manifest['source_bytes']} bytes, from {COMMIT}")
