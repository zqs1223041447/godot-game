#!/usr/bin/env python3
"""Verify the Godot 4.6 Windows x86_64 PE and every embedded PCK v3 entry.

Usage: python tools/verify_windows_pack.py builds/windows/GodotGame.exe
This checks exported bytes; it does not claim Windows-native execution.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("executable", type=Path)
parser.add_argument("--verify-import-cache", action="store_true", help="Match exported painting bytes to freshly imported current source files")
args = parser.parse_args()
data = args.executable.read_bytes()
assert data[:2] == b"MZ", "Missing DOS executable signature"
pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
assert data[pe_offset:pe_offset + 4] == b"PE\0\0", "Missing PE signature"
assert struct.unpack_from("<H", data, pe_offset + 4)[0] == 0x8664, "Expected AMD64 PE"
assert data[-4:] == b"GDPC", "Embedded Godot pack footer missing"
pack_bytes = struct.unpack_from("<Q", data, len(data) - 12)[0]
pack_start = len(data) - 12 - pack_bytes
assert pack_start >= 0 and data[pack_start:pack_start + 4] == b"GDPC"
pack_version, major, minor, patch, pack_flags = struct.unpack_from("<IIIII", data, pack_start + 4)
assert pack_version == 3, "Verifier supports PCK v3 only"
assert not pack_flags & 1, "Encrypted directory unsupported"
data_base, directory_offset = struct.unpack_from("<QQ", data, pack_start + 24)
position = pack_start + directory_offset
file_count = struct.unpack_from("<I", data, position)[0]
position += 4
assert 0 < file_count < 10000
entries = []
packed_payloads = {}
for _ in range(file_count):
    name_bytes = struct.unpack_from("<I", data, position)[0]
    position += 4
    assert name_bytes < 65536
    name = data[position:position + name_bytes].decode("utf-8").rstrip("\0")
    position += name_bytes
    offset, size = struct.unpack_from("<QQ", data, position)
    position += 16
    digest = data[position:position + 16]
    position += 16
    flags = struct.unpack_from("<I", data, position)[0]
    position += 4
    start = pack_start + data_base + offset
    assert pack_start <= start <= start + size <= len(data) - 12, name
    assert not flags & 1, "Encrypted entry unsupported"
    assert hashlib.md5(data[start:start + size]).digest() == digest, name
    logical_name = name.removeprefix("res://")
    packed_payloads[logical_name] = data[start:start + size]
    assert logical_name != "data/poe_passive_registry.json", "Research-only passive source exported"
    assert not logical_name.startswith("data/passive_source/") or logical_name == "data/passive_source/localization_zh_CN.json", "Research-only passive source exported: " + name
    assert not logical_name.startswith(("data/reference/", "tests/", "tools/", "builds/", "docs/")), "Development-only file exported: " + name
    entries.append({"name": name, "size": size, "md5_verified": True})
assert any(entry["name"].removeprefix("res://") == "data/passive_balance.json" for entry in entries), "Shared balance authority omitted from export"
# All original paintings must have both their import map and compiled texture.
project_root = Path(__file__).resolve().parents[1]
names = {entry["name"].removeprefix("res://") for entry in entries}
localization_path = "data/passive_source/localization_zh_CN.json"
if (project_root / localization_path).is_file():
    assert localization_path in names, "Passive-tree display mapping omitted from export"
    assert packed_payloads[localization_path] == (project_root / localization_path).read_bytes(), "Packed passive-tree mapping differs from frozen source"
painted_assets_verified = 0
painted_cache_verified = []
art_manifest = json.loads((project_root / "assets/ui/grimoire/asset_manifest.json").read_text())
manifest_hashes = {row["path"]: row["sha256"] for row in art_manifest["assets"]}
for folder in ("assets/ui/grimoire", "assets/art/equipment"):
    for source in sorted((project_root / folder).glob("*.png")):
        import_file = source.with_name(source.name + ".import")
        import_name = str(import_file.relative_to(project_root))
        assert import_name in names, "Painted asset import missing: " + import_name
        imported_paths = re.findall(r'^path="res://([^"\n]+)"', import_file.read_text(), re.MULTILINE)
        assert len(imported_paths) == 1 and imported_paths[0] in names, "Painted texture missing: " + import_name
        if args.verify_import_cache:
            source_name = source.relative_to(project_root).as_posix()
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            if source_name in manifest_hashes:
                assert source_hash == manifest_hashes[source_name], "Artwork manifest source is stale: " + source_name
            imported = project_root / imported_paths[0]
            checksum_file = imported.with_suffix(".md5")
            source_md5 = re.findall(r'^source_md5="([0-9a-f]{32})"', checksum_file.read_text(), re.MULTILINE)
            assert source_md5 == [hashlib.md5(source.read_bytes()).hexdigest()], "Texture cache came from different PNG bytes: " + source_name
            # Godot deliberately exports only [remap], removing editor-only
            # [deps]/[params] and adding a trailing NUL. Compare that runtime
            # mapping exactly rather than requiring an impossible whole-file match.
            source_remap = import_file.read_text().split("[deps]", 1)[0].strip()
            packed_remap = packed_payloads[import_name].decode("utf-8").rstrip("\0").strip()
            assert packed_remap == source_remap, "Packed runtime import mapping differs: " + source_name
            assert packed_payloads[imported_paths[0]] == imported.read_bytes(), "Packed texture differs from fresh source cache: " + source_name
            painted_cache_verified.append({"source": source_name, "source_sha256": source_hash,
                "imported": imported_paths[0], "texture_sha256": hashlib.sha256(imported.read_bytes()).hexdigest()})
        painted_assets_verified += 1
print(json.dumps({
    "pe": "x86_64", "embedded_pck_version": pack_version,
    "godot_version": f"{major}.{minor}.{patch}", "pck_offset": pack_start,
    "pck_bytes": pack_bytes, "file_count": file_count,
    "all_entry_md5_verified": True, "painted_assets_verified": painted_assets_verified,
    "painting_import_cache_matches": painted_cache_verified,
    "sha256": hashlib.sha256(data).hexdigest(), "files": entries,
}, indent=2, ensure_ascii=False))
