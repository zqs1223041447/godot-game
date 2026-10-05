#!/usr/bin/env python3
"""Frozen-v54, dependency-free static proposal audit. No Godot or runtime writes."""
from __future__ import annotations

import argparse
import ast
import hashlib
import itertools
import json
import math
import re
import subprocess
from pathlib import Path

FROZEN = "5e442d98e82b248efc3a553fdf9bf95733929096"
FILES = {
    "catalog": "scripts/items/equipment_catalog.gd",
    "build": "scripts/items/build_affix_profile.gd",
    "weapon": "scripts/items/weapon_local_rules.gd",
    "data": "scripts/game_data.gd",
    "assembly": "scripts/combat/damage_base_compiler.gd",
    "combat": "scripts/combat/combat_data.gd",
    "critical": "scripts/combat/critical_strike_rules.gd",
    "resolver": "scripts/combat/damage_resolver.gd",
    "defense": "scripts/mechanics/defense_rules.gd",
    "state": "scripts/canonical_game_state.gd",
}
NEW_IDS = ("whetstone_edge", "tempered_edge", "deepwell", "wellturn",
           "global_critical_chance", "global_critical_multiplier")
TARGETS = tuple(itertools.product((0, 80), (0.0, 0.25, 0.75)))


def literal(node):
    """Only the literal constructors needed by frozen catalog dictionaries."""
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Dict):
        return {literal(k): literal(v) for k, v in zip(node.keys, node.values)}
    if isinstance(node, (ast.List, ast.Tuple)):
        return [literal(v) for v in node.elts]
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
        args = [literal(v) for v in node.args]
        if node.func.id == "Vector2i":
            return args
        if node.func.id == "Color":
            return args[0]
    if isinstance(node, ast.Name) and node.id == "PI":
        return math.pi
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        return literal(node.left) / literal(node.right)
    if isinstance(node, ast.Attribute) and ast.unparse(node) == "NineSlotProfile._POOL_PROFILE":
        return {}  # Not needed by the four old weapon bases.
    raise ValueError(f"Unexpected literal node: {ast.dump(node)}")


def dictionary(text, name):
    start = re.search(r"const " + re.escape(name) + r"\s*:\s*Dictionary\s*=\s*\{", text).end() - 1
    depth, quoted, escaped = 0, False, False
    for end in range(start, len(text)):
        char = text[end]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return literal(ast.parse(text[start:end + 1], mode="eval").body)
    raise ValueError(name)


def eligible_tiers(family, level):
    return [t for t in family["tiers"] if t["level"] <= level and t["weight"] > 0]


def family_subsets(families, rarity, rules):
    rule = rules[rarity]
    prefixes = [key for key, value in families.items() if value["kind"] == "prefix"]
    suffixes = [key for key, value in families.items() if value["kind"] == "suffix"]
    for count in range(rule["min_affixes"], rule["max_affixes"] + 1):
        for pcount in range(max(0, count - rule["max_suffixes"]), min(count, rule["max_prefixes"]) + 1):
            for ps in itertools.combinations(prefixes, pcount):
                for ss in itertools.combinations(suffixes, count - pcount):
                    chosen = ps + ss
                    if len({families[x]["group"] for x in chosen}) == len(chosen):
                        yield chosen


def witness(base_id, rarity, level, chosen, families, tier_number=None, endpoint="max"):
    return {
        "id": "gear_000001", "base_id": base_id, "rarity": rarity, "item_level": level,
        "affixes": [{"id": key, "tier": t["tier"], "value": t[endpoint]}
                    for key in chosen
                    for t in [next(t for t in eligible_tiers(families[key], level) if t["tier"] == tier_number)
                              if tier_number else eligible_tiers(families[key], level)[-1]]],
    }


def valid(item, families, rules):
    rule = rules[item["rarity"]]
    affixes = item["affixes"]
    if not rule["min_affixes"] <= len(affixes) <= rule["max_affixes"]:
        return False
    groups, counts = set(), {"prefix": 0, "suffix": 0}
    for a in affixes:
        f = families[a["id"]]
        t = f["tiers"][a["tier"] - 1]
        if f["group"] in groups or t["level"] > item["item_level"] or not t["min"] <= a["value"] <= t["max"]:
            return False
        groups.add(f["group"])
        counts[f["kind"]] += 1
    return counts["prefix"] <= rule["max_prefixes"] and counts["suffix"] <= rule["max_suffixes"]


def reachability(families, rules):
    rows = []
    for level in (1, 8, 16):
        for rarity in rules:
            family_count, tier_count, value_count, by_count = 0, 0, 0, {}
            for selected in family_subsets(families, rarity, rules):
                family_count += 1
                by_count[str(len(selected))] = by_count.get(str(len(selected)), 0) + 1
                for tiers in itertools.product(*(eligible_tiers(families[key], level) for key in selected)):
                    item = {"base_id": "forgeblade", "rarity": rarity, "item_level": level,
                            "affixes": [{"id": key, "tier": t["tier"], "value": t["min"]}
                                        for key, t in zip(selected, tiers)]}
                    assert valid(item, families, rules)
                    remaining = {kind: {key: eligible_tiers(f, level) for key, f in families.items() if f["kind"] == kind}
                                 for kind in ("prefix", "suffix")}
                    # Construct an allowed roll path for each family+tier assignment.
                    # Every choice occupies a nonempty integer RNG interval. Every
                    # possible value in its inclusive range therefore has positive
                    # probability. Do not confuse this with uniformly likely items.
                    for key, t in zip(selected, tiers):
                        pool = remaining[families[key]["kind"]]
                        total = sum(entry["weight"] for ts in pool.values() for entry in ts)
                        assert 0 < t["weight"] <= total and t in pool[key]
                        assert t["max"] >= t["min"]
                        pool.pop(key)
                    tier_count += 1
                    value_count += math.prod(t["max"] - t["min"] + 1 for t in tiers)
            rows.append({"item_level_band": [level, {1: 7, 8: 15, 16: 30}[level]], "rarity": rarity,
                         "family_combinations": family_count, "family_by_affix_count": by_count,
                         "family_tier_combinations": tier_count, "family_tier_integer_value_combinations": value_count,
                         "all_have_positive_roll_paths": True})
    return rows


def components(item, families, bases):
    stats = dict(bases[item["base_id"]]["stats"])
    for a in item["affixes"]:
        family = families[a["id"]]
        amount = a["value"] / (100.0 if family["unit"] == "percent" else 10000.0 if family["unit"] == "basis_points" else 1.0)
        stats[family["stat"]] = stats.get(family["stat"], 0.0) + amount
    local = (4.0 + stats.get("weapon_added_physical", 0.0)) * (1.0 + stats.get("weapon_physical_increased", 0.0)) if item["base_id"] == "forgeblade" else 0.0
    # In frozen v54 ashwood W is NOT a cleave consumer.
    physical = (18.0 + stats.get("damage", 0.0) + local + stats.get("attack_added_physical", 0.0)) * 2.8
    fire = stats.get("attack_added_fire", 0.0) * 2.8 * (1.0 + stats.get("fire_increased", 0.0) + stats.get("attack_elemental_increased", 0.0))
    return {"physical": physical, "fire": fire, "local_W": local,
            "critical_chance": min(1.0, 0.05 * (1.0 + stats.get("crit_chance_increased", 0.0))),
            "critical_multiplier": 1.5 + stats.get("crit_multiplier_add", 0.0)}


def hit(c, armour, fire_resistance, multiplier=1.0):
    physical = c["physical"] * multiplier
    reduction = min(0.9, armour / (armour + 5.0 * physical)) if physical > 0 else 0.0
    return physical * (1.0 - reduction) + c["fire"] * multiplier * (1.0 - fire_resistance)


def measure(c, armour, fire_resistance):
    ordinary = hit(c, armour, fire_resistance)
    baseline_critical = hit(c, armour, fire_resistance, 1.5)
    critical = hit(c, armour, fire_resistance, c["critical_multiplier"])
    return {"ordinary_hit": ordinary,
            "baseline_critical_expected_hit": ordinary * 0.95 + baseline_critical * 0.05,
            "item_critical_expected_hit": ordinary * (1.0 - c["critical_chance"]) + critical * c["critical_chance"],
            "critical_hit": critical}


def optimize(candidates, families, bases, armour, fire_resistance, metric):
    best = None
    for item in candidates:
        c = components(item, families, bases)
        measured = measure(c, armour, fire_resistance)
        if best is None or measured[metric] > best["result"][metric] + 1e-10:
            best = {"item": item, "raw": c, "result": measured}
    return best


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=Path(__file__).resolve().parents[4] / "v054-faster-burning")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("budget.json"))
    args = parser.parse_args()
    source = {key: subprocess.check_output(["git", "-C", str(args.baseline), "show", f"{FROZEN}:{path}"], text=True)
              for key, path in FILES.items()}
    rules = dictionary(source["catalog"], "RARITIES")
    bases, families = {}, {}
    for name in ("BASES", "EXPANSION_BASES", "LOCAL_WEAPON_BASES"):
        bases.update(dictionary(source["catalog"], name))
    for name in ("AFFIXES", "EXPANSION_AFFIXES", "LOCAL_WEAPON_AFFIXES"):
        families.update(dictionary(source["catalog"], name))
    families.update(dictionary(source["build"], "AFFIXES"))
    profiles = dictionary(source["catalog"], "POOL_PROFILES")
    cleave = dictionary(source["data"], "SKILLS")["cleave"]
    assert cleave["hit_recipe"] == {"base_coefficient": 2.8, "added_effectiveness": 2.8, "damage_type": "physical"}
    assert (cleave["mana"], cleave["cooldown"]) == (12.0, 1.4)
    assert "stats.crit_base_chance = 0.05" in source["state"] and "stats.crit_base_multiplier = 1.5" in source["state"]
    old_bases = {key: value for key, value in bases.items() if value["slot"] == "weapon"}
    assert set(old_bases) == {"cinder_reed", "gale_spindle", "runewood_focus", "ashwood_bow"}
    old_families = {}
    for base_id, base in old_bases.items():
        profile = next(profile for profile in profiles.values() if base_id in profile.get("base_ids", []))
        old_families[base_id] = {key: families[key] for key in profile["affix_ids"] if key in families
                                 and base["slot"] in families[key]["slots"]
                                 and base_id in families[key].get("allowed_base_ids", [base_id])}
    proposal = {key: families[key] for key in NEW_IDS}
    assert len({f["group"] for f in proposal.values()}) == 6
    for family in proposal.values():
        assert [(t["level"], t["weight"]) for t in family["tiers"]] == [(1, 100), (8, 60), (16, 30)]
    bases["forgeblade"] = {"name": "forgeblade (proposal)", "slot": "weapon", "size": [1, 3], "stats": {}}
    rows = []
    for level in (1, 8, 16):
        for rarity in rules:
            old = [witness(base, rarity, level, selected, fs) for base, fs in old_families.items()
                   for selected in family_subsets(fs, rarity, rules)]
            new = [witness("forgeblade", rarity, level, selected, proposal)
                   for selected in family_subsets(proposal, rarity, rules)]
            assert all(valid(item, old_families[item["base_id"]], rules) for item in old)
            assert all(valid(item, proposal, rules) for item in new)
            for armour, resistance in TARGETS:
                for metric in ("ordinary_hit", "baseline_critical_expected_hit", "item_critical_expected_hit"):
                    o = optimize(old, families, bases, armour, resistance, metric)
                    n = optimize(new, families, bases, armour, resistance, metric)
                    rows.append({"level": level, "rarity": rarity, "armour": armour, "fire_resistance": resistance,
                                 "metric": metric, "old": o, "new": n,
                                 "new_over_old": n["result"][metric] / o["result"][metric],
                                 "old_family_subsets_evaluated": len(old), "new_family_subsets_evaluated": len(new)})
    fixed = {
        "white": witness("forgeblade", "normal", 1, (), proposal),
        "double_T1_min_legal_four_affix_rare": witness("forgeblade", "rare", 1, NEW_IDS[:4], proposal, 1, "min"),
        "double_T1_max_legal_four_affix_rare": witness("forgeblade", "rare", 1, NEW_IDS[:4], proposal, 1),
        "six_T1_min": witness("forgeblade", "rare", 1, NEW_IDS, proposal, 1, "min"),
        "six_T1_max": witness("forgeblade", "rare", 1, NEW_IDS, proposal, 1),
        "six_T2_max": witness("forgeblade", "rare", 8, NEW_IDS, proposal, 2),
        "six_T3_max": witness("forgeblade", "rare", 16, NEW_IDS, proposal, 3),
    }
    fixed_rows = {}
    for name, item in fixed.items():
        assert valid(item, proposal, rules)
        c = components(item, families, bases)
        fixed_rows[name] = {"item": item, "raw": c, "targets": [dict(armour=a, fire_resistance=r, **measure(c, a, r)) for a, r in TARGETS]}
    # Regression anchors are derived independently from the report loops.
    assert math.isclose(fixed_rows["white"]["raw"]["physical"], 61.6)
    assert math.isclose(fixed_rows["double_T1_max_legal_four_affix_rare"]["raw"]["physical"], 69.72)
    assert math.isclose(fixed_rows["six_T3_max"]["targets"][0]["item_critical_expected_hit"], 90.7494)
    bare = {"physical": 50.4, "fire": 0.0, "critical_chance": .05, "critical_multiplier": 1.5}
    scope = {"local_W_consumer": {"skill_id": "cleave", "role": "direct", "tags": ["hit", "attack", "melee", "area"]},
             "all_other_skill_roles_local_contribution": 0.0,
             "global_critical_scope": "All primary hit profiles and independent secondary critical profiles; never restricted to cleave",
             "six_T3_global_critical_example_unchanged_raw_50_4": {
                 "before": measure(bare, 0, 0)["item_critical_expected_hit"],
                 "after": measure(dict(bare, critical_chance=.07, critical_multiplier=1.65), 0, 0)["item_critical_expected_hit"]}}
    report = {
        "status": "STATIC PROPOSAL, NOT IMPLEMENTED; not gameplay DPS or balance proof",
        "frozen_commit": FROZEN, "source_sha256": {FILES[k]: hashlib.sha256(v.encode()).hexdigest() for k, v in source.items()},
        "scope": "Single-weapon substitution; B=18; other equipment/passives/supports absent; conditional on successful hit; no ailments, cooldown-rate, mana, evasion, positioning or area-density simulation",
        "proposal": {"base": bases["forgeblade"], "base_local_physical": 4.0,
                     "families": proposal, "eligibility_note": "Copied numeric family data only. Proposal adds the six families to forgeblade eligibility; frozen v54 does not accept these proposed items."},
        "cleave": {"base": 18.0, "coefficient": 2.8, "added_effectiveness": 2.8, "mana": 12.0, "cooldown": 1.4},
        "reachability": reachability(proposal, rules), "fixed_items": fixed_rows,
        "optimized_comparisons": rows, "consumer_scope": scope,
        "proof_note": "Enumerates every legal family subset. All affix tiers and values are monotone for these metrics, so the highest unlocked tier maximum is a valid upper bound and witness for each subset. Reachability separately enumerates every family+tier assignment and symbolically counts every inclusive integer value combination. Generator positive-weight interval reasoning establishes possible paths, not observed RNG seeds, frequency or production admission."}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"PASS: {len(rows)} independent metric/target/rarity/tier comparisons; 9 reachability bands; 7 legal fixed fixtures")
    for row in rows:
        if row["level"] == 16 and row["metric"] == "item_critical_expected_hit":
            print(f"L16 {row['rarity']:6} A{row['armour']:2} F{row['fire_resistance']:.2f}: old {row['old']['result'][row['metric']]:.6f} new {row['new']['result'][row['metric']]:.6f} ratio {row['new_over_old']:.6f}")
    print(args.output)


if __name__ == "__main__":
    main()
