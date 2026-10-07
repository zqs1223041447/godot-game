extends SceneTree
## Narrow, CPU-only atlas extraction. Does not run the full reference exporter.
## godot --headless --path . --script res://tools/export_monster_reference_art.gd
## Add -- --verify-only to recheck the saved PNGs, manifest and two HTML images.
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const ART := "res://docs/reference/art/"
const MANIFEST := ART + "manifest.json"
const HTML := "res://docs/reference/index.html"
const EVIDENCE := "res://docs/qa/v106-reference-art/"
const BORDER := 8
const DIRECTION := 2
const ANIMATION := "idle"
const PLACEHOLDER := '<span class="fallback-emblem" aria-hidden="true">✧</span>'
const SIZE_SCOPE := "image_size is the legacy default; each entry.image_size overrides it. Monster entries use their actual cropped atlas-frame dimensions without scaling."
const CAPTURE_SCOPE := "capture describes legacy non-monster exports only. All monster entries use monster_capture and their per-entry source metadata."
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var source_hashes: Dictionary = {}
var verify_only := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	verify_only = OS.get_cmdline_user_args().has("--verify-only")
	var ids: Array = Monsters.TEMPLATES.keys()
	ids.sort()
	var frame_index: int = Catalog.frame_index(DIRECTION, ANIMATION, 0.0)
	var frame_rect := Rect2i(Catalog.frame_rect(frame_index))
	for id: String in ids:
		_extract_and_check(id, frame_index, frame_rect)
	if failures.is_empty():
		_sync_manifest()
		_sync_html()
	for source: String in source_hashes:
		if FileAccess.get_sha256(source) != source_hashes[source]:
			failures.append("Source atlas changed: " + source)
	var evidence := {
		"status": "pass" if failures.is_empty() else "fail",
		"mode": "verify_only" if verify_only else "export_and_verify",
		"method": "Godot Image.load_from_file / get_region / blit_rect; CPU pixels only",
		"runtime_catalog": "ActorSpriteCatalog.enemy_key / enemy_tint / frame_index / frame_rect",
		"source_atlas_sha256": source_hashes,
		"source_atlases_unchanged": failures.filter(func(item: String) -> bool: return item.begins_with("Source atlas changed:")).is_empty(),
		"template_count": rows.size(), "family_count": source_hashes.size(),
		"checks": checks, "entries": rows, "failures": failures,
		"scope": "Lossless untinted source frames only; no editor import, runtime scene, combat, GPU capture, resize, recolor, or generated design."
	}
	var evidence_name := "verify.json" if verify_only else "export.json"
	if not _write_json(EVIDENCE + evidence_name, evidence):
		failures.append("Cannot save evidence " + evidence_name)
	for failure: String in failures:
		push_error(failure)
	print("MONSTER_REFERENCE_ART_%s: %d templates, %d source families; %s" % ["PASS" if failures.is_empty() else "FAIL", rows.size(), source_hashes.size(), evidence_name])
	quit(0 if failures.is_empty() else 1)


func _extract_and_check(id: String, frame_index: int, frame_rect: Rect2i) -> void:
	var enemy := {"template_id": id}
	var family: String = Catalog.enemy_key(enemy)
	if family.is_empty() or not Catalog.DEFINITIONS.has(family):
		failures.append("No authoritative family for " + id)
		return
	var source: String = Catalog.DEFINITIONS[family].path
	var source_hash := FileAccess.get_sha256(source)
	if source_hash.is_empty():
		failures.append("Unreadable atlas " + source)
		return
	source_hashes[source] = source_hash
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(source))
	if atlas == null or atlas.is_empty() or atlas.get_format() != Image.FORMAT_RGBA8:
		failures.append("Expected nonempty original RGBA8 atlas for " + id)
		return
	if not Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(frame_rect):
		failures.append("Frame outside atlas for " + id)
		return
	var frame := atlas.get_region(frame_rect)
	var crop: Rect2i = frame.get_used_rect()
	if not crop.has_area():
		failures.append("Empty source frame for " + id)
		return
	var core := frame.get_region(crop)
	var output := Image.create(crop.size.x + BORDER * 2, crop.size.y + BORDER * 2, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	output.blit_rect(core, Rect2i(Vector2i.ZERO, core.get_size()), Vector2i(BORDER, BORDER))
	var file := "monsters/" + id + ".png"
	if not verify_only:
		if output.save_png(ART + file) != OK:
			failures.append("Cannot write " + file)
			return
	var saved := Image.load_from_file(ProjectSettings.globalize_path(ART + file))
	if saved == null or saved.is_empty() or saved.get_format() != Image.FORMAT_RGBA8:
		failures.append("Expected saved RGBA8 PNG for " + id)
		return
	var core_rect := Rect2i(Vector2i(BORDER, BORDER), crop.size)
	var core_equal := saved.get_region(core_rect).get_data() == core.get_data()
	var exact_image := saved.get_size() == output.get_size() and saved.get_data() == output.get_data()
	var nonempty_pixels := 0
	var border_clear := true
	for y: int in range(saved.get_height()):
		for x: int in range(saved.get_width()):
			if saved.get_pixel(x, y).a > 0.0:
				nonempty_pixels += 1
				if not core_rect.has_point(Vector2i(x, y)):
					border_clear = false
	var used_bounds_match := saved.get_used_rect() == core_rect
	if not core_equal or not exact_image or not border_clear or not used_bounds_match or nonempty_pixels == 0:
		failures.append("Lossless pixel / nonempty / 8px border verification failed for " + id)
	var tint: Color = Catalog.enemy_tint(enemy)
	rows.append({
		"category": "monsters", "id": id, "name": Monsters.TEMPLATES[id].name,
		"file": file,
		"source_renderer": "Godot Image.load_from_file + get_region; lossless source atlas frame",
		"source_catalog": "MonsterCatalog.TEMPLATES + ActorSpriteCatalog", "entry_type": "template",
		"family": family, "source_atlas": source, "source_atlas_sha256": source_hash,
		"source_frame": {"direction_index": DIRECTION, "direction": "south", "animation": ANIMATION, "seconds": 0, "frame_index": frame_index},
		"source_frame_rect": _rect_array(frame_rect), "source_crop_rect_in_frame": _rect_array(crop),
		"image_size": [saved.get_width(), saved.get_height()], "transparent_border_px": BORDER,
		"runtime_tint": [tint.r, tint.g, tint.b, tint.a], "tint_applied": false,
		"capture": "Original family atlas frame, transparent outer crop only plus 8px transparent padding; unscaled and untinted. No rarity glyph or status overlays."
	})
	checks.append({
		"id": id, "family": family, "png_sha256": FileAccess.get_sha256(ART + file),
		"format": "RGBA8", "image_size": [saved.get_width(), saved.get_height()],
		"nonempty_pixels": nonempty_pixels, "core_pixels_equal_source": core_equal,
		"complete_image_equals_expected": exact_image, "transparent_border_8px": border_clear,
		"used_bounds_match": used_bounds_match,
	})


func _sync_manifest() -> void:
	var original := FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(original)
	if not parsed is Dictionary or not parsed.get("entries") is Array:
		failures.append("Invalid existing art manifest")
		return
	var manifest: Dictionary = parsed
	var entries: Array = []
	for entry: Dictionary in manifest.entries:
		if entry.get("category") != "monsters":
			entries.append(entry)
	entries.append_array(rows)
	manifest.entries = entries
	manifest.counts.monsters = rows.size()
	manifest.written_images = entries.size()
	manifest.image_size_scope = SIZE_SCOPE
	manifest.capture_scope = CAPTURE_SCOPE
	manifest.monster_capture = {
		"method": "lossless extraction of current runtime family atlas frames",
		"animation": "south-facing idle, frame zero", "minimum_transparent_border_px": BORDER,
		"trim": "fully transparent outer rows and columns only", "resize": false,
		"tint_applied": false, "runtime_tint": "Recorded per entry for traceability; not applied to these PNGs.",
		"glyphs_and_overlays": "none", "source_authority": "ActorSpriteCatalog.enemy_key, frame_index, frame_rect, enemy_tint",
	}
	var updated := JSON.stringify(manifest, "\t", false) + "\n"
	if _nonmonster_entry_bytes(original) != _nonmonster_entry_bytes(updated):
		failures.append("Refusing manifest write: non-monster entry bytes would change")
		return
	if verify_only:
		if updated != original:
			failures.append("Saved manifest does not match authoritative monster rows")
	elif not _write_text(MANIFEST, updated):
		failures.append("Cannot write art manifest")


func _nonmonster_entry_bytes(manifest: String) -> String:
	var start := manifest.find('\t"entries": [\n')
	var stop := manifest.find('\t\t{\n\t\t\t"category": "monsters",')
	if start < 0 or stop <= start:
		failures.append("Unexpected manifest entry layout; no safe limited update")
		return ""
	return manifest.substr(start, stop - start)


func _sync_html() -> void:
	var original := FileAccess.get_file_as_string(HTML)
	var updated := original
	for id: String in ["mist_skitter", "chaos_guard"]:
		var prefix := '<article class="entry" id="monsters-%s" data-category="monsters" tabindex="-1"><div class="entry-heading">' % id
		var image := '<img class="emblem" src="art/monsters/%s.png" width="64" height="64" alt="" loading="lazy">' % id
		if updated.count(prefix + PLACEHOLDER) == 1:
			updated = updated.replace(prefix + PLACEHOLDER, prefix + image)
		elif updated.count(prefix + image) != 1:
			failures.append("Unexpected card header; refusing HTML update for " + id)
			return
	if verify_only:
		if updated != original:
			failures.append("Missing monster image in HTML")
	elif updated != original and not _write_text(HTML, updated):
		failures.append("Cannot write reference HTML")


func _rect_array(rect: Rect2i) -> Array[int]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _write_json(path: String, data: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(data, "\t", false) + "\n")


func _write_text(path: String, content: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	return file.get_error() == OK
