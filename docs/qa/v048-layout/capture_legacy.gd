extends SceneTree
## Run this identical external script once with the v47 PCK and once with v48.
## Store Variant bytes, not JSON, to retain exact fields, types and float values.
const Maps = preload("res://scripts/world/map_compiler.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const State = preload("res://scripts/world/map_camp_state.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Camps = preload("res://scripts/world/map_camp_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const BOUNDS := Rect2(Vector2(42, 104), Vector2(1196, 462) / 0.65)
var failures := 0


func _initialize() -> void:
	var result := {"geometry": [], "profiles": []}
	_capture_geometry(result.geometry)
	for map_id: String in ["old_garden", "broken_ruins"]:
		for tier: int in [0, 1, 2, 3]:
			for modified: bool in [false, true]:
				var normal: Array = ["enemy_max_health_120", "enemy_shield_from_health_20"] if modified else []
				var compiled := Maps.compile(map_id, normal, []) if tier == 0 else Maps.compile_normal(map_id, tier, normal, [])
				var special: Array = []
				if modified and compiled.profile.wave >= 4: special = ["frost_patrol"] if map_id == "old_garden" else ["elemental_aegis"]
				compiled = Maps.compile(map_id, normal, special) if tier == 0 else Maps.compile_normal(map_id, tier, normal, special)
				var profile: Dictionary = compiled.profile
				var layout := Layout.layout(map_id, BOUNDS)
				var geometry := Geometry.new()
				geometry.configure(map_id, BOUNDS)
				for seed_value: int in [0, 43, 4348]:
					var state := State.new()
					if not state.begin(profile, layout.landmarks, seed_value).ok:
						failures += 1
						continue
					var runtime := Runtime.new()
					var groups: Array = []
					for mark: Dictionary in layout.landmarks.camps:
						var admitted := Camps.plan(runtime, profile, state.entries(mark.id), geometry, mark.trigger_center, 100 - groups.size() * mark.root_count)
						if not admitted.ok: failures += 1
						groups.append(admitted)
						if admitted.ok:
							Encounter._restore(runtime, admitted.runtime_checkpoint)
							var ids: Array[int] = []
							for enemy: Dictionary in admitted.enemies: ids.append(enemy.id)
							state.activate(mark.id, ids)
					var boss: Dictionary = layout.landmarks.boss
					var boss_entries: Array[Dictionary] = [{"template_id": profile.boss_id, "rarity": "", "mechanisms": [], "position": boss.center}]
					var boss_result := Camps.plan(Runtime.new(), profile, boss_entries, geometry, boss.trigger_center, 100, "map_boss")
					if not boss_result.ok: failures += 1
					result.profiles.append({"profile": profile, "layout": layout, "seed": seed_value,
						"state": state.checkpoint(), "groups": groups, "boss": boss_result, "states": state.states({})})
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output_path = argument.trim_prefix("--out=")
	if output_path.is_empty():
		push_error("Pass -- --out=/absolute/path.bin")
		quit(1)
		return
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if not output:
		push_error("Cannot write baseline bytes")
		quit(1)
		return
	var bytes := var_to_bytes(result)
	output.store_buffer(bytes)
	output.close()
	print("Legacy layout capture: %d profile/seed cases; %d geometry cases; %d bytes; %d failures" % [result.profiles.size(), result.geometry.size(), bytes.size(), failures])
	quit(1 if failures else 0)


func _capture_geometry(results: Array) -> void:
	for map_id: String in ["normal", "town", "old_garden", "broken_ruins"]:
		for origin: Vector2 in [BOUNDS.position, Vector2(-317, 801)]:
			var geometry := Geometry.new()
			geometry.configure(map_id, Rect2(origin, BOUNDS.size))
			var operations: Array = []
			for radius: float in [0.0, 6.0, 10.0, 14.0, 22.0, 27.5]:
				for pair: Array in [
					[Vector2(200, 150), Vector2(1400, 350)],
					[Vector2(920, 670), Vector2(920, 130)],
					[Vector2(500, 320), Vector2(1300, 320)],
					[Vector2(608, 300), Vector2(1208, 400)],
					[Vector2(20, 20), Vector2(1820, 690)],
				]:
					var start: Vector2 = origin + pair[0]
					var goal: Vector2 = origin + pair[1]
					operations.append([geometry.is_clear(start, radius), geometry.legal_point(start, radius),
						geometry.sweep(start, goal, radius), geometry.visible(start, goal, radius),
						geometry.move(start, goal, radius), geometry.direction(start, goal, radius, 8.0)])
			results.append({"snapshot": geometry.snapshot(), "operations": operations, "routes": geometry._routes.duplicate(true)})
