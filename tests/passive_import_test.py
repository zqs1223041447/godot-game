"""Focused regression tests for the offline PoE passive data importer."""
from __future__ import annotations

import math
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.passive_import import import_tree as importer  # noqa: E402


class PassiveImportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw_bytes = importer.DEFAULT_SOURCE.read_bytes()
        cls.manifest = importer.load_manifest()
        cls.digest = importer.verify_source_bytes(cls.raw_bytes, cls.manifest)
        cls.source = importer.parse_json_bytes(cls.raw_bytes, "pinned data.json")
        cls.normalized = importer.build_normalized(
            cls.source, cls.manifest, cls.digest, len(cls.raw_bytes)
        )

    def test_pinned_file_and_complete_node_partition(self) -> None:
        self.assertEqual(self.digest, importer.PINNED_SHA256)
        self.assertEqual(len(self.raw_bytes), importer.PINNED_BYTES)
        self.assertEqual(self.normalized["tree"], "Default")
        self.assertEqual(len(self.normalized["node_records"]), 3390)
        self.assertEqual(len(self.normalized["standard_tree"]["node_ids"]), 2790)

        categories = [
            set(self.normalized["standard_tree"]["node_ids"]),
            set(self.normalized["special_subtrees"]["expansion_jewels"]["node_ids"]),
        ]
        categories.extend(
            set(details["node_ids"])
            for details in self.normalized["special_subtrees"]["ascendancies"].values()
        )
        flattened = [node_id for category in categories for node_id in category]
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertEqual(set(flattened), set(self.source["nodes"]))
        self.assertEqual(len(self.normalized["special_subtrees"]["ascendancies"]), 37)
        self.assertEqual(
            self.normalized["coverage"]["ascendancy_node_records"], 558
        )
        self.assertEqual(
            self.normalized["coverage"]["expansion_jewel_node_records"], 42
        )
        self.assertEqual(self.normalized["classes"], self.source["classes"])
        self.assertEqual(
            self.normalized["alternate_ascendancies"],
            self.source["alternate_ascendancies"],
        )
        root_out = set(self.source["nodes"]["root"]["out"])
        starts = self.normalized["standard_tree"]["class_start_nodes"]
        self.assertEqual(len(starts), 7)
        for start in starts:
            node = self.source["nodes"][start["node_id"]]
            self.assertEqual(node["classStartIndex"], start["class_index"])
            self.assertEqual(
                start["class_name"], self.source["classes"][start["class_index"]]["name"]
            )
            self.assertIn(start["node_id"], root_out)

    def test_unplaced_records_and_group_data_are_retained(self) -> None:
        standard = self.normalized["standard_tree"]
        self.assertEqual(len(self.normalized["groups"]), 797)
        self.assertEqual(self.normalized["groups"], self.source["groups"])
        self.assertEqual(self.normalized["node_records"], self.source["nodes"])
        self.assertEqual(len(standard["positioned_node_ids"]), 2387)
        self.assertEqual(len(standard["unpositioned_node_ids"]), 403)
        self.assertEqual(len(standard["detached_definition_ids"]), 402)
        self.assertIn("root", standard["unpositioned_node_ids"])
        self.assertEqual(
            self.normalized["coverage"]["groups_mixing_standard_and_expansion_nodes"],
            30,
        )
        self.assertEqual(
            self.normalized["coverage"]["nodes_orbit_absent_from_group_orbits_list"],
            48,
        )

    def test_source_edges_and_partition_boundaries_are_complete(self) -> None:
        edges = self.normalized["edges"]
        raw_nodes = self.source["nodes"]
        self.assertEqual(len(edges), 3382)
        self.assertEqual(
            self.normalized["coverage"]["source_out_links"], 3382
        )
        self.assertEqual(
            self.normalized["coverage"]["source_in_links"], 3359
        )
        self.assertEqual(
            self.normalized["coverage"]["source_out_links_without_matching_in_entry"],
            23,
        )
        out_only = {
            (node_id, str(target_id))
            for node_id, node in raw_nodes.items()
            for target_id in node.get("out", [])
            if node_id not in raw_nodes[str(target_id)].get("in", [])
        }
        self.assertEqual(len(out_only), 23)
        self.assertEqual({node_id for node_id, _ in out_only}, {"root"})
        self.assertEqual(
            self.normalized["coverage"]["source_in_links_without_matching_out_entry"],
            0,
        )
        self.assertEqual(
            self.normalized["coverage"]["edges_crossing_partitions"], 127
        )

        edge_ids = {edge["id"] for edge in edges}
        self.assertEqual(len(edge_ids), len(edges))
        for edge in edges:
            a, b = edge["a"], edge["b"]
            self.assertIn(a, raw_nodes)
            self.assertIn(b, raw_nodes)
            expected_out = []
            expected_in = []
            for candidate, neighbor in ((a, b), (b, a)):
                if neighbor in raw_nodes[candidate].get("out", []):
                    expected_out.append(candidate)
                if neighbor in raw_nodes[candidate].get("in", []):
                    expected_in.append(candidate)
            self.assertEqual(edge["source_out_from"], sorted(expected_out, key=importer.node_sort_key))
            self.assertEqual(edge["source_in_at"], sorted(expected_in, key=importer.node_sort_key))

        partitions = [
            set(self.normalized["standard_tree"]["node_ids"]),
            set(self.normalized["special_subtrees"]["expansion_jewels"]["node_ids"]),
        ]
        partitions.extend(
            set(details["node_ids"])
            for details in self.normalized["special_subtrees"]["ascendancies"].values()
        )
        for partition in partitions:
            expected_internal = {
                edge["id"] for edge in edges
                if edge["a"] in partition and edge["b"] in partition
            }
            expected_boundary = {
                edge["id"] for edge in edges
                if (edge["a"] in partition) != (edge["b"] in partition)
            }
            # Each category-specific record is checked below via its node set.
            # The standard tree is the only top-level record in this loop without
            # a direct reference; its edge lists are checked in the next checks.
            if partition == set(self.normalized["standard_tree"]["node_ids"]):
                record = self.normalized["standard_tree"]
            elif partition == set(self.normalized["special_subtrees"]["expansion_jewels"]["node_ids"]):
                record = self.normalized["special_subtrees"]["expansion_jewels"]
            else:
                record = next(
                    details
                    for details in self.normalized["special_subtrees"]["ascendancies"].values()
                    if set(details["node_ids"]) == partition
                )
            self.assertEqual(set(record["internal_edge_ids"]), expected_internal)
            self.assertEqual(set(record["boundary_edge_ids"]), expected_boundary)
            self.assertTrue(set(record["internal_edge_ids"]).issubset(edge_ids))
            self.assertTrue(set(record["boundary_edge_ids"]).issubset(edge_ids))

    def test_default_allocation_graph_excludes_root_and_cross_partition_edges(self) -> None:
        standard = self.normalized["standard_tree"]
        allocation = standard["default_allocation_graph"]
        source_nodes = self.source["nodes"]
        source_groups = self.source["groups"]
        source_standard_positioned = {
            node_id
            for node_id, node in source_nodes.items()
            if node_id != "root"
            and not node.get("ascendancyName")
            and not node.get("expansionJewel")
            and "group" in node
            and str(node["group"]) in source_groups
        }
        self.assertEqual(len(source_standard_positioned), 2387)
        self.assertEqual(set(allocation["node_ids"]), source_standard_positioned)
        self.assertNotIn("root", allocation["node_ids"])
        self.assertEqual(len(allocation["node_ids"]), 2387)
        self.assertEqual(set(allocation["adjacency"]), source_standard_positioned)
        coverage = self.normalized["coverage"]
        self.assertEqual(coverage["default_allocation_nodes"], 2387)
        self.assertEqual(coverage["default_allocation_edges"], 2697)
        self.assertEqual(coverage["default_allocation_root_edges_excluded"], 23)
        self.assertEqual(
            coverage["default_allocation_cross_partition_edges_excluded"], 127
        )
        self.assertEqual(coverage["default_allocation_unpositioned_edges_excluded"], 23)
        self.assertEqual(coverage["default_allocation_source_edges_excluded"], 685)

        all_edges = self.normalized["edges"]
        expected_allocation_edges = {
            edge["id"]
            for edge in all_edges
            if edge["a"] in source_standard_positioned
            and edge["b"] in source_standard_positioned
            and not edge["crosses_partition"]
        }
        self.assertEqual(set(allocation["edge_ids"]), expected_allocation_edges)
        self.assertEqual(len(allocation["edge_ids"]), 2697)
        edge_by_id = {edge["id"]: edge for edge in all_edges}
        expected_adjacency = {node_id: set() for node_id in source_standard_positioned}
        for edge_id in allocation["edge_ids"]:
            edge = edge_by_id[edge_id]
            self.assertNotEqual(edge["a"], "root")
            self.assertNotEqual(edge["b"], "root")
            self.assertFalse(edge["crosses_partition"])
            self.assertIn(edge["a"], source_standard_positioned)
            self.assertIn(edge["b"], source_standard_positioned)
            expected_adjacency[edge["a"]].add(edge["b"])
            expected_adjacency[edge["b"]].add(edge["a"])
        for node_id, neighbors in allocation["adjacency"].items():
            self.assertNotIn("root", neighbors)
            self.assertEqual(set(neighbors), expected_adjacency[node_id])
            for neighbor in neighbors:
                self.assertIn(node_id, allocation["adjacency"][neighbor])

        expected_root_edges = {
            edge["id"] for edge in all_edges if "root" in (edge["a"], edge["b"])
        }
        expected_cross_edges = {
            edge["id"] for edge in all_edges if edge["crosses_partition"]
        }
        self.assertEqual(set(allocation["excluded_root_edge_ids"]), expected_root_edges)
        self.assertEqual(len(expected_root_edges), 23)
        self.assertEqual(
            set(allocation["excluded_cross_partition_edge_ids"]), expected_cross_edges
        )
        self.assertEqual(len(expected_cross_edges), 127)
        self.assertTrue(expected_root_edges.isdisjoint(allocation["edge_ids"]))
        self.assertTrue(expected_cross_edges.isdisjoint(allocation["edge_ids"]))
        self.assertEqual(
            set(allocation["excluded_source_edge_ids"]),
            {edge["id"] for edge in all_edges} - expected_allocation_edges,
        )
        self.assertEqual(len(allocation["excluded_source_edge_ids"]), 685)

        expected_start_ids = {
            node_id for node_id, node in source_nodes.items()
            if "classStartIndex" in node
        }
        self.assertEqual(set(allocation["class_start_ids"]), expected_start_ids)
        self.assertEqual(len(expected_start_ids), 7)
        start_to_start_edges = {
            frozenset((edge["a"], edge["b"]))
            for edge in all_edges
            if edge["a"] in expected_start_ids and edge["b"] in expected_start_ids
        }
        self.assertEqual(start_to_start_edges, set())
        self.assertEqual(
            allocation["edge_filter"]["exclude_logical_root_id"], "root"
        )
        self.assertTrue(allocation["edge_filter"]["exclude_cross_partition_edges"])
        self.assertTrue(
            allocation["edge_filter"]["exclude_edges_with_unpositioned_endpoints"]
        )

    def test_source_orbit_angles_and_node_positions(self) -> None:
        constants = self.normalized["constants"]
        skills_per_orbit = constants["skillsPerOrbit"]
        self.assertEqual(importer.orbit_angle_degrees(2, 1, skills_per_orbit), 30)
        self.assertEqual(importer.orbit_angle_degrees(2, 2, skills_per_orbit), 45)
        self.assertEqual(importer.orbit_angle_degrees(4, 1, skills_per_orbit), 10)
        self.assertEqual(importer.orbit_angle_degrees(4, 2, skills_per_orbit), 20)
        self.assertEqual(importer.orbit_angle_degrees(5, 7, skills_per_orbit), 35)

        # Frozen samples distinguish the special 16- and 40-position tables from
        # a uniform distribution and check the official tree x/y orientation.
        samples = {
            "655": (30.0, 8084.21, 2441.413885),
            "32024": (20.0, 164.560931, -4964.578462),
            "21075": (35.0, 375.652601, -5043.588653),
        }
        for node_id, (angle, expected_x, expected_y) in samples.items():
            position = self.normalized["positions"][node_id]
            self.assertEqual(position["angle_degrees"], angle)
            self.assertEqual(position["x"], expected_x)
            self.assertEqual(position["y"], expected_y)

        self.assertEqual(len(self.normalized["positions"]), 2987)
        for node_id, position in self.normalized["positions"].items():
            source_node = self.source["nodes"][node_id]
            group = self.source["groups"][str(source_node["group"])]
            radius = self.source["constants"]["orbitRadii"][source_node["orbit"]]
            angle = math.radians(position["angle_degrees"])
            self.assertEqual(
                position["x"],
                round(group["x"] + math.sin(angle) * radius, 6),
            )
            self.assertEqual(
                position["y"],
                round(group["y"] - math.cos(angle) * radius, 6),
            )

    def test_mastery_choices_stats_and_jewel_slots_are_verbatim(self) -> None:
        nodes = self.normalized["node_records"]
        mastery_nodes = {
            node_id: node
            for node_id, node in nodes.items()
            if node.get("isMastery") is True
        }
        self.assertEqual(len(mastery_nodes), 353)
        self.assertEqual(sum(len(node.get("masteryEffects", [])) for node in mastery_nodes.values()), 1837)
        for node_id, node in mastery_nodes.items():
            self.assertEqual(node, self.source["nodes"][node_id])

        self.assertEqual(
            sum(node.get("isMultipleChoice") is True for node in nodes.values()), 17
        )
        self.assertEqual(
            sum(node.get("isMultipleChoiceOption") is True for node in nodes.values()), 62
        )

        slot_ids = set(self.normalized["jewel_slot_ids"])
        self.assertEqual(
            self.normalized["jewel_slots_source"], self.source["jewelSlots"]
        )
        flagged_ids = {
            node_id for node_id, node in nodes.items()
            if node.get("isJewelSocket") is True
        }
        self.assertEqual(slot_ids, flagged_ids)
        self.assertEqual(len(slot_ids), 60)
        self.assertEqual(
            len(self.normalized["standard_tree"]["jewel_slot_ids"]), 15
        )
        asc_socket_ids = {
            node_id
            for details in self.normalized["special_subtrees"]["ascendancies"].values()
            for node_id in details["jewel_socket_ids"]
        }
        self.assertEqual(len(asc_socket_ids), 3)
        self.assertEqual(
            len(self.normalized["special_subtrees"]["expansion_jewels"]["jewel_socket_ids"]),
            42,
        )
        self.assertEqual(
            slot_ids,
            set(self.normalized["standard_tree"]["jewel_slot_ids"])
            | asc_socket_ids
            | set(self.normalized["special_subtrees"]["expansion_jewels"]["jewel_socket_ids"]),
        )
        coverage = self.normalized["coverage"]
        self.assertEqual(coverage["source_node_flag_counts"]["isKeystone"], 57)
        self.assertEqual(coverage["source_node_flag_counts"]["isNotable"], 997)
        self.assertEqual(coverage["source_node_flag_counts"]["isBloodline"], 147)
        self.assertEqual(coverage["source_node_flag_counts"]["isProxy"], 42)
        self.assertEqual(coverage["source_node_flag_counts"]["isBlighted"], 30)
        self.assertEqual(coverage["mastery_effect_stats_lines"], 2015)
        self.assertEqual(coverage["node_stats_lines"], 4966)

    def test_normalization_and_cli_check_are_deterministic(self) -> None:
        regenerated = importer.build_normalized(
            self.source, self.manifest, self.digest, len(self.raw_bytes)
        )
        first = importer.canonical_json_bytes(self.normalized)
        second = importer.canonical_json_bytes(regenerated)
        self.assertEqual(first, second)
        self.assertEqual(first, importer.DEFAULT_OUTPUT.read_bytes())

        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "passive_import" / "import_tree.py"),
                "--check",
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("verified:", result.stdout)
        self.assertIn("does not mean source modifiers are implemented", result.stdout)

    def test_hash_mismatch_is_rejected_without_trusting_the_pin(self) -> None:
        changed_same_size = self.raw_bytes[:-1] + b" "
        with self.assertRaisesRegex(importer.ImportErrorDetail, "SHA-256 mismatch"):
            importer.verify_source_bytes(changed_same_size, self.manifest)


if __name__ == "__main__":
    unittest.main()
