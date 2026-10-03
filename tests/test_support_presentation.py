"""Small mutation fixtures for the support presentation audit."""
from __future__ import annotations

import copy
import unittest

from tools import check_support_presentation as audit


AREA_SOURCE = '''
const SKILL_IDS: Array[String] = ["nova", "meteor"]
const SUPPORTS: Dictionary = {
	"breadth": {
		"name": "广域辅助",
		"description": "新星与陨星：面积 ×1.44（半径 ×1.20），命中伤害总降 15%，魔力 ×1.20；冷却不变。",
		"skills": SKILL_IDS,
		"requires": ["area_hit"],
		"operations": [
			{"op": "area_multiplier", "value": 1.44},
			{"op": "area_hit_more", "value": -0.15},
			{"op": "mana_multiplier", "value": 1.20},
		],
	},
}
'''

SOURCE_SKILLS = {
    "nova": {"name": "奥能新星", "short_name": "新星", "capabilities": ["area_hit"]},
    "meteor": {"name": "陨星坠落", "short_name": "陨星", "capabilities": ["area_hit"]},
}


def fixture_definition() -> dict:
    return audit.parse_support_provider(AREA_SOURCE)["breadth"]


def run_description_audit(definition: dict) -> audit.AuditResult:
    result = audit.AuditResult()
    audit._check_description_claims(
        "breadth", definition, {"nova", "meteor"}, SOURCE_SKILLS, result, minimum_save_version=12
    )
    return result


def fixture_catalog(definition: dict, minimum_gate: int = 12) -> dict:
    catalog_definition = copy.deepcopy(definition)
    examples = {}
    for skill_id, radius, mana, cooldown in (
        ("nova", 155.0, 24.0, 6.0),
        ("meteor", 110.0, 32.0, 8.0),
    ):
        examples[skill_id] = {
            "before": {"mana": mana, "cooldown": cooldown, "initial_count": 0, "recipe": {"radius": radius}},
            "after": {
                "mana": mana * 1.2,
                "cooldown": cooldown,
                "initial_count": 0,
                "recipe": {"radius": radius * 1.2, "area_multiplier": 1.44},
            },
        }
    skills = {}
    for skill_id, fields in SOURCE_SKILLS.items():
        skills[skill_id] = {
            **fields,
            "compatible_supports": ["breadth"],
        }
    return {
        "save_version": 13,
        "supports": {"breadth": catalog_definition},
        "skills": skills,
        "support_program_examples": {"breadth": {"family": "area", "examples": examples}},
    }


class SupportPresentationAuditTests(unittest.TestCase):
    def test_parses_gdscript_constant_reference_in_metadata(self) -> None:
        definition = fixture_definition()
        self.assertEqual(definition["skills"], ["nova", "meteor"])
        self.assertEqual(definition["operations"][0], {"op": "area_multiplier", "value": 1.44})

    def test_catalog_description_mutant_is_detected(self) -> None:
        definition = fixture_definition()
        catalog = fixture_catalog(definition)
        catalog["supports"]["breadth"]["description"] = "mutant description"
        result = audit.AuditResult()
        audit._compare_catalog_metadata("breadth", definition, catalog["supports"]["breadth"], result)
        self.assertIn("CATALOG_METADATA_MISMATCH", {issue.code for issue in result.errors})

    def test_tooltip_mana_mutant_is_detected(self) -> None:
        definition = fixture_definition()
        definition["description"] = definition["description"].replace("魔力 ×1.20", "魔力 ×1.25")
        result = run_description_audit(definition)
        self.assertIn("TEXT_MANA_MISMATCH", {issue.code for issue in result.errors})

    def test_area_radius_mutant_is_detected(self) -> None:
        definition = fixture_definition()
        definition["description"] = definition["description"].replace("半径 ×1.20", "半径 ×1.10")
        result = run_description_audit(definition)
        self.assertIn("TEXT_AREA_RADIUS_MISMATCH", {issue.code for issue in result.errors})

    def test_damage_scope_mutant_is_detected(self) -> None:
        definition = fixture_definition()
        definition["description"] = definition["description"].replace(
            "命中伤害总降", "投射物命中伤害总降"
        )
        result = run_description_audit(definition)
        self.assertIn("TEXT_DAMAGE_SCOPE_MISMATCH", {issue.code for issue in result.errors})

    def test_save_gate_above_catalog_version_is_detected(self) -> None:
        definition = fixture_definition()
        catalog = fixture_catalog(definition)
        result = audit.audit_supports(
            {"breadth": definition},
            SOURCE_SKILLS,
            catalog,
            {"breadth": 14},
        )
        self.assertIn("GATE_AFTER_CATALOG_VERSION", {issue.code for issue in result.errors})


if __name__ == "__main__":
    unittest.main()
