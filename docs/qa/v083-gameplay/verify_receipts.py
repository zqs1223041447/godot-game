#!/usr/bin/env python3
"""Read-only checks of the one actual-Main run; never launches Godot."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
checks: list[dict] = []


def require(value: bool, label: str) -> None:
    checks.append({"passed":bool(value),"label":label})


def read(name: str) -> dict:
    return json.loads((RESULTS/name).read_text())


receipt = read("execution.json")
report = read("main-result.json")
log = (RESULTS/"main.log").read_text()
require(receipt["exit_code"] == 0, "Actual Main process succeeded")
require(receipt["editor_import"] is False and receipt["native_window"] is False, "No worker import or GUI")
require(receipt["xdg_data_home"].startswith("/tmp/godot-m1-v083-ginkgo-"), "Dedicated independent save directory")
require(receipt["entry_sha256"] == hashlib.sha256((ROOT/"tests/ginkgo_map_gameplay_test.gd").read_bytes()).hexdigest(), "Executed test still matches current source")
require("SCRIPT ERROR:" not in log and "ERROR:" not in log, "No Godot parse/runtime/test errors")
summary = re.search(r"GINKGO_MAP_GAMEPLAY checks=(\d+) failures=(\d+) completed_runs=(\d+)",log)
require(summary is not None, "Final complete test summary exists")
require(report["failures"] == 0, "Raw Main report has zero failures")
require(len(report["runs"]) == 2, "Exactly two complete formal battle fixtures")
if summary:
    require(int(summary[1]) == report["checks"] + 1, "Final successful report-file-open check accounts for one extra logged check")
    require(int(summary[2]) == 0 and int(summary[3]) == 2, "Log confirms zero failures and two complete runs")

for tier in (1,2):
    row = report["runs"][tier-1]
    profile = row["profile"]
    attack = report["attacks"][str(tier)]
    model = read(f"formal-tier{tier}.json")
    require(row["tier"] == tier and profile["id"] == "ginkgo_arcade", f"I/II exact map identity: {tier}")
    require(profile["normal_map"] is True and profile["journey_tier"] == tier, f"Real formal profile tier: {tier}")
    require(profile["wave"] == (3 if tier==1 else 6), f"Approved real wave: {tier}")
    require(profile["fee"] == (tier-1)*4, f"Existing currency entry fee: {tier}")
    expected_reward = 4 if tier==1 else 12
    require(profile["completion_reward"] == expected_reward and row["pending"]["shards"] == expected_reward, f"Correct frozen completion reward: {tier}")
    require(row["claim"]["ok"] and row["claim"]["claimed_shards"] == expected_reward, f"Actual claim: {tier}")
    require(row["roots"] == 37 and row["coexisting_roots"] == 36 and row["boss_children"] == 4, f"Full unchanged actor and reward counts: {tier}")
    require(len(row["roster"]["camps"]) == 3 and all(len(c["entries"])==12 for c in row["roster"]["camps"]), f"Frozen complete 3x12 roster: {tier}")
    require(attack["boss"]["map_boss_attack_id"] == "ginkgo_shelter_slam", f"Natural boss owns map-only authority: {tier}")
    require(attack["attack"]["center"] == attack["boss"]["pos"], f"Frozen self-at-start center: {tier}")
    require("pulse_count" not in attack["attack"], f"Shared single-pulse scheduler: {tier}")
    require(attack["attack"]["profile"]["radius"] == 240.0 and attack["attack"]["profile"]["windup_seconds"] == 1.4, f"Approved danger geometry and duration: {tier}")
    require(attack["attack"]["profile"]["damage_multiplier"] == 1.2, f"Approved existing contact budget: {tier}")
    require(attack["visual"][0]["center"] == attack["attack"]["center"] and attack["visual"][0]["profile"] == attack["attack"]["profile"], f"Visual snapshot uses same real authority: {tier}")
    require(model["version"] == 50 and model["journey"]["best_tiers"]["ginkgo_arcade"] == tier, f"Genuine schema50 formal completion fixture: {tier}")
    require(model["journey"]["normal_root_kills"] == 37*tier, f"Root-only accumulated progression: {tier}")
    require(not model["journey"]["active_run"] and not model["journey"]["pending_map_reward"], f"Export occurs after real return and claim: {tier}")

require(report["runs"][1]["profile"]["normal_ids"] == ["enemy_attack_speed_110","enemy_damage_115"] and report["runs"][1]["profile"]["special_ids"] == ["frost_patrol"], "II uses two existing normal modifiers and one existing special")
freeze = report["attacks"]["freeze"]
require(abs(freeze["state"]["frozen_until"]-freeze["state"]["frozen_from"]-0.24)<1e-9, "Actual natural boss freeze is0.24")
require(freeze["paused"]["elapsed"] == 0.5 and freeze["paused"]["phase"] == "windup", "Freeze preserves original0.5 warning progress")
require(len(freeze["resolved"]) == 1 and freeze["resolved"][0]["applied"], "Resumed real attack resolves once")
require(freeze["paused"]["attack_id"] == freeze["resolved"][0]["attack_id"] and freeze["paused"]["center"] == freeze["resolved"][0]["center"], "Frozen identity and center survive thaw")
cast = read("freeze-cast.json")["cast"]
source = read("freeze-source.json")
require(source["version"] == 50 and "14209" in source["talents"]["allocated"] and source["talents"]["normal_points"] == 0, "Same lawful owned freeze source budget")
require(cast["skill_id"] == "frost" and "frost_lock" in cast["support_ids"], "Same compiled owned Frost Lock group")
require(abs(cast["snapshot"]["freeze_policy"]["duration_by_rarity"]["boss"]-0.24)<1e-9, "Frozen cast policy supplies exact boss duration")

hashes = {f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(RESULTS.iterdir()) if f.is_file()}
value = {"checks":len(checks),"failures":sum(not row["passed"] for row in checks),"checks_detail":checks,"files_sha256":hashes,"godot_rerun":False}
(HERE/"acceptance.json").write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n")
print(json.dumps({k:value[k] for k in ("checks","failures","godot_rerun")}))
raise SystemExit(1 if value["failures"] else 0)
