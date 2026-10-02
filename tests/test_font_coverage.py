#!/usr/bin/env python3
"""Offline coverage regression tests, with optional isolated Godot text rendering.

python3 tests/test_font_coverage.py
python3 tests/test_font_coverage.py --godot godot --render-dir /tmp/font-qa
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import check_font_coverage as coverage
import subset_font
from fontTools.ttLib import TTFont


class StringScanTests(unittest.TestCase):
    def test_comments_do_not_request_glyphs(self):
        source = '# "注释"\nvar label = "回收 # 原样" # "忽略"\n'
        self.assertEqual(coverage.string_literals(source), [(2, "回收 # 原样")])

    def test_multiline_raw_names_and_paths(self):
        source = 'var a = """第一行\n第二行"""\nvar b = r"\\u6821"\nvar c = &"校准"; var d = ^"碎片"'
        self.assertEqual(coverage.string_literals(source), [(1, "第一行\n第二行"), (3, r"\u6821"), (4, "校准"), (4, "碎片")])

    def test_unicode_escapes_and_surrogates(self):
        self.assertEqual(coverage.string_literals(r'"\u6821\u51C6\U020000\uD840\uDC00"'), [(1, "校准𠀀𠀀")])

    def test_escaped_quotes_and_continuation(self):
        self.assertEqual(coverage.string_literals('"报\\\"价\\\'\\\n回收"'), [(1, '报"价\'回收')])

    def test_malformed_strings_fail(self):
        for source in ('"校准', r'"\u68ZZ"', r'"\q"', r'"\uD840"'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                coverage.string_literals(source)

    def test_json_csv_resources_and_gdignore(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "project.godot").write_text('; "忽略"\nconfig/name="中文"\n')
            for folder in ("scripts", "scenes", "data", "assets"):
                (root / folder).mkdir()
            (root / "scripts/ui.gd").write_text('var text = "校准" # "注释"\n')
            (root / "scenes/main.tscn").write_text('text = "碎片"\n')
            (root / "data/nested.json").write_text(r'{"标签":[{"name":"\u62a5\u4ef7"}]}')
            (root / "data/locale.csv").write_text('id,text\nitem,"回收,碎片"\n')
            (root / "assets/theme.tres").write_text('caption="字形"\n')
            (root / "assets/generation.json").write_text('{"prompt":"忽略"}')
            (root / "data/reference").mkdir()
            (root / "data/reference/.gdignore").touch()
            (root / "data/reference/offline.json").write_text('{"name":"忽略"}')
            required, count = coverage.collect_required(root, {"supplemental_sources": []})
            han = {chr(cp) for cp in required if coverage.is_han(cp)}
            self.assertEqual(han, set("中文校准碎片标签报价回收字形"))
            self.assertEqual(count, 6)

    def test_non_bmp_chinese_is_required(self):
        self.assertTrue(coverage.is_han(0x20000))
        self.assertIn(0x20000, coverage.printable_codepoints("𠀀\n\t"))
        self.assertNotIn(10, coverage.printable_codepoints("𠀀\n\t"))


class FontCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / coverage.MANIFEST_PATH).read_text())
        cls.font_bytes = (ROOT / coverage.FONT_PATH).read_bytes()
        cls.locations, cls.runtime_files = coverage.collect_required(ROOT, cls.manifest)

    def setUp(self):
        self.font = TTFont(io.BytesIO(self.font_bytes))
        self.addCleanup(self.font.close)

    def report(self, manifest=None):
        return coverage.check_font(self.font, set(self.locations), manifest or self.manifest)

    def test_all_runtime_and_pinned_crafting_characters(self):
        report = self.report()
        self.assertTrue(report["ok"], report)
        self.assertGreater(report["required_han"], 700)
        self.assertEqual(report["missing"], [])
        self.assertEqual(report["lost_baseline"], [])
        self.assertEqual(report["empty_han"], [])

    def test_more_than_the_six_reported_glyphs_are_protected(self):
        required = set(self.locations)
        self.assertTrue(set(map(ord, "价报收校片碎例工派艺证资")) <= required)
        self.assertTrue(set(map(ord, "贯穿")) <= required)

    def test_all_planner_failure_reasons_are_in_the_corpus(self):
        sources = [source for source in self.manifest["supplemental_sources"] if source["path"] == "scripts/items/crafting_transaction_planner.gd"]
        self.assertEqual(len(sources), 1)
        self.assertEqual(sources[0]["commit"], "5d5bba0baeb680cf56e0244e7c0b53490e290757")
        self.assertEqual(len(sources[0]["strings"]), 28)
        reasons = "".join(item["text"] for item in sources[0]["strings"])
        self.assertTrue(set("串务库订产号了料划七恰好许允态益") <= set(reasons))
        self.assertTrue(set(map(ord, reasons)) - {ord(" ")} <= set(self.locations))
        self.assertTrue(set(map(ord, "串务库订产号了料划七恰好许允态益")) <= set(self.locations))

    def test_missing_planner_glyphs_are_rejected(self):
        missing = set(map(ord, "串务库订产号了料划七恰好许允态益"))
        for table in self.font["cmap"].tables:
            if table.isUnicode():
                for codepoint in missing:
                    table.cmap.pop(codepoint, None)
        report = self.report()
        self.assertFalse(report["ok"])
        self.assertEqual(set(report["missing"]), missing)
        baseline = set(map(ord, self.manifest["baseline"]["characters"]))
        self.assertEqual(set(report["lost_baseline"]), missing & baseline)

    def test_encounter_ui_and_dynamic_option_names_are_covered(self):
        paths = {"scripts/ui/encounter_controls.gd", "scripts/encounters/encounter_catalog.gd"}
        sources = [s for s in self.manifest["supplemental_sources"] if s["path"] in paths]
        self.assertEqual({s["path"] for s in sources}, paths)
        self.assertTrue(all(s["commit"] == "48b929b528b5879c779712ab82814c535993b9a1" and len(s["strings"]) == 8 for s in sources))
        texts = [item["text"] for s in sources for item in s["strings"]]
        self.assertIn("强健", texts)
        self.assertIn("参数风险 · 难度尚未评估", texts)
        self.assertEqual(set(self.manifest["generation"]["added_since_baseline"]), set("参层评遇遭险难集健"))
        self.assertEqual(len(set(self.manifest["baseline"]["characters"])), 890)

    def test_pre_encounter_890_font_is_rejected(self):
        missing = set(map(ord, "参层评遇遭险难集健"))
        for table in self.font["cmap"].tables:
            if table.isUnicode():
                for cp in missing:
                    table.cmap.pop(cp, None)
        report = self.report()
        self.assertEqual(set(report["missing"]), missing)
        self.assertFalse(report["ok"])
        self.assertEqual(report["lost_baseline"], [])

    def test_existing_glyph_outlines_metrics_and_family(self):
        baseline = self.manifest["baseline"]
        self.assertEqual(coverage.glyph_fingerprint(self.font, set(map(ord, baseline["characters"]))), baseline["glyphs_sha256"])
        self.assertEqual(coverage.layout_metrics(self.font), baseline["layout_metrics"])
        self.assertEqual(self.font["name"].getDebugName(1), "Arena Sans SC")
        self.assertEqual(self.font["name"].getDebugName(6), "ArenaSansSC-Regular")

    def test_missing_crafting_glyph_is_detected(self):
        for table in self.font["cmap"].tables:
            if table.isUnicode():
                table.cmap.pop(ord("工"), None)
        report = self.report()
        self.assertFalse(report["ok"])
        self.assertIn(ord("工"), report["missing"])

    def test_lost_baseline_glyph_is_detected(self):
        for table in self.font["cmap"].tables:
            if table.isUnicode():
                table.cmap.pop(ord("伤"), None)
        report = self.report()
        self.assertFalse(report["ok"])
        self.assertIn(ord("伤"), report["lost_baseline"])

    def test_notdef_mapping_does_not_count_as_coverage(self):
        for table in self.font["cmap"].tables:
            if table.isUnicode():
                table.cmap[ord("校")] = ".notdef"
        self.assertIn(ord("校"), self.report()["missing"])

    def test_empty_chinese_glyph_is_detected(self):
        name = self.font.getBestCmap()[ord("工")]
        charstring = self.font["CFF "].cff.topDictIndex[0].CharStrings[name]
        charstring.bytecode = None
        charstring.program = ["endchar"]
        self.assertIn(ord("工"), self.report()["empty_han"])

    def test_metric_and_outline_regression_is_detected(self):
        name = self.font.getBestCmap()[ord("伤")]
        advance, bearing = self.font["hmtx"][name]
        self.font["hmtx"][name] = (advance + 1, bearing)
        self.assertIn("Existing glyph outlines/advances changed", self.report()["errors"])
        self.font["hhea"].ascent += 1
        self.assertIn("Font layout metrics changed", self.report()["errors"])

    def test_chinese_can_never_be_exempted(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["source_unsupported_symbols"] += "校"
        with self.assertRaises(ValueError):
            self.report(manifest)

    def test_license_and_embedded_license_preserved(self):
        license_info = self.manifest["license"]
        self.assertEqual(hashlib.sha256((ROOT / license_info["path"]).read_bytes()).hexdigest(), license_info["sha256"])
        self.assertIn("SIL Open Font License", self.font["name"].getDebugName(13))
        self.assertTrue(self.font["name"].getDebugName(0))

    def test_unverified_source_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = root / coverage.MANIFEST_PATH
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_text(json.dumps(self.manifest))
            source = root / "unverified.ttf"
            source.write_bytes(b"not the recorded font")
            with self.assertRaisesRegex(ValueError, "Source SHA256"):
                subset_font.regenerate(source, root=root)
            self.assertFalse((root / coverage.FONT_PATH).exists())

    def test_offline_cli_and_strict_symbol_audit(self):
        command = [sys.executable, str(ROOT / "tools/check_font_coverage.py"), "--json"]
        result = subprocess.run(command, cwd="/tmp", capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["ok"])
        self.assertEqual(report["fallback_symbols"], [0x2301, 0x25C8])
        strict = subprocess.run(command + ["--strict-symbols"], capture_output=True, text=True)
        self.assertEqual(strict.returncode, 1, strict.stderr)


GODOT_PROBE = r'''
extends SceneTree
class TextCanvas extends Node2D:
    var font: FontFile
    var rows: Array
    var sizes: Array
    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("f2e5c5"))
        var y: float = 32
        for raw_size: float in sizes:
            var size: int = int(raw_size)
            draw_string(font, Vector2(24, y), "Arena Sans SC / %d px / fallback OFF" % size, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("473828"))
            y += 32
            for text: String in rows:
                draw_string(font, Vector2(24, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("473828"))
                y += 30
            y += 20

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var input: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://probe.json"))
    var font: FontFile = load("res://assets/fonts/arena_sans.otf")
    font.allow_system_fallback = false
    font.fallbacks = []
    var ts: TextServer = TextServerManager.get_primary_interface()
    var rids: Array[RID] = font.get_rids()
    if rids.size() != 1 or ts.font_is_allow_system_fallback(rids[0]):
        push_error("Probe must use exactly one native font RID without fallback")
        quit(1)
        return
    var mappings: int = 0
    var rasters: int = 0
    for raw_size: float in input.sizes:
        var size: int = int(raw_size)
        for raw_codepoint: float in input.codepoints:
            var codepoint: int = int(raw_codepoint)
            var glyph: int = ts.font_get_glyph_index(rids[0], size, codepoint, 0)
            if not ts.font_has_char(rids[0], codepoint) or glyph == 0:
                push_error("Missing native glyph U+%04X" % codepoint)
                quit(1)
                return
            mappings += 1
        for raw_codepoint: float in input.han:
            var glyph: int = ts.font_get_glyph_index(rids[0], size, int(raw_codepoint), 0)
            font.render_glyph(0, Vector2i(size, 0), glyph)
            var extent: Vector2 = font.get_glyph_size(0, Vector2i(size, 0), glyph)
            if extent.x <= 0 or extent.y <= 0 or font.get_glyph_texture_idx(0, Vector2i(size, 0), glyph) < 0:
                push_error("Empty Godot raster U+%04X" % int(raw_codepoint))
                quit(1)
                return
            rasters += 1
    var result: Dictionary = {"engine": Engine.get_version_info().string, "native_mappings": mappings, "han_rasters": rasters, "sizes": input.sizes, "font_rids": rids.size(), "supported_chars": font.get_supported_chars().length(), "fallback": false, "display_driver": DisplayServer.get_name(), "rendered": false}
    if not input.render_path.is_empty():
        root.size = Vector2i(1100, int(input.capture_height))
        root.content_scale_size = root.size
        var canvas := TextCanvas.new()
        canvas.font = font
        canvas.rows = input.rows
        canvas.sizes = input.sizes
        root.add_child(canvas)
        for index: int in range(10):
            await process_frame
        await RenderingServer.frame_post_draw
        var image: Image = root.get_texture().get_image()
        if image.is_empty() or image.save_png(input.render_path) != OK:
            push_error("Unable to save actual Godot text viewport")
            quit(1)
            return
        result.rendered = true
        result.rendered_rows = input.rows
        result.capture_height = int(input.capture_height)
    var output: FileAccess = FileAccess.open("res://result.json", FileAccess.WRITE)
    output.store_string(JSON.stringify(result))
    output.close()
    print("GODOT_FONT_PROBE_PASS ", JSON.stringify(result))
    quit()
'''


def godot_probe(godot: str, render_dir: Path | None) -> dict:
    """Import the exact binary/settings in a temporary project, with isolated saves."""
    manifest = json.loads((ROOT / coverage.MANIFEST_PATH).read_text())
    locations, _ = coverage.collect_required(ROOT, manifest)
    baseline = set(map(ord, manifest["baseline"]["characters"]))
    codepoints = set(locations) | baseline
    codepoints -= set(map(ord, manifest["source_unsupported_symbols"]))
    rows = [
        "价 报 收 校 片 碎 / 仓 竞 例 工 派 艺 证 资 / 贯穿辅助",
        "校准碎片 12 / 回收 / 校准",
        "暂无可用的制作报价。",
        "制作报价缺少有效的校准碎片数量。",
        "此稀有度尚未定义工艺成本。",
        "底材或词缀资格无效。",
    ]
    probe = manifest.get("render_probe", {"source_paths": ["scripts/items/crafting_transaction_planner.gd"], "sizes": [16, 19]})
    render_sources = [source for source in manifest["supplemental_sources"] if source["path"] in probe["source_paths"]]
    if render_sources:
        # Use original display strings that collectively contain every new Han.
        texts = [item["text"] for source in render_sources for item in source["strings"]]
        remaining = {chr(cp) for cp in locations if coverage.is_han(cp)} - set(manifest["baseline"]["characters"])
        rows = []
        while remaining:
            text = max(texts, key=lambda candidate: len(set(candidate) & remaining))
            hits = set(text) & remaining
            if not hits:
                raise ValueError("Display-string rendering corpus does not cover new Han glyphs")
            rows.append(text)
            remaining -= hits
    if render_dir:
        render_dir = render_dir.resolve()
        render_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="godot-font-coverage-") as directory:
        project = Path(directory)
        assets = project / "assets/fonts"
        assets.mkdir(parents=True)
        for filename in ("arena_sans.otf", "arena_sans.otf.import"):
            shutil.copy2(ROOT / "assets/fonts" / filename, assets / filename)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Font coverage probe"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (project / "probe.gd").write_text(GODOT_PROBE)
        (project / "probe.json").write_text(json.dumps({
            "codepoints": sorted(codepoints), "han": sorted(cp for cp in locations if coverage.is_han(cp)),
            "rows": rows, "sizes": probe["sizes"],
            "capture_height": 32 + len(probe["sizes"]) * (52 + 30 * len(rows)),
            "render_path": str(render_dir / "godot-text-16-19.png") if render_dir else "",
        }, ensure_ascii=False))
        environment = dict(os.environ)
        for key, folder in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            environment[key] = str(project / folder)
            (project / folder).mkdir()
        (project / "cache/fontconfig").mkdir()
        base = [godot, "--path", str(project)]
        commands = [base + ["--headless", "--editor", "--import"], base + ([] if render_dir else ["--headless"]) + ["--script", "res://probe.gd", "--audio-driver", "Dummy"]]
        for command in commands:
            completed = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=60)
            log = completed.stdout + completed.stderr
            if completed.returncode or "SCRIPT ERROR:" in log or "ERROR:" in log:
                raise RuntimeError(f"Godot probe failed ({completed.returncode}):\n{log}")
        result = json.loads((project / "result.json").read_text())
        result["font_sha256"] = hashlib.sha256((ROOT / coverage.FONT_PATH).read_bytes()).hexdigest()
        if render_dir:
            result["png_sha256"] = hashlib.sha256((render_dir / "godot-text-16-19.png").read_bytes()).hexdigest()
            (render_dir / "godot-probe.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Optional Godot executable for native mapping/raster checks")
    parser.add_argument("--render-dir", type=Path, help="Also capture a text viewport; requires a graphical display")
    args = parser.parse_args()
    if args.render_dir and not args.godot:
        parser.error("--render-dir requires --godot")
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
    if args.godot:
        print(json.dumps(godot_probe(args.godot, args.render_dir), ensure_ascii=False, indent=2))
