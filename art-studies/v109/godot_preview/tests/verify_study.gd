extends SceneTree
## Bounded functional checks, not screenshots, FPS or animation acceptance.

const Study := preload("res://study.gd")
var checks: Array[Dictionary] = []
var failure_count := 0
var report: Dictionary = {"scope": "Headless layer, foot-anchor, physics, sort-contract and lifecycle checks only", "native_visual_review": "not_run", "fps_benchmark": "not_run", "animation_acceptance": "not_applicable_static_direction_images"}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		failure_count += 1
	print(("PASS " if passed else "FAIL ") + label + (" " + str(detail) if detail != null else ""))

func run() -> void:
	var scene := Study.new()
	root.add_child(scene)
	await physics_frame
	await process_frame
	scene.player.accept_input = false
	check("manifest_and_png_load", scene.load_errors.is_empty(), scene.load_errors)
	check("all_30_source_layers_loaded_28_visible", scene.loaded_images == 30 and scene.drawn_layers == 28, [scene.loaded_images, scene.drawn_layers])
	check("20_bodies_21_separate_polygons", scene.collider_nodes.size() == 20 and count_polygons(scene) == 21)
	check("two_gate_legs_retained", scene.collider_nodes.object_00.get_child_count() == 2)
	check("ground_and_detail_are_always_behind", scene.background_root.z_index == -1 and scene.background_root.get_child_count() == 2)
	check("diagnostics_off_by_default", not scene.debug_visible)
	var positions_ok := true
	var source_polygons_ok := true
	for entry in scene.manifest.layers:
		if not entry.visible_in_original:
			continue
		var parent: Node2D = scene.sorted_root if entry.sort_mode == "y_sort" else scene.background_root
		var node: Node2D = parent.get_node(str(entry.id))
		var sprite: Sprite2D = node.get_child(0)
		var corner := node.position + sprite.offset
		positions_ok = positions_ok and corner.distance_to(Vector2(entry.source_rect_pixel.x, entry.source_rect_pixel.y)) < 0.001
	for entry in scene.manifest.colliders:
		var body: StaticBody2D = scene.collider_nodes[entry.id]
		for i in entry.polygons.size():
			var actual: PackedVector2Array = body.get_child(i).polygon
			var expected: PackedVector2Array = scene.points(entry.polygons[i].screen_pixel)
			source_polygons_ok = source_polygons_ok and actual == expected and body.transform == Transform2D.IDENTITY
	check("layer_pixels_land_at_manifest_crop", positions_ok)
	check("collision_screen_points_unmodified", source_polygons_ok)

	var feet_ok := true
	for index in 8:
		scene.player.set_direction(index)
		var foot_in_parent: Vector2 = scene.player.sprite.position + (scene.player.sprite.offset + scene.player.FEET[index]) * scene.player.sprite.scale
		feet_ok = feet_ok and foot_in_parent.length() < 0.001
		var vector := Vector2.RIGHT.rotated(index * PI / 4.0)
		feet_ok = feet_ok and scene.player.direction_from_vector(vector) == index
	check("eight_direction_idle_regions_keep_same_physics_foot", feet_ok)

	var front: Vector2 = scene.point(scene.manifest.gate_check.front_foot_screen_pixel)
	var rear: Vector2 = scene.point(scene.manifest.gate_check.rear_foot_screen_pixel)
	var result := KinematicCollision2D.new()
	var blocked := scene.player.test_move(Transform2D(0, front), rear - front, result)
	check("gate_center_sweep_clear_at_14_22px_radius", not blocked)
	var forward := await drive(scene.player, front, rear, 90)
	check("character_moves_through_gate_front_to_rear", forward.reached and forward.contacts == 0, forward)
	var backward := await drive(scene.player, rear, front, 90)
	check("character_moves_through_gate_rear_to_front", backward.reached and backward.contacts == 0, backward)

	var gate: Dictionary = scene.manifest.colliders[0]
	for i in gate.polygons.size():
		var polygon: PackedVector2Array = scene.points(gate.polygons[i].screen_pixel)
		var bounds := polygon_bounds(polygon)
		var start := Vector2(bounds.get_center().x, bounds.end.y + 46.0)
		var target := bounds.get_center()
		var hit := KinematicCollision2D.new()
		var did_hit := scene.player.test_move(Transform2D(0, start), target - start, hit)
		var id := "" if not did_hit else str(hit.get_collider().get_meta("collider_id", ""))
		check("gate_leg_%d_blocks_sweep" % i, did_hit and id == "object_00", id)
		var movement := await drive(scene.player, start, target, 70)
		check("gate_leg_%d_blocks_character" % i, not movement.reached and movement.contacts > 0 and movement.last_contact == "object_00", movement)
		check("gate_leg_%d_no_foot_penetration" % i, not Geometry2D.is_point_in_polygon(scene.player.position, polygon))

	var rock_start := Vector2(265, 649)
	var rock_target := Vector2(275, 514)
	var rock_hit := KinematicCollision2D.new()
	var rock_blocked := scene.player.test_move(Transform2D(0, rock_start), rock_target - rock_start, rock_hit)
	var rock_id := "" if not rock_blocked else str(rock_hit.get_collider().get_meta("collider_id", ""))
	check("rock_blocks_sweep", rock_blocked and rock_id == "object_08", rock_id)
	var rock_movement := await drive(scene.player, rock_start, rock_target, 90)
	check("rock_blocks_character", not rock_movement.reached and rock_movement.contacts > 0, rock_movement)

	var sort_ok: bool = scene.sorted_root.y_sort_enabled and scene.player.get_parent() == scene.sorted_root
	var order: Array[String] = []
	var sorted: Array = scene.prop_nodes.values()
	sorted.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y < b.position.y)
	for prop in sorted:
		order.append(prop.name)
		sort_ok = sort_ok and prop.z_index == scene.player.z_index and not prop.y_sort_enabled
	var expected_order: Array[String] = []
	for id in scene.manifest.default_draw_order:
		if scene.prop_nodes.has(id):
			expected_order.append(id)
	check("shared_foot_y_sort_matches_frozen_prop_order", sort_ok and order == expected_order)
	var arch: Node2D = scene.prop_nodes.arch_00
	scene.player.position = rear
	check("character_behind_arch_at_rear", scene.player.position.y < arch.position.y)
	scene.player.position = front
	check("character_in_front_of_arch_at_front", scene.player.position.y > arch.position.y)
	# The full ground threshold must never enter the sorted prop branch.
	check("threshold_in_ground_contract", scene.background_root.has_node("00_ground") and not scene.sorted_root.has_node("00_ground"))
	scene.reset_player()
	check("reset_restores_spawn_idle", scene.player.position == scene.SPAWN_POINT and scene.player.direction_index == 2 and scene.player.velocity == Vector2.ZERO)
	check("no_animation_or_gameplay_nodes", scene.find_children("*", "AnimationPlayer", true, false).is_empty() and scene.find_children("*", "AnimatedSprite2D", true, false).is_empty())
	# Drop local node references before verifying complete scene teardown.
	sorted.clear()
	scene.queue_free()
	await process_frame
	await process_frame
	await physics_frame
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var baseline_resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var lifecycle: Array[Dictionary] = []
	for cycle in 3:
		var next_scene := Study.new()
		root.add_child(next_scene)
		await physics_frame
		await process_frame
		next_scene.player.accept_input = false
		next_scene.queue_free()
		await process_frame
		await process_frame
		await physics_frame
		lifecycle.append({"cycle": cycle + 1, "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))})
	var stable := true
	for row in lifecycle:
		stable = stable and row.nodes == baseline_nodes and row.resources <= baseline_resources
	check("three_scene_load_free_cycles_stable", stable, {"baseline_nodes": baseline_nodes, "baseline_resources": baseline_resources, "cycles": lifecycle})
	report.checks = checks
	report.failures = failure_count
	report.passed = failure_count == 0
	report.character_radius_pixel = 14.2222222222
	report.coordinate_space = "identity screen_pixel; no Camera2D zoom; original collision points preserved"
	var file := FileAccess.open("res://qa/headless-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("RESULT: %d checks, %d failures" % [checks.size(), failure_count])
	quit(0 if failure_count == 0 else 1)

func count_polygons(scene: Node2D) -> int:
	var count := 0
	for body in scene.collider_nodes.values():
		count += body.get_child_count()
	return count

func polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for vertex in polygon:
		bounds = bounds.expand(vertex)
	return bounds

func drive(player: CharacterBody2D, start: Vector2, target: Vector2, max_ticks: int) -> Dictionary:
	player.test_direction = Vector2.ZERO
	player.position = start
	player.velocity = Vector2.ZERO
	player.contact_count = 0
	player.last_contact_id = ""
	await physics_frame
	await process_frame
	var reached := false
	var ticks := 0
	while ticks < max_ticks:
		if player.position.distance_to(target) <= 3.0:
			reached = true
			break
		player.test_direction = (target - player.position).normalized()
		await physics_frame
		await process_frame
		ticks += 1
	player.test_direction = Vector2.ZERO
	player.velocity = Vector2.ZERO
	return {"reached": reached, "ticks": ticks, "end_pixel": [player.position.x, player.position.y], "distance_to_target": player.position.distance_to(target), "contacts": player.contact_count, "last_contact": player.last_contact_id}
