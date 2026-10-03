#!/usr/bin/env python3
"""Static consistency checks for support metadata and its displayed help text.

This deliberately reads the checked-in runtime catalog. It does not run Godot,
rebuild the catalog, or reproduce combat/damage calculations.
"""
from __future__ import annotations

import argparse
import ast
import json
import math
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SUPPORT_PROVIDER_FILES = {
    "legacy": "scripts/combat/support_catalog.gd",
    "extension": "scripts/combat/projectile_support_rules.gd",
    "area": "scripts/combat/area_support_rules.gd",
    "program": "scripts/combat/resource_support_rules.gd",
    "element": "scripts/combat/element_support_rules.gd",
    "delivery": "scripts/combat/delivery_support_rules.gd",
}
EXPECTED_SUPPORT_COUNT = 16
DAMAGE_TYPE_NAMES = {
    "physical": "物理",
    "fire": "火焰",
    "cold": "冰霜",
    "lightning": "闪电",
    "chaos": "混沌",
}


@dataclass(frozen=True)
class Issue:
    code: str
    support_id: str
    message: str


@dataclass
class AuditResult:
    errors: list[Issue] = field(default_factory=list)
    manual_review: set[str] = field(default_factory=set)
    source_count: int = 0
    catalog_count: int = 0
    checked_preview_rows: int = 0
    save_version: int | None = None
    gates: dict[str, int] = field(default_factory=dict)

    def error(self, code: str, support_id: str, message: str) -> None:
        self.errors.append(Issue(code, support_id, message))


def _skip_space_and_comments(text: str, index: int) -> int:
    while index < len(text):
        if text[index].isspace():
            index += 1
            continue
        if text[index] == "#":
            newline = text.find("\n", index)
            return len(text) if newline < 0 else _skip_space_and_comments(text, newline + 1)
        break
    return index


def _matching_delimiter(text: str, opening: int, left: str, right: str) -> int:
    depth = 0
    quoted = False
    escaped = False
    index = opening
    while index < len(text):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == "#":
            newline = text.find("\n", index)
            if newline < 0:
                return -1
            index = newline
        elif char == '"':
            quoted = True
        elif char == left:
            depth += 1
        elif char == right:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return -1


def _constant_block(text: str, name: str, delimiter: str = "{") -> str:
    pattern = re.compile(
        r"\bconst\s+" + re.escape(name) + r"(?:\s*:[^=\n]+)?\s*=\s*" + re.escape(delimiter)
    )
    match = pattern.search(text)
    if not match:
        raise ValueError(f"constant {name} was not found")
    closing = {"{": "}", "[": "]"}[delimiter]
    opening = match.end() - 1
    end = _matching_delimiter(text, opening, delimiter, closing)
    if end < 0:
        raise ValueError(f"constant {name} has an unclosed {delimiter}")
    return text[opening : end + 1]


def _top_level_dictionary_entries(block: str) -> dict[str, str]:
    """Return literal top-level key -> value-block pairs from a GDScript dict."""
    entries: dict[str, str] = {}
    index = 1
    depth = 1
    while index < len(block) - 1:
        index = _skip_space_and_comments(block, index)
        if index >= len(block) - 1:
            break
        char = block[index]
        if char == '"':
            key_end = index + 1
            escaped = False
            while key_end < len(block):
                current = block[key_end]
                if escaped:
                    escaped = False
                elif current == "\\":
                    escaped = True
                elif current == '"':
                    break
                key_end += 1
            if key_end >= len(block):
                raise ValueError("unterminated dictionary key")
            key = json.loads(block[index : key_end + 1])
            after_key = _skip_space_and_comments(block, key_end + 1)
            if depth == 1 and after_key < len(block) and block[after_key] == ":":
                value_start = _skip_space_and_comments(block, after_key + 1)
                if value_start < len(block) and block[value_start] == "{":
                    value_end = _matching_delimiter(block, value_start, "{", "}")
                    if value_end < 0:
                        raise ValueError(f"unclosed value for {key}")
                    entries[key] = block[value_start : value_end + 1]
                    index = value_end + 1
                    continue
            index = key_end + 1
            continue
        if char == "#":
            index = _skip_space_and_comments(block, index)
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        index += 1
    return entries


def _eval_literal(node: ast.AST, constants: dict[str, Any]) -> Any:
    if isinstance(node, ast.Constant) and isinstance(node.value, (str, int, float, bool, type(None))):
        return node.value
    if isinstance(node, ast.List):
        return [_eval_literal(value, constants) for value in node.elts]
    if isinstance(node, ast.Tuple):
        return tuple(_eval_literal(value, constants) for value in node.elts)
    if isinstance(node, ast.Dict):
        return {
            _eval_literal(key, constants): _eval_literal(value, constants)
            for key, value in zip(node.keys, node.values)
        }
    if isinstance(node, ast.Name) and node.id in constants:
        return constants[node.id]
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
        value = _eval_literal(node.operand, constants)
        return -value if isinstance(node.op, ast.USub) else value
    raise ValueError(f"unsupported GDScript literal expression: {ast.dump(node, include_attributes=False)}")


def _literal_value(expression: str, constants: dict[str, Any] | None = None) -> Any:
    parsed = ast.parse(expression, mode="eval")
    return _eval_literal(parsed.body, constants or {})


def _constant_arrays(text: str) -> dict[str, Any]:
    arrays: dict[str, Any] = {}
    pattern = re.compile(r"\bconst\s+(\w+)(?:\s*:[^=\n]+)?\s*=\s*\[")
    for match in pattern.finditer(text):
        name = match.group(1)
        opening = match.end() - 1
        end = _matching_delimiter(text, opening, "[", "]")
        if end >= 0:
            try:
                arrays[name] = _literal_value(text[opening : end + 1], arrays)
            except (SyntaxError, ValueError):
                continue
    return arrays


def parse_support_provider(text: str) -> dict[str, dict[str, Any]]:
    constants = _constant_arrays(text)
    block = _constant_block(text, "SUPPORTS")
    result: dict[str, dict[str, Any]] = {}
    for support_id, definition_block in _top_level_dictionary_entries(block).items():
        parsed = ast.parse(definition_block, mode="eval")
        value = _eval_literal(parsed.body, constants)
        if not isinstance(value, dict):
            raise ValueError(f"support {support_id} is not a dictionary")
        result[support_id] = value
    return result


def parse_game_skills(text: str) -> dict[str, dict[str, Any]]:
    block = _constant_block(text, "SKILLS")
    skills: dict[str, dict[str, Any]] = {}
    for skill_id, skill_block in _top_level_dictionary_entries(block).items():
        def read_string(field_name: str) -> str | None:
            match = re.search(
                r'"' + re.escape(field_name) + r'"\s*:\s*("(?:\\.|[^"\\])*")',
                skill_block,
            )
            return json.loads(match.group(1)) if match else None

        capability_match = re.search(r'"capabilities"\s*:\s*(\[[^\]]*\])', skill_block)
        capabilities = _literal_value(capability_match.group(1)) if capability_match else None
        if not isinstance(capabilities, list) or not all(isinstance(item, str) for item in capabilities):
            raise ValueError(f"skill {skill_id} has no readable capability list")
        skills[skill_id] = {
            "name": read_string("name"),
            "short_name": read_string("short_name"),
            "capabilities": capabilities,
        }
    return skills


def parse_integer_constant(text: str, name: str) -> int:
    match = re.search(r"\bconst\s+" + re.escape(name) + r"\s*:\s*int\s*=\s*(\d+)", text)
    if not match:
        raise ValueError(f"integer constant {name} was not found")
    return int(match.group(1))


def _within_tolerance(actual: float, expected: float) -> bool:
    return math.isclose(float(actual), float(expected), rel_tol=1e-8, abs_tol=1e-8)


def _operation_values(definition: dict[str, Any], operation_name: str) -> list[float]:
    values: list[float] = []
    for operation in definition.get("operations", []):
        if isinstance(operation, dict) and operation.get("op") == operation_name:
            try:
                values.append(float(operation["value"]))
            except (KeyError, TypeError, ValueError):
                pass
    return values


def _single_operation_value(
    support_id: str, definition: dict[str, Any], name: str, result: AuditResult
) -> float | None:
    values = _operation_values(definition, name)
    if len(values) > 1:
        result.error("DUPLICATE_OPERATION", support_id, f"{name} occurs more than once")
        return None
    return values[0] if values else None


def _compare_claim(
    support_id: str,
    description: str,
    pattern: str,
    expected: float,
    code: str,
    label: str,
    result: AuditResult,
    *,
    required: bool = True,
) -> bool:
    matches = list(re.finditer(pattern, description))
    if not matches:
        if required:
            result.error(code, support_id, f"displayed description does not state {label}")
        return False
    if len(matches) != 1:
        result.error(code, support_id, f"displayed description has {len(matches)} {label} claims")
        return False
    try:
        actual = float(matches[0].group(1))
    except (IndexError, ValueError):
        result.error(code, support_id, f"displayed {label} claim is not numeric")
        return False
    if not _within_tolerance(actual, expected):
        result.error(code, support_id, f"displayed {label} is {actual:g}; source operation is {expected:g}")
        return False
    return True


def _percent_claim_pattern(scope: str, direction: str) -> str:
    number = r"([0-9]+(?:\.[0-9]+)?)"
    if scope == "area_hit":
        prefix = r"(?<!投射物)(?<!主)命中伤害总"
    else:
        prefix = re.escape(scope + "伤害总")
    return prefix + re.escape(direction) + r"\s*" + number + r"\s*%"


def _check_description_claims(
    support_id: str,
    definition: dict[str, Any],
    eligible_skills: set[str],
    source_skills: dict[str, dict[str, Any]],
    result: AuditResult,
    *,
    minimum_save_version: int | None = None,
) -> None:
    description = definition.get("description")
    if not isinstance(description, str):
        result.error("DESCRIPTION_MISSING", support_id, "source description is missing")
        return

    mana = _single_operation_value(support_id, definition, "mana_multiplier", result)
    if mana is None:
        result.error("MANA_OPERATION_MISSING", support_id, "support definition has no mana_multiplier operation")
    else:
        _compare_claim(
            support_id,
            description,
            r"(?:魔力(?:消耗)?|耗魔)\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)",
            mana,
            "TEXT_MANA_MISMATCH",
            "mana multiplier",
            result,
        )

    cooldown = _single_operation_value(support_id, definition, "cooldown_multiplier", result)
    cooldown_claim = re.search(r"冷却(?:时间)?\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)", description)
    unchanged_claim = "冷却不变" in description
    if cooldown is not None:
        if cooldown_claim:
            actual = float(cooldown_claim.group(1))
            if not _within_tolerance(actual, cooldown):
                result.error("TEXT_COOLDOWN_MISMATCH", support_id, f"displayed cooldown is {actual:g}; source operation is {cooldown:g}")
        else:
            result.error("TEXT_COOLDOWN_MISSING", support_id, "source changes cooldown but description has no numeric cooldown claim")
    elif cooldown_claim:
        actual = float(cooldown_claim.group(1))
        if not _within_tolerance(actual, 1.0):
            result.error("TEXT_COOLDOWN_MISMATCH", support_id, f"displayed cooldown is {actual:g}; no cooldown operation means 1")
    elif not unchanged_claim:
        result.manual_review.add(f"{support_id}: help text does not state whether cooldown changes")

    op_scopes = {
        "projectile_hit_more": "投射物命中",
        "primary_hit_more": "主命中",
        "area_hit_more": "area_hit",
    }
    for operation in definition.get("operations", []):
        if not isinstance(operation, dict):
            result.error("OPERATION_SHAPE", support_id, "operation metadata is not a dictionary")
            continue
        op_name = operation.get("op")
        try:
            value = float(operation["value"])
        except (KeyError, TypeError, ValueError):
            result.error("OPERATION_VALUE", support_id, f"{op_name!r} has no numeric value")
            continue

        if op_name in op_scopes:
            direction = "增" if value >= 0 else "降"
            scope = op_scopes[op_name]
            if op_name == "area_hit_more" and re.search(r"(?:投射物|主)命中伤害总", description):
                result.error("TEXT_DAMAGE_SCOPE_MISMATCH", support_id, "area hit operation is described as projectile/primary-hit damage")
                continue
            _compare_claim(
                support_id,
                description,
                _percent_claim_pattern(scope, direction),
                abs(value) * 100.0,
                "TEXT_DAMAGE_CLAIM_MISMATCH",
                f"{scope} damage percent",
                result,
            )
        elif op_name in {"primary_component_more", "other_components_more"}:
            damage_type = operation.get("damage_type")
            type_name = DAMAGE_TYPE_NAMES.get(damage_type)
            if not type_name:
                result.error("DAMAGE_TYPE_UNKNOWN", support_id, f"unknown operation damage type {damage_type!r}")
                continue
            if "主命中" not in description:
                result.error("TEXT_DAMAGE_SCOPE_MISMATCH", support_id, "component modifier text does not identify the primary hit scope")
            phrase = type_name if op_name == "primary_component_more" else "其他类型"
            direction = "增" if value >= 0 else "降"
            pattern = re.escape(phrase + "伤害总") + re.escape(direction) + r"\s*([0-9]+(?:\.[0-9]+)?)\s*%"
            _compare_claim(
                support_id,
                description,
                pattern,
                abs(value) * 100.0,
                "TEXT_DAMAGE_CLAIM_MISMATCH",
                f"{phrase} damage percent",
                result,
            )
        elif op_name == "projectile_speed_multiplier":
            _compare_claim(support_id, description, r"投射物速度\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)", value,
                           "TEXT_SPEED_MISMATCH", "projectile speed multiplier", result)
        elif op_name == "area_multiplier":
            _compare_claim(support_id, description, r"面积\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)", value,
                           "TEXT_AREA_MISMATCH", "area multiplier", result)
            radius = _compare_claim(support_id, description, r"半径\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)",
                                    math.sqrt(value), "TEXT_AREA_RADIUS_MISMATCH", "radius multiplier", result)
            if not radius:
                result.manual_review.add(f"{support_id}: area/radius prose needs a human check")
        elif op_name == "slow_duration_multiplier":
            _compare_claim(support_id, description, r"现有减速时间\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)", value,
                           "TEXT_SLOW_DURATION_MISMATCH", "slow duration multiplier", result)
        elif op_name == "chain_followup_range_multiplier":
            _compare_claim(support_id, description, r"后续寻敌距离\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)", value,
                           "TEXT_CHAIN_RANGE_MISMATCH", "follow-up range multiplier", result)
            range_pair = re.search(r"后续寻敌距离[^（(]*[（(]\s*([0-9]+(?:\.[0-9]+)?)\s*至\s*([0-9]+(?:\.[0-9]+)?)", description)
            if range_pair:
                before, after = map(float, range_pair.groups())
                if before <= 0 or not _within_tolerance(after / before, value):
                    result.error("TEXT_CHAIN_RANGE_MISMATCH", support_id, "displayed follow-up range endpoints do not match multiplier")
        elif op_name in {"add_initial_projectiles", "add_pierce", "chain_extra_targets"}:
            labels = {
                "add_initial_projectiles": r"初始投射物\s*\+\s*([0-9]+(?:\.[0-9]+)?)",
                "add_pierce": r"穿透\s*\+\s*([0-9]+(?:\.[0-9]+)?)",
                "chain_extra_targets": r"总命中目标数\s*\+\s*([0-9]+(?:\.[0-9]+)?)",
            }
            _compare_claim(support_id, description, labels[op_name], value,
                           "TEXT_COUNT_MISMATCH", op_name, result)

    prefix = re.split(r"[；;。：:]", description, maxsplit=1)[0]
    mentions = _skill_mentions(prefix, source_skills)
    if mentions:
        if mentions != eligible_skills:
            result.error(
                "TEXT_SKILLS_MISMATCH",
                support_id,
                f"description prefix names {sorted(mentions)}; metadata admits {sorted(eligible_skills)}",
            )
    else:
        result.manual_review.add(f"{support_id}: help text does not enumerate eligible skills")

    version_claim = re.search(r"(?:最低)?存档版本\s*(?:至少|不低于|[≥=:：])\s*(\d+)", description)
    if version_claim and minimum_save_version is not None and int(version_claim.group(1)) != minimum_save_version:
        result.error("TEXT_SAVE_VERSION_MISMATCH", support_id, f"displayed save gate is {version_claim.group(1)}; source gate is {minimum_save_version}")


def _skill_mentions(text: str, source_skills: dict[str, dict[str, Any]]) -> set[str]:
    variants: list[tuple[str, str]] = []
    for skill_id, fields in source_skills.items():
        for name in (fields.get("name"), fields.get("short_name")):
            if isinstance(name, str) and name:
                variants.append((name, skill_id))
    variants.sort(key=lambda item: (-len(item[0]), item[0]))
    occupied: list[tuple[int, int]] = []
    found: set[str] = set()
    for name, skill_id in variants:
        for match in re.finditer(re.escape(name), text):
            span = match.span()
            if any(span[0] < end and start < span[1] for start, end in occupied):
                continue
            occupied.append(span)
            found.add(skill_id)
    return found


def _expected_eligible_skills(
    definition: dict[str, Any], source_skills: dict[str, dict[str, Any]]
) -> set[str]:
    if isinstance(definition.get("skills"), list):
        return set(definition["skills"])
    required = definition.get("requires", [])
    if not isinstance(required, list):
        return set()
    return {
        skill_id
        for skill_id, skill in source_skills.items()
        if all(capability in skill.get("capabilities", []) for capability in required)
    }


def _expected_family(definition: dict[str, Any]) -> str:
    if isinstance(definition.get("family"), str):
        return definition["family"]
    if definition.get("requires") == ["area_hit"]:
        return "area"
    return "projectile"


def _compare_catalog_metadata(
    support_id: str, source_definition: dict[str, Any], catalog_definition: Any, result: AuditResult
) -> None:
    if not isinstance(catalog_definition, dict):
        result.error("CATALOG_SUPPORT_MISSING", support_id, "offline catalog support entry is not an object")
        return
    comparable = {key: value for key, value in catalog_definition.items() if key != "minimum_save_version"}
    if comparable != source_definition:
        result.error("CATALOG_METADATA_MISMATCH", support_id, "offline support metadata differs from runtime source metadata")


def _compare_ratio(
    support_id: str,
    after: Any,
    before: Any,
    expected: float,
    field_name: str,
    result: AuditResult,
) -> None:
    try:
        actual = float(after) / float(before)
    except (TypeError, ValueError, ZeroDivisionError):
        result.error("PREVIEW_FIELD_MISSING", support_id, f"catalog preview cannot compare {field_name}")
        return
    if not _within_tolerance(actual, expected):
        result.error("PREVIEW_FACTOR_MISMATCH", support_id, f"catalog preview {field_name} ratio is {actual:g}; source operation is {expected:g}")


def _compare_preview_rows(
    support_id: str,
    definition: dict[str, Any],
    examples: Any,
    eligible: set[str],
    result: AuditResult,
) -> None:
    if not isinstance(examples, dict):
        result.error("PREVIEW_EXAMPLES_MISSING", support_id, "offline catalog has no per-skill support examples")
        return
    if set(examples) != eligible:
        result.error("PREVIEW_SKILLS_MISMATCH", support_id, f"preview skills {sorted(examples)} differ from eligible skills {sorted(eligible)}")
    factors: dict[str, float] = {
        "mana_multiplier": 1.0,
        "cooldown_multiplier": 1.0,
    }
    for operation in definition.get("operations", []):
        if not isinstance(operation, dict):
            continue
        name = operation.get("op")
        if name in factors:
            factors[name] *= float(operation.get("value", 1.0))
    for skill_id, pair in examples.items():
        if not isinstance(pair, dict) or not isinstance(pair.get("before"), dict) or not isinstance(pair.get("after"), dict):
            result.error("PREVIEW_ROW_SHAPE", support_id, f"preview example for {skill_id} has no before/after pair")
            continue
        before, after = pair["before"], pair["after"]
        result.checked_preview_rows += 1
        _compare_ratio(support_id, after.get("mana"), before.get("mana"), factors["mana_multiplier"], f"{skill_id} mana", result)
        _compare_ratio(support_id, after.get("cooldown"), before.get("cooldown"), factors["cooldown_multiplier"], f"{skill_id} cooldown", result)
        before_recipe = before.get("recipe", {})
        after_recipe = after.get("recipe", {})
        for operation in definition.get("operations", []):
            if not isinstance(operation, dict):
                continue
            op_name = operation.get("op")
            value = float(operation.get("value", 0.0))
            if op_name == "add_initial_projectiles":
                actual = int(after.get("initial_count", 0)) - int(before.get("initial_count", 0))
                if actual != int(value):
                    result.error("PREVIEW_FACTOR_MISMATCH", support_id, f"catalog preview {skill_id} initial count changes by {actual}; source operation is {value:g}")
            elif op_name == "add_pierce":
                try:
                    actual = int(after_recipe["pierce"]) - int(before_recipe["pierce"])
                except (KeyError, TypeError, ValueError):
                    actual = None
                if actual != int(value):
                    result.error("PREVIEW_FACTOR_MISMATCH", support_id, f"catalog preview {skill_id} pierce changes by {actual}; source operation is {value:g}")
            elif op_name == "projectile_speed_multiplier":
                _compare_ratio(support_id, after_recipe.get("speed"), before_recipe.get("speed"), value, f"{skill_id} projectile speed", result)
            elif op_name == "slow_duration_multiplier":
                _compare_ratio(support_id, after_recipe.get("slow"), before_recipe.get("slow"), value, f"{skill_id} slow duration", result)
            elif op_name == "area_multiplier":
                if not _within_tolerance(float(after_recipe.get("area_multiplier", 1.0)), value):
                    result.error("PREVIEW_FACTOR_MISMATCH", support_id, f"catalog preview {skill_id} area multiplier differs from source")
                _compare_ratio(support_id, after_recipe.get("radius"), before_recipe.get("radius"), math.sqrt(value), f"{skill_id} radius", result)
            elif op_name == "chain_extra_targets":
                try:
                    actual = int(after_recipe["hit"]["bounce_count"]) - int(before_recipe["hit"]["bounce_count"])
                except (KeyError, TypeError, ValueError):
                    actual = None
                if actual != int(value):
                    result.error("PREVIEW_FACTOR_MISMATCH", support_id, f"catalog preview {skill_id} target count changes by {actual}; source operation is {value:g}")
            elif op_name == "chain_followup_range_multiplier":
                _compare_ratio(support_id, after_recipe.get("followup_range"), before_recipe.get("followup_range"), value, f"{skill_id} follow-up range", result)


def audit_supports(
    source_supports: dict[str, dict[str, Any]],
    source_skills: dict[str, dict[str, Any]],
    catalog: dict[str, Any],
    minimum_versions: dict[str, int],
    *,
    expected_count: int | None = None,
    panel_source: str = "",
    builder_source: str = "",
) -> AuditResult:
    result = AuditResult(source_count=len(source_supports))
    catalog_supports = catalog.get("supports", {})
    if not isinstance(catalog_supports, dict):
        catalog_supports = {}
    result.catalog_count = len(catalog_supports)
    if expected_count is not None and len(source_supports) != expected_count:
        result.error("SOURCE_COUNT_MISMATCH", "", f"expected {expected_count} runtime supports, found {len(source_supports)}")
    if set(source_supports) != set(catalog_supports):
        result.error("SUPPORT_ID_SET_MISMATCH", "", "runtime and offline support ID sets differ")

    catalog_skills = catalog.get("skills", {})
    if not isinstance(catalog_skills, dict):
        catalog_skills = {}
    for skill_id, source_skill in source_skills.items():
        catalog_skill = catalog_skills.get(skill_id)
        if not isinstance(catalog_skill, dict):
            result.error("CATALOG_SKILL_MISSING", skill_id, "offline catalog skill entry is missing")
            continue
        for field_name in ("name", "short_name", "capabilities"):
            if catalog_skill.get(field_name) != source_skill.get(field_name):
                result.error("CATALOG_SKILL_MISMATCH", skill_id, f"offline skill field {field_name!r} differs from GameData")

    result.save_version = catalog.get("save_version") if isinstance(catalog.get("save_version"), int) else None
    preview_catalog = catalog.get("support_program_examples", {})
    minimum_versions_present = True
    for support_id, definition in source_supports.items():
        eligible = _expected_eligible_skills(definition, source_skills)
        _compare_catalog_metadata(support_id, definition, catalog_supports.get(support_id), result)
        catalog_eligible = {
            skill_id
            for skill_id, skill in catalog_skills.items()
            if isinstance(skill, dict) and support_id in skill.get("compatible_supports", [])
        }
        if eligible != catalog_eligible:
            result.error("CATALOG_ELIGIBILITY_MISMATCH", support_id, f"GameData/provider eligibility is {sorted(eligible)}; catalog skill links are {sorted(catalog_eligible)}")

        example_entry = preview_catalog.get(support_id, {}) if isinstance(preview_catalog, dict) else {}
        if isinstance(example_entry, dict) and example_entry.get("family") != _expected_family(definition):
            result.error("PREVIEW_FAMILY_MISMATCH", support_id, f"example family is {example_entry.get('family')!r}; expected {_expected_family(definition)!r}")
        examples = example_entry.get("examples", {}) if isinstance(example_entry, dict) else None
        _compare_preview_rows(support_id, definition, examples, eligible, result)

        minimum = minimum_versions.get(support_id, 1)
        result.gates[support_id] = minimum
        catalog_definition = catalog_supports.get(support_id, {})
        gate_in_catalog = isinstance(catalog_definition, dict) and "minimum_save_version" in catalog_definition
        minimum_versions_present = minimum_versions_present and gate_in_catalog
        if gate_in_catalog:
            try:
                recorded_minimum = int(catalog_definition["minimum_save_version"])
            except (TypeError, ValueError):
                result.error("CATALOG_GATE_INVALID", support_id, "catalog minimum_save_version is not an integer")
            else:
                if recorded_minimum != minimum:
                    result.error("CATALOG_GATE_MISMATCH", support_id, f"catalog gate is {recorded_minimum}; SupportRegistry gate is {minimum}")
        if result.save_version is None:
            result.error("CATALOG_SAVE_VERSION_MISSING", support_id, "offline catalog has no integer save_version")
        elif minimum > result.save_version:
            result.error("GATE_AFTER_CATALOG_VERSION", support_id, f"source minimum save version {minimum} exceeds catalog save version {result.save_version}")

        _check_description_claims(
            support_id,
            definition,
            eligible,
            source_skills,
            result,
            minimum_save_version=minimum,
        )

    if not minimum_versions_present:
        gated = sorted(support_id for support_id, version in result.gates.items() if version > 1)
        if gated:
            result.manual_review.add(
                "catalog.json has only a global save_version, not per-support gates; verify source gate mapping for "
                + ", ".join(gated)
            )
    if panel_source and 'definition.get("description", "")' not in panel_source:
        result.error("UI_DESCRIPTION_BINDING_MISSING", "", "SkillSupportPanel no longer renders the support definition description")
    if builder_source and "cards.append(add('supports',key,s['name'],s['description'],body" not in builder_source:
        result.error("OFFLINE_DESCRIPTION_BINDING_MISSING", "", "offline builder no longer renders catalog support descriptions")
    result.manual_review.add(
        "Semantic prose beyond the recognized numeric/scope phrases is not proven (for example exclusions and edge cases); inspect each help description and compiler behavior when wording changes."
    )
    return result


def read_repository(root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], dict[str, int], dict[str, Any], str, str]:
    source_supports: dict[str, dict[str, Any]] = {}
    provider_ids: dict[str, set[str]] = {}
    source_texts: dict[str, str] = {}
    for provider, relative_path in SUPPORT_PROVIDER_FILES.items():
        path = root / relative_path
        text = path.read_text(encoding="utf-8")
        source_texts[provider] = text
        definitions = parse_support_provider(text)
        provider_ids[provider] = set(definitions)
        overlap = set(source_supports) & set(definitions)
        if overlap:
            raise ValueError(f"duplicate support IDs across providers: {sorted(overlap)}")
        source_supports.update(definitions)

    registry_text = (root / "scripts/combat/support_registry.gd").read_text(encoding="utf-8")
    area_text = source_texts["area"]
    extension_gate = parse_integer_constant(registry_text, "EXTENSION_SAVE_VERSION")
    batch_gate = parse_integer_constant(registry_text, "BATCH_SAVE_VERSION")
    area_versions = _literal_value(_constant_block(area_text, "SAVE_VERSIONS"))
    if not isinstance(area_versions, dict):
        raise ValueError("AreaSupportRules.SAVE_VERSIONS is not a dictionary")
    routing_patterns = (
        r"Extension\.SUPPORTS\.has\(id\)\s*:\s*minimum\s*=\s*EXTENSION_SAVE_VERSION",
        r"Area\.SUPPORTS\.has\(id\)\s*:\s*minimum\s*=\s*int\(Area\.SAVE_VERSIONS\[id\]\)",
        r"is_program_support\(id\)\s*:\s*minimum\s*=\s*BATCH_SAVE_VERSION",
    )
    if any(not re.search(pattern, registry_text) for pattern in routing_patterns):
        raise ValueError("SupportRegistry save-gate routing changed; update this static audit before relying on it")
    minimum_versions: dict[str, int] = {support_id: 1 for support_id in provider_ids["legacy"]}
    minimum_versions.update({support_id: extension_gate for support_id in provider_ids["extension"]})
    for support_id in provider_ids["area"]:
        if support_id not in area_versions:
            raise ValueError(f"area support {support_id} has no AreaSupportRules.SAVE_VERSIONS entry")
        minimum_versions[support_id] = int(area_versions[support_id])
    program_ids = provider_ids["program"] | provider_ids["element"] | provider_ids["delivery"]
    minimum_versions.update({support_id: batch_gate for support_id in program_ids})
    if set(minimum_versions) != set(source_supports):
        raise ValueError("source save-gate mapping does not cover exactly the support IDs")

    source_skills_text = (root / "scripts/game_data.gd").read_text(encoding="utf-8")
    source_skills = parse_game_skills(source_skills_text)
    catalog = json.loads((root / "docs/reference/catalog.json").read_text(encoding="utf-8"))
    panel_source = (root / "scripts/skill_support_panel.gd").read_text(encoding="utf-8")
    builder_source = (root / "tools/build_reference.py").read_text(encoding="utf-8")
    return source_supports, source_skills, minimum_versions, catalog, panel_source, builder_source


def format_report(result: AuditResult) -> str:
    lines = [
        f"Support presentation audit: {result.source_count} runtime definitions; {result.catalog_count} offline catalog entries; "
        f"{result.checked_preview_rows} exported preview rows checked.",
    ]
    if result.save_version is not None:
        counts = Counter(result.gates.values())
        gate_summary = ", ".join(f"v{version}: {counts[version]}" for version in sorted(counts))
        lines.append(f"Catalog save_version: {result.save_version}; source minimum gates: {gate_summary}.")
    if result.errors:
        lines.append(f"Errors: {len(result.errors)}")
        lines.extend(f"  ERROR {issue.code} {issue.support_id}: {issue.message}" for issue in result.errors)
    else:
        lines.append("Errors: 0")
    if result.manual_review:
        lines.append("Manual review:")
        lines.extend(f"  - {item}" for item in sorted(result.manual_review))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="repository root")
    args = parser.parse_args(argv)
    try:
        source_supports, source_skills, gates, catalog, panel_source, builder_source = read_repository(args.root.resolve())
        result = audit_supports(
            source_supports,
            source_skills,
            catalog,
            gates,
            expected_count=EXPECTED_SUPPORT_COUNT,
            panel_source=panel_source,
            builder_source=builder_source,
        )
    except (OSError, ValueError, SyntaxError, json.JSONDecodeError) as error:
        print(f"Support presentation audit could not run: {error}", file=sys.stderr)
        return 2
    print(format_report(result))
    return 1 if result.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
