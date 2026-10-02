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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("executable", type=Path)
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
    assert logical_name != "data/poe_passive_registry.json", "Research-only passive source exported"
    assert not logical_name.startswith(("data/reference/", "tests/", "tools/", "builds/", "docs/")), "Development-only file exported: " + name
    entries.append({"name": name, "size": size, "md5_verified": True})
assert any(entry["name"].removeprefix("res://") == "data/passive_balance.json" for entry in entries), "Shared balance authority omitted from export"
print(json.dumps({
    "pe": "x86_64", "embedded_pck_version": pack_version,
    "godot_version": f"{major}.{minor}.{patch}", "pck_offset": pack_start,
    "pck_bytes": pack_bytes, "file_count": file_count,
    "all_entry_md5_verified": True,
    "sha256": hashlib.sha256(data).hexdigest(), "files": entries,
}, indent=2, ensure_ascii=False))
