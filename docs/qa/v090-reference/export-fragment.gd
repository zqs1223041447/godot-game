extends SceneTree
## Four current layouts and four detached I-tier Plans only. No Main, save,
## historical catalog, player equipment, combat, full exporter or asset rebuild.
const Maps = preload("res://scripts/world/map_catalog.gd")
const Compiler = preload("res://scripts/world/map_compiler.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const Plan = preload("res://scripts/world/exploration_map_plan.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const OUTPUT := "res://docs/qa/v090-reference/exploration-fragment.json"
const SEED_VALUE := 90001


func clean(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Rect2: return {"position": clean(value.position), "size": clean(value.size)}
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[str(key)] = clean(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value: result.append(clean(item))
		return result
	return value


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-v090-reference-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	assert(not FileAccess.file_exists(OUTPUT), "Never overwrite previous export evidence")
	var inputs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v090-routes/tested-inputs.json"))
	for path: String in inputs:
		assert(FileAccess.get_sha256("res://" + path) == inputs[path], "Frozen input changed: " + path)
	var maps := {}
	for map_id: String in Maps.MAPS:
		var compiled: Dictionary = Compiler.compile_normal(map_id, 1, [], [])
		assert(compiled.ok)
		var layout: Dictionary = Layout.layout(map_id, Layout.WORLD_BOUNDS)
		assert(layout.ok and layout.landmarks.distribution_version == "route_outposts_v1")
		assert(layout.landmarks.outposts.size() == 6)
		for segment: Dictionary in layout.landmarks.route_segments: assert(segment.width == 72.0)
		var runtime := Runtime.new()
		var planned: Dictionary = Plan.plan(compiled.profile, runtime, SEED_VALUE, Layout.WORLD_BOUNDS)
		assert(planned.ok and planned.roots.size() == int(Maps.MAPS[map_id].ordinary_target) + 1)
		assert(planned.spawn_records.size() == planned.roots.size())
		assert(planned.mechanism_config.is_empty() and planned.optional_encounters.is_empty())
		assert(runtime.next_id == 0, "Detached export must not commit staged actors")
		var shape: Dictionary = planned.geometry.snapshot()
		assert(shape.landmarks == layout.landmarks and shape.walls == layout.walls)
		var roots := []
		for enemy: Dictionary in planned.roots:
			assert(not enemy.exploration_awake)
			roots.append({"actor_id": enemy.id, "root_id": enemy.root_id, "template_id": enemy.template_id,
				"position": enemy.pos, "radius": enemy.radius, "rarity": enemy.rarity,
				"generation": enemy.generation, "reward_eligible": enemy.reward_eligible,
				"spawn_key": enemy.map_spawn_key, "awake": enemy.exploration_awake,
				"outpost_id": str(enemy.get("map_outpost_id", ""))})
		maps[map_id] = {"description": Layout.description(map_id), "geometry": shape,
			"plan_example": {"seed": SEED_VALUE, "total": roots.size(), "roots": roots,
				"spawn_records": planned.spawn_records, "mechanism_config": planned.mechanism_config,
				"optional_encounters": planned.optional_encounters,
				"scope": "Detached I-tier empty-modifier Plan example; no Main execution, player equipment, save, combat or rewards."}}
	assert(maps.size() == 4)
	var result := {"maps": maps, "route_distribution": {"version": "route_outposts_v1",
		"outpost_count": 6, "route_width": 72.0, "source_group_count": 3}}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(clean(result), "\t", true, true) + "\n")
	file.close()
	print("Exported four layouts and four detached Plans; 6 outposts per map, 72-unit routes; no Main, combat, saves or PNGs")
	quit(0)
