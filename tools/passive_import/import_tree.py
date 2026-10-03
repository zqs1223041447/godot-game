#!/usr/bin/env python3
"""Validate and deterministically normalize the pinned PoE1 passive tree export.

This is an offline-first data preparation tool. It never changes game runtime or
save data. The optional fetch path only replaces the raw source after its pinned
SHA-256 and byte count match the committed source manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPOSITORY_ROOT / "data" / "passive_source"
MANIFEST_PATH = SOURCE_DIR / "source_manifest.json"
DEFAULT_SOURCE = SOURCE_DIR / "data.json"
DEFAULT_OUTPUT = SOURCE_DIR / "normalized_tree.json"

PINNED_COMMIT = "8bd138b32ea2631455cac5935bfab089f826094f"
PINNED_SHA256 = "7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122"
PINNED_BYTES = 6_666_935
SCHEMA_VERSION = 1

# GGG documents the 16-position orbit mapping in skilltree-export README 3.17.0.
# The 40-position mapping and coordinate signs match the established PoE tree
# reader in PathOfBuildingCommunity/PathOfBuilding's PassiveTree.lua.
ANGLES_16 = (0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330)
ANGLES_40 = (
    0, 10, 20, 30, 40, 45, 50, 60, 70, 80,
    90, 100, 110, 120, 130, 135, 140, 150, 160, 170,
    180, 190, 200, 210, 220, 225, 230, 240, 250, 260,
    270, 280, 290, 300, 310, 315, 320, 330, 340, 350,
)
OMITTED_ROOT_FIELDS = ("extraImages", "sprites")


class ImportErrorDetail(ValueError):
    """Invalid source, manifest, or normalized output."""


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ImportErrorDetail(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ImportErrorDetail(f"non-standard JSON numeric constant: {value}")


def parse_json_bytes(raw_bytes: bytes, label: str) -> Any:
    try:
        return json.loads(
            raw_bytes.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ImportErrorDetail(f"{label} is not valid UTF-8 JSON: {exc}") from exc


def canonical_json_bytes(value: Any) -> bytes:
    try:
        text = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            indent=2,
        )
    except (TypeError, ValueError) as exc:
        raise ImportErrorDetail(f"cannot serialize normalized JSON: {exc}") from exc
    return (text + "\n").encode("utf-8")


def node_sort_key(node_id: str) -> tuple[int, int | str]:
    if node_id == "root":
        return (0, "")
    if node_id.isdecimal():
        return (1, int(node_id))
    return (2, node_id)


def sorted_ids(values: Any) -> list[str]:
    return sorted((str(value) for value in values), key=node_sort_key)


def load_manifest(path: Path = MANIFEST_PATH) -> dict[str, Any]:
    manifest = parse_json_bytes(path.read_bytes(), str(path))
    if not isinstance(manifest, dict):
        raise ImportErrorDetail("source manifest must be a JSON object")
    source = manifest.get("source")
    if not isinstance(source, dict):
        raise ImportErrorDetail("source manifest lacks the source object")
    if source.get("commit") != PINNED_COMMIT:
        raise ImportErrorDetail("manifest commit does not match the importer pin")
    if source.get("sha256") != PINNED_SHA256:
        raise ImportErrorDetail("manifest SHA-256 does not match the importer pin")
    if source.get("bytes") != PINNED_BYTES:
        raise ImportErrorDetail("manifest byte count does not match the importer pin")
    if source.get("data_url") != (
        "https://raw.githubusercontent.com/grindinggear/skilltree-export/"
        + PINNED_COMMIT
        + "/data.json"
    ):
        raise ImportErrorDetail("manifest URL is not the pinned official raw URL")
    return manifest


def verify_source_bytes(raw_bytes: bytes, manifest: dict[str, Any]) -> str:
    source = manifest["source"]
    digest = hashlib.sha256(raw_bytes).hexdigest()
    if len(raw_bytes) != source["bytes"]:
        raise ImportErrorDetail(
            f"source byte count mismatch: expected {source['bytes']}, got {len(raw_bytes)}"
        )
    if digest != source["sha256"]:
        raise ImportErrorDetail(
            f"source SHA-256 mismatch: expected {source['sha256']}, got {digest}"
        )
    return digest


def _require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ImportErrorDetail(f"{label} must be an object")
    return value


def _require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ImportErrorDetail(f"{label} must be an array")
    return value


def _finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ImportErrorDetail(f"{label} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise ImportErrorDetail(f"{label} must be finite")
    return number


def orbit_angle_degrees(orbit: int, orbit_index: int, skills_per_orbit: list[Any]) -> float:
    if isinstance(orbit, bool) or not isinstance(orbit, int):
        raise ImportErrorDetail("node orbit must be an integer")
    if isinstance(orbit_index, bool) or not isinstance(orbit_index, int):
        raise ImportErrorDetail("node orbitIndex must be an integer")
    if orbit < 0 or orbit >= len(skills_per_orbit):
        raise ImportErrorDetail(f"orbit index outside skillsPerOrbit: {orbit}")
    count = skills_per_orbit[orbit]
    if isinstance(count, bool) or not isinstance(count, int) or count < 1:
        raise ImportErrorDetail(f"invalid skillsPerOrbit value for orbit {orbit}")
    if orbit_index < 0 or orbit_index >= count:
        raise ImportErrorDetail(
            f"orbitIndex {orbit_index} outside orbit {orbit} with {count} positions"
        )
    if count == 16:
        return float(ANGLES_16[orbit_index])
    if count == 40:
        return float(ANGLES_40[orbit_index])
    return 360.0 * orbit_index / count


def _category(node: dict[str, Any]) -> str:
    ascendancy = node.get("ascendancyName")
    expansion = node.get("expansionJewel")
    if ascendancy and expansion:
        raise ImportErrorDetail("a node cannot belong to both an ascendancy and expansion jewel")
    if ascendancy:
        if not isinstance(ascendancy, str):
            raise ImportErrorDetail("ascendancyName must be a string")
        return "ascendancy/" + ascendancy
    if expansion:
        if not isinstance(expansion, dict):
            raise ImportErrorDetail("expansionJewel must be an object")
        return "expansion_jewels"
    return "standard_tree"


def _source_text_counts(nodes: dict[str, dict[str, Any]]) -> dict[str, int]:
    node_stats = [
        text for node in nodes.values()
        for text in _require_list(node.get("stats", []), "node.stats")
    ]
    mastery_stats = [
        text
        for node in nodes.values()
        for effect in _require_list(node.get("masteryEffects", []), "node.masteryEffects")
        for text in _require_list(
            _require_object(effect, "mastery effect").get("stats", []),
            "mastery effect.stats",
        )
    ]
    if any(not isinstance(text, str) for text in node_stats + mastery_stats):
        raise ImportErrorDetail("source stats must remain strings")
    return {
        "node_stats_lines": len(node_stats),
        "node_stats_unique_texts": len(set(node_stats)),
        "mastery_effect_stats_lines": len(mastery_stats),
        "mastery_effect_stats_unique_texts": len(set(mastery_stats)),
    }


def build_normalized(
    source: dict[str, Any],
    manifest: dict[str, Any],
    source_sha256: str = PINNED_SHA256,
    source_bytes: int = PINNED_BYTES,
) -> dict[str, Any]:
    source = _require_object(source, "source data")
    if source.get("tree") != "Default":
        raise ImportErrorDetail("expected the official Default passive tree")

    nodes = _require_object(source.get("nodes"), "nodes")
    groups = _require_object(source.get("groups"), "groups")
    classes = _require_list(source.get("classes"), "classes")
    constants = _require_object(source.get("constants"), "constants")
    skills_per_orbit = _require_list(
        constants.get("skillsPerOrbit"), "constants.skillsPerOrbit"
    )
    orbit_radii = _require_list(constants.get("orbitRadii"), "constants.orbitRadii")
    if not nodes or not groups:
        raise ImportErrorDetail("source nodes and groups must not be empty")

    node_ids = set(nodes)
    if any(not isinstance(node_id, str) or not node_id for node_id in node_ids):
        raise ImportErrorDetail("node dictionary keys must be non-empty strings")
    if "root" not in nodes:
        raise ImportErrorDetail("source tree is missing its root node")

    for node_id, node_value in nodes.items():
        node = _require_object(node_value, f"node {node_id}")
        for field in ("in", "out"):
            refs = _require_list(node.get(field, []), f"node {node_id}.{field}")
            if any(str(ref) not in node_ids for ref in refs):
                raise ImportErrorDetail(f"node {node_id}.{field} contains an unknown ID")
        group_id = node.get("group")
        if node_id == "root":
            continue
        if group_id is None:
            if node.get("in") or node.get("out"):
                raise ImportErrorDetail(
                    f"unplaced source definition {node_id} unexpectedly has graph edges"
                )
            continue
        group = groups.get(str(group_id))
        if not isinstance(group, dict):
            raise ImportErrorDetail(f"node {node_id} refers to missing group {group_id}")
        group_nodes = _require_list(group.get("nodes", []), f"group {group_id}.nodes")
        if node_id not in {str(value) for value in group_nodes}:
            raise ImportErrorDetail(f"node {node_id} is absent from its source group")
        # The node's orbit is authoritative for its position. Preserve the
        # source group's separate `orbits` list verbatim; this export has 48
        # nodes whose orbit is intentionally absent from that list.

    # Confirm source group membership in both directions. Groups are kept whole:
    # some groups intentionally mix ordinary nodes and expansion-jewel nodes.
    for group_id, group_value in groups.items():
        group = _require_object(group_value, f"group {group_id}")
        member_ids = _require_list(group.get("nodes", []), f"group {group_id}.nodes")
        seen_members: set[str] = set()
        for raw_member in member_ids:
            member_id = str(raw_member)
            if member_id not in node_ids:
                raise ImportErrorDetail(f"group {group_id} contains unknown node {member_id}")
            if member_id in seen_members:
                raise ImportErrorDetail(f"group {group_id} repeats node {member_id}")
            seen_members.add(member_id)
            if member_id == "root" or str(nodes[member_id].get("group")) != str(group_id):
                raise ImportErrorDetail(
                    f"group {group_id} membership disagrees with node {member_id}"
                )

    for node_id, node in nodes.items():
        if node_id != "root" and node.get("group") is not None:
            group = groups[str(node["group"])]
            if node_id not in {str(value) for value in group.get("nodes", [])}:
                raise ImportErrorDetail(f"node {node_id} is missing from group membership")

    category_by_id = {node_id: _category(node) for node_id, node in nodes.items()}
    categories = set(category_by_id.values())
    standard_ids = sorted_ids(
        node_id for node_id, category in category_by_id.items()
        if category == "standard_tree"
    )
    ascendancy_ids: dict[str, list[str]] = {}
    for category in categories:
        if category.startswith("ascendancy/"):
            ascendancy = category.removeprefix("ascendancy/")
            ascendancy_ids[ascendancy] = sorted_ids(
                node_id for node_id, node_category in category_by_id.items()
                if node_category == category
            )
    ascendancy_ids = {
        name: ascendancy_ids[name] for name in sorted(ascendancy_ids)
    }
    expansion_ids = sorted_ids(
        node_id for node_id, category in category_by_id.items()
        if category == "expansion_jewels"
    )

    positions: dict[str, dict[str, Any]] = {}
    for node_id in sorted_ids(nodes):
        node = nodes[node_id]
        if node_id == "root" or node.get("group") is None:
            continue
        group_id = str(node["group"])
        group = groups[group_id]
        orbit = node["orbit"]
        orbit_index = node["orbitIndex"]
        angle_degrees = orbit_angle_degrees(orbit, orbit_index, skills_per_orbit)
        if orbit >= len(orbit_radii):
            raise ImportErrorDetail(f"node {node_id} orbit has no source radius")
        center_x = _finite_number(group.get("x"), f"group {group_id}.x")
        center_y = _finite_number(group.get("y"), f"group {group_id}.y")
        radius = _finite_number(orbit_radii[orbit], f"orbitRadii[{orbit}]")
        radians = math.radians(angle_degrees)
        positions[node_id] = {
            "group_id": group_id,
            "orbit": orbit,
            "orbit_index": orbit_index,
            "angle_degrees": angle_degrees,
            "radius": radius,
            "x": round(center_x + math.sin(radians) * radius, 6),
            "y": round(center_y - math.cos(radians) * radius, 6),
        }

    outgoing: set[tuple[str, str]] = set()
    incoming: set[tuple[str, str]] = set()
    for node_id, node in nodes.items():
        for target_id in node.get("out", []):
            outgoing.add((node_id, str(target_id)))
        for source_id in node.get("in", []):
            incoming.add((str(source_id), node_id))
    pair_set = {
        tuple(sorted((first, second), key=node_sort_key))
        for first, second in outgoing | incoming
    }
    ordered_pairs = sorted(
        pair_set,
        key=lambda pair: (node_sort_key(pair[0]), node_sort_key(pair[1])),
    )
    out_sources_by_pair: dict[tuple[str, str], set[str]] = defaultdict(set)
    in_nodes_by_pair: dict[tuple[str, str], set[str]] = defaultdict(set)
    for source_id, target_id in outgoing:
        pair = tuple(sorted((source_id, target_id), key=node_sort_key))
        out_sources_by_pair[pair].add(source_id)
    for source_id, target_id in incoming:
        pair = tuple(sorted((source_id, target_id), key=node_sort_key))
        in_nodes_by_pair[pair].add(target_id)
    edges: list[dict[str, Any]] = []
    for edge_index, (first, second) in enumerate(ordered_pairs):
        category_a = category_by_id[first]
        category_b = category_by_id[second]
        pair = (first, second)
        out_from = sorted_ids(out_sources_by_pair.get(pair, set()))
        in_at = sorted_ids(in_nodes_by_pair.get(pair, set()))
        edges.append({
            "id": f"E{edge_index:04d}",
            "a": first,
            "b": second,
            "source_out_from": out_from,
            "source_in_at": in_at,
            "partition_a": category_a,
            "partition_b": category_b,
            "crosses_partition": category_a != category_b,
        })
    def partition_edges(ids: set[str]) -> tuple[list[str], list[str]]:
        internal: list[str] = []
        boundary: list[str] = []
        for edge in edges:
            has_a = edge["a"] in ids
            has_b = edge["b"] in ids
            if has_a and has_b:
                internal.append(edge["id"])
            elif has_a or has_b:
                boundary.append(edge["id"])
        return internal, boundary

    root = nodes["root"]
    if not isinstance(root, dict):
        raise ImportErrorDetail("root record must be an object")

    class_start_nodes = []
    starts_by_index: dict[int, str] = {}
    for node_id, node in nodes.items():
        if "classStartIndex" not in node:
            continue
        index = node["classStartIndex"]
        if isinstance(index, bool) or not isinstance(index, int):
            raise ImportErrorDetail(f"node {node_id}.classStartIndex must be an integer")
        if index < 0 or index >= len(classes) or index in starts_by_index:
            raise ImportErrorDetail(f"invalid or repeated class start index: {index}")
        starts_by_index[index] = node_id
        class_start_nodes.append({
            "node_id": node_id,
            "class_index": index,
            "class_name": _require_object(classes[index], f"class {index}").get("name"),
        })
    class_start_nodes.sort(key=lambda start: start["class_index"])
    if len(class_start_nodes) != len(classes):
        raise ImportErrorDetail(
            f"expected one class-start node per class, found {len(class_start_nodes)}"
        )

    raw_jewel_slots = _require_list(source.get("jewelSlots"), "jewelSlots")
    jewel_slot_ids = [str(value) for value in raw_jewel_slots]
    if len(jewel_slot_ids) != len(set(jewel_slot_ids)):
        raise ImportErrorDetail("jewelSlots contains duplicate IDs")
    socket_ids = {
        node_id for node_id, node in nodes.items() if node.get("isJewelSocket") is True
    }
    if set(jewel_slot_ids) != socket_ids:
        raise ImportErrorDetail("jewelSlots and isJewelSocket node IDs do not match")
    standard_socket_ids = sorted_ids(socket_ids.intersection(standard_ids))
    expansion_socket_ids = sorted_ids(socket_ids.intersection(expansion_ids))

    standard_set = set(standard_ids)
    standard_internal, standard_boundary = partition_edges(standard_set)
    standard_positioned_ids = sorted_ids(standard_set.intersection(positions))
    standard_unpositioned_ids = sorted_ids(standard_set - set(positions))
    # This is the only adjacency intended for a future default standard-tree
    # allocator. It excludes the non-allocatable logical root, every edge that
    # crosses a subtree partition, and any endpoint without a source position.
    allocation_node_ids = sorted_ids(
        node_id for node_id in standard_positioned_ids if node_id != "root"
    )
    allocation_node_set = set(allocation_node_ids)
    allocation_edges = [
        edge for edge in edges
        if edge["a"] in allocation_node_set
        and edge["b"] in allocation_node_set
        and not edge["crosses_partition"]
        and edge["a"] != "root"
        and edge["b"] != "root"
    ]
    allocation_edge_ids = [edge["id"] for edge in allocation_edges]
    allocation_adjacency: dict[str, list[str]] = {
        node_id: [] for node_id in allocation_node_ids
    }
    for edge in allocation_edges:
        allocation_adjacency[edge["a"]].append(edge["b"])
        allocation_adjacency[edge["b"]].append(edge["a"])
    allocation_adjacency = {
        node_id: sorted_ids(neighbors)
        for node_id, neighbors in allocation_adjacency.items()
    }
    allocation_start_ids = [start["node_id"] for start in class_start_nodes]
    if any(start_id not in allocation_node_set for start_id in allocation_start_ids):
        raise ImportErrorDetail("a class start is missing from the default allocation graph")
    if "root" in allocation_adjacency or any(
        "root" in neighbors for neighbors in allocation_adjacency.values()
    ):
        raise ImportErrorDetail("logical root leaked into the default allocation graph")
    allocation_edge_id_set = set(allocation_edge_ids)
    root_edge_ids = [edge["id"] for edge in edges if "root" in (edge["a"], edge["b"])]
    cross_partition_edge_ids = [edge["id"] for edge in edges if edge["crosses_partition"]]
    unpositioned_edge_ids = [
        edge["id"] for edge in edges
        if edge["a"] not in positions or edge["b"] not in positions
    ]
    excluded_allocation_edge_ids = [
        edge["id"] for edge in edges if edge["id"] not in allocation_edge_id_set
    ]

    special_ascendancies: dict[str, dict[str, Any]] = {}
    for name, ids in ascendancy_ids.items():
        ids_set = set(ids)
        internal, boundary = partition_edges(ids_set)
        special_ascendancies[name] = {
            "node_ids": ids,
            "positioned_node_ids": sorted_ids(ids_set.intersection(positions)),
            "jewel_socket_ids": sorted_ids(
                node_id for node_id in ids if nodes[node_id].get("isJewelSocket") is True
            ),
            "start_node_ids": sorted_ids(
                node_id for node_id in ids if nodes[node_id].get("isAscendancyStart") is True
            ),
            "group_ids": sorted_ids(
                {str(nodes[node_id]["group"]) for node_id in ids if "group" in nodes[node_id]}
            ),
            "internal_edge_ids": internal,
            "boundary_edge_ids": boundary,
            "bloodline_node_count": sum(
                nodes[node_id].get("isBloodline") is True for node_id in ids
            ),
        }
    expansion_set = set(expansion_ids)
    expansion_internal, expansion_boundary = partition_edges(expansion_set)
    ascendancy_socket_count = sum(
        len(details["jewel_socket_ids"]) for details in special_ascendancies.values()
    )
    detached_standard_ids = sorted_ids(
        node_id for node_id in standard_ids if node_id != "root" and "group" not in nodes[node_id]
    )

    flag_names = sorted({
        field
        for node in nodes.values()
        for field in node
        if field.startswith("is")
    })
    flag_counts = {
        flag: sum(node.get(flag) is True for node in nodes.values())
        for flag in flag_names
    }
    mastery_nodes = [node for node in nodes.values() if node.get("isMastery") is True]
    mastery_option_count = sum(
        len(_require_list(node.get("masteryEffects", []), "masteryEffects"))
        for node in mastery_nodes
    )
    multi_choice_count = sum(node.get("isMultipleChoice") is True for node in nodes.values())
    multi_choice_option_count = sum(
        node.get("isMultipleChoiceOption") is True for node in nodes.values()
    )
    alternate_ascendancies = _require_list(
        source.get("alternate_ascendancies"), "alternate_ascendancies"
    )
    source_out_only = len(outgoing - incoming)
    source_in_only = len(incoming - outgoing)
    boundary_edge_count = sum(edge["crosses_partition"] for edge in edges)
    node_orbit_not_listed_in_group_orbits = sum(
        1
        for node_id, node in nodes.items()
        if node_id != "root"
        and node.get("group") is not None
        and node.get("orbit") not in groups[str(node["group"])].get("orbits", [])
    )
    text_counts = _source_text_counts(nodes)
    coverage = {
        "source_nodes": len(nodes),
        "standard_tree_node_records": len(standard_ids),
        "standard_tree_positioned_nodes": len(standard_positioned_ids),
        "standard_tree_unpositioned_nodes": len(standard_unpositioned_ids),
        "detached_standard_definitions_without_group_or_edges": len(detached_standard_ids),
        "logical_root_nodes": 1,
        "ascendancy_names": len(special_ascendancies),
        "ascendancy_node_records": sum(len(ids) for ids in ascendancy_ids.values()),
        "expansion_jewel_node_records": len(expansion_ids),
        "source_groups": len(groups),
        "groups_mixing_standard_and_expansion_nodes": sum(
            1 for group in groups.values()
            if {
                "standard_tree",
                "expansion_jewels",
            }.issubset({
                category_by_id[str(node_id)]
                for node_id in group.get("nodes", [])
            })
        ),
        "nodes_orbit_absent_from_group_orbits_list": node_orbit_not_listed_in_group_orbits,
        "nodes_with_derived_positions": len(positions),
        "source_out_links": sum(len(node.get("out", [])) for node in nodes.values()),
        "source_in_links": sum(len(node.get("in", [])) for node in nodes.values()),
        "unique_undirected_edges": len(edges),
        "source_out_links_without_matching_in_entry": source_out_only,
        "source_in_links_without_matching_out_entry": source_in_only,
        "edges_crossing_partitions": boundary_edge_count,
        "default_allocation_nodes": len(allocation_node_ids),
        "default_allocation_edges": len(allocation_edge_ids),
        "default_allocation_root_edges_excluded": len(root_edge_ids),
        "default_allocation_cross_partition_edges_excluded": len(cross_partition_edge_ids),
        "default_allocation_unpositioned_edges_excluded": len(unpositioned_edge_ids),
        "default_allocation_source_edges_excluded": len(excluded_allocation_edge_ids),
        "classes": len(classes),
        "class_start_nodes": len(class_start_nodes),
        "alternate_ascendancies": len(alternate_ascendancies),
        "jewel_slots": len(jewel_slot_ids),
        "standard_tree_jewel_slots": len(standard_socket_ids),
        "ascendancy_jewel_sockets": ascendancy_socket_count,
        "expansion_jewel_sockets": len(expansion_socket_ids),
        "mastery_nodes": len(mastery_nodes),
        "mastery_effect_options": mastery_option_count,
        "multiple_choice_nodes": multi_choice_count,
        "multiple_choice_option_nodes": multi_choice_option_count,
        "source_node_flag_counts": flag_counts,
        **text_counts,
    }

    if sum(len(ids) for ids in ascendancy_ids.values()) != sum(
        category.startswith("ascendancy/") for category in category_by_id.values()
    ):
        raise ImportErrorDetail("ascendancy partition count mismatch")
    all_partition_ids = (
        set(standard_ids)
        | {node_id for ids in ascendancy_ids.values() for node_id in ids}
        | set(expansion_ids)
    )
    if all_partition_ids != node_ids:
        raise ImportErrorDetail("partition node IDs do not cover the source exactly once")

    out_edge_pairs = {
        tuple(sorted((node_id, str(target_id)), key=node_sort_key))
        for node_id, node in nodes.items()
        for target_id in node.get("out", [])
    }
    in_edge_pairs = {
        tuple(sorted((str(source_id), node_id), key=node_sort_key))
        for node_id, node in nodes.items()
        for source_id in node.get("in", [])
    }
    if { (edge["a"], edge["b"]) for edge in edges } != out_edge_pairs | in_edge_pairs:
        raise ImportErrorDetail("normalized edge list does not cover source in/out links")

    output = {
        "schema_version": SCHEMA_VERSION,
        "provenance": {
            "repository": manifest["source"]["repository"],
            "version": manifest["source"]["version"],
            "commit": manifest["source"]["commit"],
            "data_file": manifest["source"]["data_file"],
            "data_url": manifest["source"]["data_url"],
            "data_sha256": source_sha256,
            "data_bytes": source_bytes,
            "rights_review": manifest["rights_review"],
            "omitted_source_root_fields": list(OMITTED_ROOT_FIELDS),
            "no_official_art_resources_copied": True,
        },
        "tree": source["tree"],
        "classes": classes,
        "alternate_ascendancies": alternate_ascendancies,
        "points": source.get("points", {}),
        "bounds": {
            field: source[field]
            for field in ("min_x", "min_y", "max_x", "max_y")
            if field in source
        },
        "image_zoom_levels": source.get("imageZoomLevels", []),
        "constants": constants,
        "jewel_slots_source": raw_jewel_slots,
        "jewel_slot_ids": jewel_slot_ids,
        # These records are copied without rewriting source keys, values, strings,
        # in/out order, stats or mastery option order.
        "groups": groups,
        "node_records": nodes,
        "positions": positions,
        "edges": edges,
        "standard_tree": {
            "root_id": "root",
            "node_ids": standard_ids,
            "positioned_node_ids": standard_positioned_ids,
            "unpositioned_node_ids": standard_unpositioned_ids,
            "detached_definition_ids": detached_standard_ids,
            "class_start_nodes": class_start_nodes,
            "jewel_slot_ids": standard_socket_ids,
            "group_ids": sorted_ids(
                {
                    str(nodes[node_id]["group"])
                    for node_id in standard_ids
                    if "group" in nodes[node_id]
                    and str(nodes[node_id]["group"]) in groups
                }
            ),
            "internal_edge_ids": standard_internal,
            "boundary_edge_ids": standard_boundary,
            "default_allocation_graph": {
                "node_ids": allocation_node_ids,
                "class_start_ids": allocation_start_ids,
                "edge_ids": allocation_edge_ids,
                "adjacency": allocation_adjacency,
                "excluded_root_edge_ids": root_edge_ids,
                "excluded_cross_partition_edge_ids": cross_partition_edge_ids,
                "excluded_unpositioned_edge_ids": unpositioned_edge_ids,
                "excluded_source_edge_ids": excluded_allocation_edge_ids,
                "edge_filter": {
                    "partition": "standard_tree",
                    "exclude_logical_root_id": "root",
                    "exclude_cross_partition_edges": True,
                    "exclude_edges_with_unpositioned_endpoints": True,
                    "edge_model": "undirected adjacency derived from the complete source edge ledger",
                },
            },
        },
        "special_subtrees": {
            "ascendancies": special_ascendancies,
            "expansion_jewels": {
                "node_ids": expansion_ids,
                "positioned_node_ids": sorted_ids(expansion_set.intersection(positions)),
                "jewel_socket_ids": expansion_socket_ids,
                "group_ids": sorted_ids(
                    {str(nodes[node_id]["group"]) for node_id in expansion_ids if "group" in nodes[node_id]}
                ),
                "internal_edge_ids": expansion_internal,
                "boundary_edge_ids": expansion_boundary,
            },
        },
        "layout_rule": {
            "source_group_center": ["groups[node.group].x", "groups[node.group].y"],
            "orbit_radius": "constants.orbitRadii[node.orbit]",
            "angle_degrees_by_index": {
                "16_positions": list(ANGLES_16),
                "40_positions": list(ANGLES_40),
                "otherwise": "360 * orbitIndex / skillsPerOrbit[orbit]",
            },
            "coordinate_formula": {
                "x": "group.x + sin(radians(angle_degrees)) * orbitRadii[orbit]",
                "y": "group.y - cos(radians(angle_degrees)) * orbitRadii[orbit]",
                "origin": "group center",
                "zero_degrees": "up",
            },
            "derived_coordinate_decimal_places": 6,
        },
        "coverage": coverage,
    }
    return output


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(content)
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()


def fetch_pinned_source(manifest: dict[str, Any], destination: Path = DEFAULT_SOURCE) -> None:
    url = manifest["source"]["data_url"]
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "godot-game-passive-import/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw_bytes = response.read(PINNED_BYTES + 1)
    verify_source_bytes(raw_bytes, manifest)
    _atomic_write(destination, raw_bytes)


def print_report(output: dict[str, Any], raw_digest: str, mode: str) -> None:
    print(
        f"{mode}: PoE1 {output['provenance']['version']} "
        f"commit {output['provenance']['commit']}"
    )
    print(f"source sha256: {raw_digest}")
    for key, value in output["coverage"].items():
        if isinstance(value, dict):
            continue
        print(f"{key}: {value}")
    print(
        "note: imported source coverage describes retained data; it does not "
        "mean source modifiers are implemented by game mechanics."
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--write", action="store_true", help="write normalized_tree.json")
    action.add_argument("--check", action="store_true", help="compare regeneration with committed output")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="pinned raw data.json")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="normalized JSON path")
    parser.add_argument(
        "--fetch-source",
        action="store_true",
        help="download the pinned URL; only replace raw data after SHA-256 verification",
    )
    parser.add_argument("--stats", action="store_true", help="print retained-data coverage counts")
    args = parser.parse_args(argv)

    try:
        manifest = load_manifest()
        if args.fetch_source:
            fetch_pinned_source(manifest, args.source)
        raw_bytes = args.source.read_bytes()
        raw_digest = verify_source_bytes(raw_bytes, manifest)
        source = parse_json_bytes(raw_bytes, str(args.source))
        output = build_normalized(source, manifest, raw_digest, len(raw_bytes))
        expected_bytes = canonical_json_bytes(output)
        if args.write:
            _atomic_write(args.output, expected_bytes)
            print_report(output, raw_digest, "wrote")
        else:
            if not args.output.exists():
                raise ImportErrorDetail(
                    f"normalized output is missing: {args.output}; run with --write"
                )
            actual_bytes = args.output.read_bytes()
            if actual_bytes != expected_bytes:
                raise ImportErrorDetail(
                    f"normalized output is stale or non-deterministic: {args.output}; "
                    "run with --write and review the diff"
                )
            print_report(output, raw_digest, "verified")
        if args.stats:
            print("coverage-json:")
            print(json.dumps(output["coverage"], ensure_ascii=False, sort_keys=True, indent=2))
        return 0
    except (OSError, ImportErrorDetail, KeyError, TypeError) as exc:
        print(f"passive import failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
