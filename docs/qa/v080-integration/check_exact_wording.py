"""Verify the nine approved text keys and splice only their F8 cache values."""
import ast
import copy
import hashlib
import json
import subprocess
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[3]
BASE = "33ed04b73edf3545b98339291df81b4c49f891cf"
QA = Path(__file__).resolve().parent
EXPECTED = {
    "5% increased Mana Cost of Skills": "技能的魔力消耗提高5%",
    "10% increased Mana Cost of Skills": "技能的魔力消耗提高10%",
    "30% increased Mana Regeneration Rate": "魔力再生速率提高30%",
    "Regenerate 10 Life per second": "每秒再生10点生命",
    "Regenerate 1.2% of Life per second": "每秒再生相当于最大生命1.2%的生命",
    "100% increased total Recovery per second from Life Leech": "生命偷取的每秒总回复速率提高100%",
    "100% increased total Recovery per second from Mana Leech": "魔力偷取的每秒总回复速率提高100%",
    "40% increased Maximum total Life Recovery per second from Leech": "生命偷取的每秒总回复上限提高40%",
    "50% increased Maximum total Mana Recovery per second from Leech": "魔力偷取的每秒总回复上限提高50%",
}


def baseline(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT)


def spans(text, start):
    decoder = json.JSONDecoder()
    pos = start + 1
    result = {}
    while True:
        while text[pos].isspace():
            pos += 1
        if text[pos] == "}":
            return result
        key, pos = decoder.raw_decode(text, pos)
        while text[pos].isspace():
            pos += 1
        assert text[pos] == ":"
        pos += 1
        while text[pos].isspace():
            pos += 1
        value_start = pos
        _, pos = decoder.raw_decode(text, pos)
        result[key] = (value_start, pos)
        while text[pos].isspace():
            pos += 1
        if text[pos] == ",":
            pos += 1
        else:
            assert text[pos] == "}"
            return result


def main():
    mapping_path = "data/passive_source/localization_zh_CN.json"
    old_mapping = json.loads(baseline(mapping_path))
    current = json.loads((ROOT / mapping_path).read_text())
    expected_mapping = copy.deepcopy(old_mapping)
    expected_mapping["lines"].update(EXPECTED)
    assert current == expected_mapping, "Only the nine approved line values may change"

    generator_path = "tools/passive_import/build_source_tree_zh.py"
    old_ast = ast.parse(baseline(generator_path))
    new_ast = ast.parse((ROOT / generator_path).read_text())
    def override_node(tree):
        return next(node for node in tree.body if isinstance(node, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == "SINGLE_LINE_OVERRIDES"
                            for t in node.targets))
    old_override = override_node(old_ast)
    new_override = override_node(new_ast)
    expected_overrides = ast.literal_eval(old_override.value)
    expected_overrides.update(EXPECTED)
    assert ast.literal_eval(new_override.value) == expected_overrides
    new_override.value = old_override.value
    assert ast.dump(new_ast) == ast.dump(old_ast), "No generator templates or logic may change"

    path = ROOT / "docs/reference/catalog.json"
    raw = baseline("docs/reference/catalog.json").decode()
    original = json.loads(raw)
    expected = copy.deepcopy(original)
    localized = expected["source_tree_localization"]
    for english, translated in EXPECTED.items():
        assert localized["lines"][english]["status"]["implemented"] is True
        localized["lines"][english]["text"] = translated
    changed_nodes = []
    for node_id, source in original["source_tree"]["nodes"].items():
        if not any(line in EXPECTED for line in source["stats"]):
            continue
        translated = "\\n".join(localized["lines"][line]["text"] for line in source["stats"])
        localized["nodes"][node_id]["stats"] = translated
        changed_nodes.append(node_id)
    # These nine exact lines have no mastery references. Do not infer new choices.
    for source in original["source_tree"]["nodes"].values():
        for choice in source["mastery_choices"]:
            assert not any(line in EXPECTED for line in choice.get("stats", []))
    replacements = []
    modified_paths = []
    def patch(before, after, start, end, key_path):
        if before == after:
            return
        if isinstance(before, dict):
            assert before.keys() == after.keys()
            offsets = spans(raw, start)
            for key in before:
                patch(before[key], after[key], *offsets[key], key_path + [key])
            return
        assert isinstance(before, str) and isinstance(after, str)
        replacements.append((start, end, json.dumps(after, ensure_ascii=False)))
        modified_paths.append(key_path)
    patch(original, expected, 0, len(raw.rstrip()), [])
    after = raw
    for start, end, replacement in sorted(replacements, reverse=True):
        after = after[:start] + replacement + after[end:]
    assert json.loads(after) == expected
    path.write_text(after)

    font_path = "assets/fonts/arena_sans.otf"
    font_bytes = (ROOT / font_path).read_bytes()
    assert font_bytes == baseline(font_path)
    font = TTFont(ROOT / font_path)
    cmap = font.getBestCmap()
    missing = sorted({char for line in EXPECTED.values() for char in line
                      if not char.isspace() and ord(char) not in cmap})
    assert not missing, missing
    font.close()
    unchanged = ["scripts/passives/source_tree_runtime.gd",
                 "scripts/passives/source_stat_patterns.gd",
                 "scripts/passives/source_tree_localization.gd",
                 "scripts/passives/source_tree_allocation_rules.gd",
                 "scripts/ui/canonical_passive_panel.gd",
                 "data/passive_source/data.json",
                 "data/passive_source/normalized_tree.json",
                 "data/passives/official_tree_runtime.json", "project.godot"]
    for item in unchanged:
        assert (ROOT / item).read_bytes() == baseline(item), item
    proof = {
        "base": BASE, "changed_keys": EXPECTED,
        "all_other_mapping_values_unchanged": True,
        "generator_only_nine_exact_overrides": True,
        "catalog_modified_paths": modified_paths,
        "catalog_changed_node_references": sorted(changed_nodes, key=int),
        "catalog_splice_count": len(replacements),
        "all_other_catalog_bytes_preserved": True,
        "typed_grants_and_support_status_unchanged": True,
        "source_graph_and_names_unchanged": True,
        "font_unchanged_and_all_text_covered": True,
        "unchanged_files": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                            for p in unchanged},
        "catalog_sha256": hashlib.sha256(after.encode()).hexdigest(),
        "godot_catalog_export_performed": False,
    }
    (QA / "exact-wording-check.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"changed_keys": len(EXPECTED), "node_references": len(changed_nodes),
                      "string_splices": len(replacements), "font_missing": missing}))


if __name__ == "__main__":
    main()
