extends SceneTree
const Exporter = preload("res://tools/export_reference.gd")
const ViewData = preload("res://scripts/visuals/world_view.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var catalog_path := "res://docs/reference/catalog.json"
	var index_path := "res://docs/reference/index.html"
	var original_catalog := FileAccess.get_sha256(catalog_path)
	var original_index := FileAccess.get_sha256(index_path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	check(not FileAccess.get_file_as_string("res://tools/export_reference.gd").contains("Arena." + "ARENA"), "No static access to Main's instance bounds")
	check(Exporter.LEGACY_REFERENCE_BOUNDS == ViewData.default_arena(), "Historical bounds are the authoritative default arena")
	check(Exporter.LEGACY_REFERENCE_BOUNDS != ViewData.exploration_arena(), "Legacy and exploration coordinates remain distinct")
	var actual: Dictionary = Exporter.town_map_examples()
	check(actual.examples.size() == 4, "Historical town example emits all four maps")
	var counts := {"old_garden":0, "broken_ruins":2, "sunwell_terrace":4, "ginkgo_arcade":3}
	for id: String in counts:
		var example: Dictionary = actual.examples[id]
		var legacy := Exporter.MapGeometryData.new()
		check(legacy.configure(id, ViewData.default_arena()), id + ": legacy geometry accepted")
		var old: Dictionary = legacy.snapshot()
		check(example.geometry.bounds == {"position":old.bounds.position, "size":old.bounds.size}, id + ": historical bounds preserved exactly")
		check(example.geometry.walls.size() == counts[id] and example.geometry.spawn == old.spawn, id + ": historical walls and centered spawn")
		var camp: Dictionary = Exporter.CampLayoutData.layout(id, Exporter.LEGACY_REFERENCE_BOUNDS)
		check(camp.ok and camp.landmarks.camps.size() == 3, id + ": legacy source-group example remains valid")
		if saved.map_camps.has(id):
			check(_json(camp.landmarks) == saved.map_camps[id], id + ": prior serialized camp coordinates unchanged")
		if old.has("obstacle_style"):
			check(example.geometry.entry == camp.landmarks.entry, id + ": historical styled-map entry preserved")
		var current := Exporter.MapGeometryData.new()
		check(current.configure_exploration(id, ViewData.exploration_arena()), id + ": current exploration geometry accepted")
		var shape: Dictionary = current.snapshot()
		var published: Dictionary = saved.exploration_maps.maps[id].geometry
		check(shape.bounds.size == Vector2(3600,2400) and shape.landmarks.outposts.size() == 6, id + ": current world remains large with six outposts")
		check(_json(shape) == published, id + ": current geometry exactly matches preserved F8 snapshot")
		check(shape.walls.size() == counts[id] and shape.spawn == shape.landmarks.entry, id + ": exploration walls and entry agree")
	check(FileAccess.get_sha256(catalog_path) == original_catalog and FileAccess.get_sha256(index_path) == original_index, "Call-only probe did not export or rewrite F8")
	print("Reference bounds: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(_clean(value), "", true, true))

func _clean(value: Variant) -> Variant:
	if value is Rect2: return {"position":_clean(value.position),"size":_clean(value.size)}
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var out := {}
		for key: Variant in value: out[str(key)] = _clean(value[key])
		return out
	if value is Array:
		var out := []
		for item: Variant in value: out.append(_clean(item))
		return out
	return value

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(why)
