extends SceneTree
## Finite, deterministic PNG exports from the actual runtime drawing code.
## Native: godot --path . --script res://tools/export_reference_art.gd
## Output: docs/reference/art, or --output-dir /absolute/path, or GODOT_REFERENCE_ART_DIR.
## Headless-safe catalog/check: add -- --manifest-only (does not capture pixels).
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Art = preload("res://scripts/visuals/equipment_art.gd")
const Emblem = preload("res://scripts/visuals/skill_emblem.gd")
const Actors = preload("res://scripts/visuals/fantasy_actors.gd")
const Preferences = preload("res://scripts/visuals/visual_settings.gd")
const IMAGE_SIZE: int = 128
const MAX_EXPORTS: int = 256
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var output_dir: String


class ItemSurface extends Node2D:
	var entry: Dictionary = {}
	func _draw() -> void:
		Art.draw_item(self, entry, Rect2(8, 8, 112, 112))


class MonsterSurface extends Node2D:
	var enemy: Dictionary = {}
	var player_pos := Vector2(100, 0)
	var elapsed: float = 0.0
	var preferences := Preferences.new()
	func _draw() -> void:
		preferences.motion = false
		preferences.effects_level = 0
		Actors.draw_enemy(self, enemy, preferences, false)


class RaritySurface extends Node2D:
	var rarity: String = "normal"
	var demo_mode: bool = true
	var _font: Font = null
	var preferences := Preferences.new()
	func _draw() -> void:
		# Draw only the real rarity glyph. Status bars, names, brood beads and
		# spawn effects are not part of a reusable template thumbnail.
		var glyph: Dictionary = {"rarity": rarity, "health": 1.0, "max_health": 1.0}
		Actors._draw_enemy_marks(self, glyph, preferences, Monsters.RARITIES[rarity].color, 0.0, Vector2(0, 10))


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output_dir = OS.get_environment("GODOT_REFERENCE_ART_DIR")
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://docs/reference/art")
	var path_index: int = args.find("--output-dir")
	if path_index >= 0:
		if path_index + 1 >= args.size() or args[path_index + 1].begins_with("--"):
			push_error("--output-dir requires a directory")
			quit(1)
			return
		output_dir = args[path_index + 1]
	if output_dir.begins_with("res://") or output_dir.begins_with("user://"):
		output_dir = ProjectSettings.globalize_path(output_dir)
	elif not output_dir.is_absolute_path():
		output_dir = ProjectSettings.globalize_path("res://").path_join(output_dir)
	collect_rows()
	if rows.is_empty() or rows.size() > MAX_EXPORTS:
		failures.append("Export count outside finite 1..%d bound" % MAX_EXPORTS)
	var seen: Dictionary = {}
	for row: Dictionary in rows:
		var key: String = row.category + "/" + row.id
		if seen.has(key):
			failures.append("Duplicate category/id: " + key)
		seen[key] = true
		if not _safe_id(row.id):
			failures.append("Unsafe catalog ID: " + row.id)
	if not failures.is_empty():
		finish()
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		failures.append("Cannot create output directory: " + output_dir)
		finish()
		return
	if not write_manifest("manifest_only", 0):
		finish()
		return
	if args.has("--manifest-only"):
		print("REFERENCE_ART_MANIFEST_PASS: ", rows.size(), " catalog entries -> ", output_dir.path_join("manifest.json"))
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		failures.append("PNG capture requires a real display/rendering backend. Run natively, or use --manifest-only.")
		finish()
		return
	root.size = Vector2i(256, 256)
	root.title = "Runtime reference art export"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(IMAGE_SIZE, IMAGE_SIZE)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var written: int = 0
	for row: Dictionary in rows:
		var surface: Node = make_surface(row)
		if surface == null:
			failures.append("No runtime surface for " + row.category + "/" + row.id)
			continue
		viewport.add_child(surface)
		for unused: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = viewport.get_texture().get_image()
		if validate_pixels(pixels, row):
			var target: String = output_dir.path_join(row.file)
			if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK or pixels.save_png(target) != OK:
				failures.append("Could not save " + target)
			else:
				written += 1
		viewport.remove_child(surface)
		surface.free()
	viewport.queue_free()
	write_manifest("complete" if failures.is_empty() else "incomplete", written)
	if failures.is_empty():
		print("REFERENCE_ART_EXPORT_PASS: ", written, " transparent 128x128 PNGs; nonempty pixels and >=4px transparent borders verified -> ", output_dir)
	finish()


func collect_rows() -> void:
	for id: String in _sorted_ids(Data.SKILLS):
		add_row("skills", id, Data.SKILLS[id].name, "SkillEmblem._draw", "GameData.SKILLS", "active_skill")
	for id: String in _sorted_ids(Supports.SUPPORTS):
		add_row("supports", id, Supports.SUPPORTS[id].name, "SkillEmblem._draw", "SupportCatalog.SUPPORTS", "support")
	var base_ids: Array[String] = Gear.all_base_ids()
	base_ids.sort()
	for id: String in base_ids:
		add_row("equipment", id, Gear.base_definition(id).name, "EquipmentArt.draw_item", "EquipmentCatalog.all_base_ids", "base")
	for id: String in _sorted_ids(Data.ITEMS):
		add_row("equipment", id, Data.ITEMS[id].name, "EquipmentArt.draw_item", "GameData.ITEMS", "fixed_item")
	var jewel_bases: Dictionary = Jewels.BASES.duplicate(true)
	jewel_bases.merge(Jewels.SPECIAL_BASES)
	for id: String in _sorted_ids(jewel_bases):
		add_row("jewels", id, jewel_bases[id].name, "EquipmentArt.draw_item", "JewelData.BASES + SPECIAL_BASES", "special_base" if Jewels.SPECIAL_BASES.has(id) else "base")
	for id: String in _sorted_ids(Monsters.TEMPLATES):
		add_row("monsters", id, Monsters.TEMPLATES[id].name, "FantasyActors.draw_enemy + _draw_enemy_marks (rarity glyph only)", "MonsterCatalog.TEMPLATES", "template")


func add_row(category: String, id: String, display_name: String, renderer: String, catalog: String, entry_type: String) -> void:
	rows.append({"category": category, "id": id, "name": display_name, "file": category + "/" + id + ".png",
		"source_renderer": renderer, "source_catalog": catalog, "entry_type": entry_type})


func make_surface(row: Dictionary) -> Node:
	match str(row.category):
		"skills", "supports":
			var emblem := Emblem.new()
			emblem.skill_id = row.id
			# Preserve the runtime's compact engraved token proportions, including
			# the fixed-size glyph details, by scaling one actual 40px Control.
			emblem.size = Vector2(40, 40)
			emblem.position = Vector2(8, 8)
			emblem.scale = Vector2(2.8, 2.8)
			return emblem
		"equipment", "jewels":
			var item := ItemSurface.new()
			if row.category == "jewels":
				item.entry = {"kind": "jewel", "base": row.id}
			elif row.entry_type == "fixed_item":
				item.entry = Data.ITEMS[row.id].duplicate(true)
				item.entry["id"] = row.id
			else:
				item.entry = Gear.base_definition(row.id)
				item.entry["base_id"] = row.id
			return item
		"monsters":
			var template: Dictionary = Monsters.TEMPLATES[row.id]
			var enemy: Dictionary = Monsters.make_enemy(1, row.id, 1, Vector2.ZERO, "map_boss" if template.rarity == "boss" else "demo")
			if enemy.is_empty():
				return null
			var holder := Node2D.new()
			var body := MonsterSurface.new()
			body.enemy = enemy
			body.position = Vector2(62, 67)
			var normalized_radius: float = 28.0 if int(enemy.kind) == 1 else 34.0
			body.scale = Vector2.ONE * normalized_radius / float(enemy.radius)
			holder.add_child(body)
			var rarity := RaritySurface.new()
			rarity.rarity = template.rarity
			rarity.position = Vector2(108, 17)
			rarity.scale = Vector2(1.35, 1.35)
			holder.add_child(rarity)
			return holder
	return null


func validate_pixels(pixels: Image, row: Dictionary) -> bool:
	var label: String = row.category + "/" + row.id
	if pixels == null or pixels.is_empty() or pixels.get_size() != Vector2i(IMAGE_SIZE, IMAGE_SIZE):
		failures.append("Missing or wrong-sized pixels: " + label)
		return false
	var used: Rect2i = pixels.get_used_rect()
	if not used.has_area():
		failures.append("Empty transparent capture: " + label)
		return false
	if not Rect2i(4, 4, IMAGE_SIZE - 8, IMAGE_SIZE - 8).encloses(used):
		failures.append("Art reaches reserved transparent edge: " + label + " " + str(used))
		return false
	return true


func write_manifest(status: String, written: int) -> bool:
	var counts: Dictionary = {}
	for row: Dictionary in rows:
		counts[row.category] = int(counts.get(row.category, 0)) + 1
	var manifest: Dictionary = {"version": 1, "image_size": [IMAGE_SIZE, IMAGE_SIZE], "transparent_background": true,
		"file_paths_relative_to": "manifest.json directory", "status": status, "written_images": written,
		"counts": counts, "entries": rows,
		"capture": {"animation": "fixed pose; motion disabled", "monster_glyph": "runtime rarity symbol only", "minimum_transparent_border_px": 4,
			"source": "Original game runtime renderers; no third-party artwork; no unrelated placeholder images"}}
	var file := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		failures.append("Cannot write art manifest")
		return false
	file.store_string(JSON.stringify(manifest, "\t", false) + "\n")
	file.close()
	return true


func _sorted_ids(catalog: Dictionary) -> Array:
	var ids: Array = catalog.keys()
	ids.sort()
	return ids


func _safe_id(id: String) -> bool:
	if id.is_empty():
		return false
	for character: String in id:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true


func finish() -> void:
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
