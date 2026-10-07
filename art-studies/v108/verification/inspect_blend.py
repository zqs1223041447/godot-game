#!/usr/bin/env python3
"""Read-only structural inspection of this packed Blender art-study scene.

Emits JSON to stdout. Does not invoke Blender, render, save, extract, or download.
Supports the little-endian, 64-bit Blender format used by the audited artifact.
Compressed input requires the locally installed zstandard package.
"""
import argparse
import collections
import hashlib
import io
import json
import re
import struct
from pathlib import Path


def inspect(path):
    file_bytes = path.read_bytes()
    if file_bytes.startswith(b"\x28\xb5\x2f\xfd"):
        import zstandard
        with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(file_bytes)) as reader:
            raw = reader.read()
    else:
        raw = file_bytes
    if raw[:9] != b"BLENDER-v":
        raise ValueError("Expected a 64-bit, little-endian Blender file")

    blocks = []
    by_pointer = {}
    offset = 12
    while offset + 24 <= len(raw):
        code, size, pointer, dna_index, count = struct.unpack_from("<4siQii", raw, offset)
        if size < 0 or offset + 24 + size > len(raw):
            raise ValueError("Invalid Blender block length")
        payload = raw[offset + 24:offset + 24 + size]
        block = (code, size, pointer, dna_index, count, payload)
        blocks.append(block)
        if pointer:
            by_pointer[pointer] = payload
        offset += 24 + size
        if code == b"ENDB":
            break
    else:
        raise ValueError("Missing Blender ENDB block")

    dna = next(block[5] for block in blocks if block[0] == b"DNA1")
    if dna[:8] != b"SDNANAME":
        raise ValueError("Invalid SDNA signature")
    cursor = 8

    def integer():
        nonlocal cursor
        value = struct.unpack_from("<I", dna, cursor)[0]
        cursor += 4
        return value

    def strings(count):
        nonlocal cursor
        result = []
        for _ in range(count):
            end = dna.index(b"\0", cursor)
            result.append(dna[cursor:end].decode("utf-8"))
            cursor = end + 1
        return result

    def section(label):
        nonlocal cursor
        cursor = (cursor + 3) & ~3
        if dna[cursor:cursor + 4] != label:
            raise ValueError("Invalid SDNA section")
        cursor += 4

    names = strings(integer())
    section(b"TYPE")
    types = strings(integer())
    section(b"TLEN")
    lengths = struct.unpack_from("<" + "H" * len(types), dna, cursor)
    cursor += 2 * len(types)
    section(b"STRC")
    structures = []
    fields_by_type = {}
    for _ in range(integer()):
        type_index, field_count = struct.unpack_from("<HH", dna, cursor)
        cursor += 4
        fields = {}
        position = 0
        for _ in range(field_count):
            field_type, field_name = struct.unpack_from("<HH", dna, cursor)
            cursor += 4
            name = names[field_name]
            multiplier = 1
            for value in re.findall(r"\[(\d+)\]", name):
                multiplier *= int(value)
            size = (8 if "*" in name else lengths[field_type]) * multiplier
            fields[name] = (position, size, types[field_type])
            position += size
        type_name = types[type_index]
        structures.append(type_name)
        fields_by_type[type_name] = fields
        if type_name in {"ID", "Image", "ImagePackedFile", "PackedFile", "ListBase"}:
            if position != lengths[type_index]:
                raise ValueError("Unsupported SDNA field layout for " + type_name)

    def offset_of(type_name, field_name):
        return fields_by_type[type_name][field_name][0]

    def pointer_at(payload, offset):
        return struct.unpack_from("<Q", payload, offset)[0]

    def text_at(payload, offset, length):
        return payload[offset:offset + length].split(b"\0", 1)[0].decode("utf-8", "replace")

    def block_type(block):
        index = block[3]
        if block[0] in {b"DNA1", b"ENDB"} or not 0 <= index < len(structures):
            return None
        return structures[index]

    images = []
    total_bytes = 0
    unpacked = []
    for block in blocks:
        if block_type(block) != "Image":
            continue
        payload = block[5]
        image_name = text_at(payload, offset_of("Image", "id") + offset_of("ID", "name[66]"), 66)
        source_path = text_at(payload, offset_of("Image", "name[1024]"), 1024)
        packed_pointer = pointer_at(payload, offset_of("Image", "*packedfile"))
        list_pointer = pointer_at(payload, offset_of("Image", "packedfiles"))
        if not packed_pointer and list_pointer:
            packed_pointer = pointer_at(by_pointer[list_pointer], offset_of("ImagePackedFile", "*packedfile"))
        entry = {"name": image_name, "source_path_is_relative": source_path.startswith("//")}
        # Report relative paths only; avoid exposing old absolute workspace metadata.
        if source_path.startswith("//"):
            entry["source_path"] = source_path
        if not packed_pointer:
            unpacked.append(image_name)
            entry["packed"] = False
        else:
            packed = by_pointer[packed_pointer]
            size = struct.unpack_from("<i", packed, offset_of("PackedFile", "size"))[0]
            data_pointer = pointer_at(packed, offset_of("PackedFile", "*data"))
            data = by_pointer[data_pointer]
            if size < 0 or len(data) < size:
                raise ValueError("Incomplete packed data for " + image_name)
            entry.update(packed=True, packed_bytes=size, packed_sha256=hashlib.sha256(data[:size]).hexdigest())
            total_bytes += size
        images.append(entry)

    counts = collections.Counter(block_type(block) for block in blocks)
    external_types = ["Library", "Text", "VFont", "bSound", "MovieClip", "Volume", "CacheFile"]
    asset_families = sorted({
        entry["source_path"].split("/")[3]
        for entry in images
        if entry.get("source_path", "").startswith("//assets/")
    })
    return {
        "filename": path.name,
        "bytes": len(file_bytes),
        "sha256": hashlib.sha256(file_bytes).hexdigest(),
        "decoded_header": raw[:12].decode("ascii"),
        "decoded_bytes": len(raw),
        "image_data_blocks": len(images),
        "images_with_packed_data": sum(entry["packed"] for entry in images),
        "packed_image_bytes": total_bytes,
        "unpacked_images": unpacked,
        "external_datablock_counts": {name: counts[name] for name in external_types},
        "asset_families_from_image_paths": asset_families,
        "images": images,
        "scope": "Read-only binary structure inspection; not a render or gameplay test",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("blend", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.blend), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
