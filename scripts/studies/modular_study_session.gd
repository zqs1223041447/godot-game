extends RefCounted
## Research-only installation on an already admitted old_garden roster.
## Formal map definitions and normal saves are never modified by this adapter.
const StudyGeometry = preload("res://scripts/studies/modular_study_geometry.gd")
const MANIFEST := "res://art-studies/v111/exports/manifest.json"
const COLLISIONS := "res://art-studies/v111/exports/collisions.json"
const ASSEMBLY := "res://art-studies/v111/exports/assembly-layout.json"
const HERO := "res://assets/actors/studies/hero_direction_study.json"
const ORIGIN_FROM_BOUNDS := Vector2(450, 1450)

static func layout(bounds: Rect2) -> Dictionary:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var collisions: Variant = JSON.parse_string(FileAccess.get_file_as_string(COLLISIONS))
	var assembly: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSEMBLY))
	if not manifest is Dictionary or not collisions is Dictionary or not assembly is Dictionary:
		return {"ok": false, "error": "Study source JSON unavailable"}
	var unit_zoom: float = manifest.projection.camera2d_zoom
	if not is_equal_approx(unit_zoom, 0.65): return {"ok": false, "error": "Unsupported source projection"}
	var instances: Array[Dictionary] = []
	var polygons: Array[PackedVector2Array] = []
	var origin := bounds.position + ORIGIN_FROM_BOUNDS
	var probes: Array[Vector2] = []
	for source: Dictionary in assembly.instances:
		var position := origin + Vector2(source.foot_screen_pixel[0], source.foot_screen_pixel[1]) / unit_zoom
		instances.append({"id": str(source.id), "module_id": str(source.module), "position": position})
		for probe: Array in source.probe_points_screen_pixel:
			probes.append(origin + Vector2(probe[0], probe[1]) / unit_zoom)
		var found := false
		for record: Dictionary in collisions.modules:
			if str(record.module_id) != str(source.module): continue
			found = true
			for polygon: Dictionary in record.polygons:
				var points := PackedVector2Array()
				for local_point: Array in polygon.outer.godot_local_world:
					# Already world units; never divide this array by zoom again.
					points.append(position + Vector2(local_point[0], local_point[1]))
				polygons.append(points)
		if not found: return {"ok": false, "error": "Missing matching module collider"}
	var gate_position: Vector2 = instances[1].position
	var portal: Dictionary = collisions.portal_validation.verified_centerline
	var gate_front := gate_position + Vector2(portal.start.godot_local_world[0], portal.start.godot_local_world[1])
	var gate_rear := gate_position + Vector2(portal.end.godot_local_world[0], portal.end.godot_local_world[1])
	return {"ok": true, "polygons": polygons, "instances": instances, "solid_probes": probes,
		"gate_front": gate_front, "gate_rear": gate_rear,
		"presentation": {"module_instances": instances, "study_origin": origin, "source_map_id": "old_garden"}}

static func install(arena: Node2D, use_static_hero: bool = true) -> Dictionary:
	if arena.world_context().mode != "map" or str(arena._map_run.profile.id) != "old_garden" or arena.enemies.size() != 25:
		return {"ok": false, "error": "Requires one freshly admitted 25-root old_garden study map"}
	var prepared := layout(arena.ARENA)
	if not prepared.ok: return prepared
	var candidate = StudyGeometry.new()
	var installed: Dictionary = candidate.install(arena.ARENA, prepared.polygons, arena.player_pos, prepared.presentation)
	if not installed.ok: return installed
	# Freeze Main while the isolated native static space receives its shapes.
	var processing := arena.is_processing()
	arena.set_process(false)
	await arena.get_tree().physics_frame
	await arena.get_tree().physics_frame
	if not candidate.physics_ready():
		arena.set_process(processing)
		return {"ok": false, "error": "Study collision space not ready"}
	if not candidate.is_clear(arena.player_pos, arena.PLAYER_RADIUS):
		arena.set_process(processing)
		return {"ok": false, "error": "Study entry intersects an obstacle"}
	for enemy: Dictionary in arena.enemies:
		if not candidate.is_clear(enemy.pos, float(enemy.radius)):
			arena.set_process(processing)
			return {"ok": false, "error": "Study root %d intersects an obstacle; no remapping committed" % int(enemy.id)}
	var hero_definition: Dictionary = {}
	if use_static_hero:
		hero_definition = JSON.parse_string(FileAccess.get_file_as_string(HERO))
		var hero_check: Dictionary = load("res://scripts/visuals/actor_sprite_catalog.gd").prepare_presentation(hero_definition)
		if not hero_check.ok:
			arena.set_process(processing)
			return {"ok": false, "error": hero_check.reason}
	var original_geometry: Variant = arena._geometry
	arena._geometry = candidate
	arena._refresh_world_geometry()
	var props: Dictionary = arena.dimensional_props.diagnostics()
	if not str(props.get("study_error", "")).is_empty():
		arena._geometry = original_geometry
		arena._refresh_world_geometry()
		arena.set_process(processing)
		return {"ok": false, "error": props.study_error}
	if use_static_hero:
		var selected: Dictionary = arena.retained_actors.set_hero_presentation(hero_definition)
		if not selected.ok:
			arena._geometry = original_geometry
			arena._refresh_world_geometry()
			arena.set_process(processing)
			return {"ok": false, "error": selected.reason}
	arena.retained_actors.sync(arena)
	arena.set_process(processing)
	return {"ok": true, "error": "", "geometry": candidate, "layout": prepared, "roots": 25, "remapped_roots": 0}
