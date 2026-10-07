extends SceneTree
## Only the new ground shadow and adjacent invariants; no broad suite rerun.

const Study := preload("res://study.gd")
var checks: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)

func run() -> void:
	var scene := Study.new()
	root.add_child(scene)
	await physics_frame
	await process_frame
	scene.player.accept_input = false
	var shadow: Node2D = scene.ground_shadow
	check("cast_and_contact_resources_present", shadow.cast_sprite.texture == scene.player.sprite.texture and shadow.cast_material.shader != null and shadow.contact_material.shader != null)
	check("ground_shadow_after_ground_before_all_props", shadow.z_index == -1 and shadow.get_index() > scene.background_root.get_index() and scene.sorted_root.z_index == 0)
	check("shadow_never_enters_character_y_sort", shadow.get_parent() == scene and shadow.get_parent() != scene.sorted_root)
	var feet_ok := true
	var directions_ok := true
	for index in 8:
		scene.player.position = Vector2(530 + index * 4, 430 - index * 2)
		scene.player.set_direction(index)
		shadow.update_from_player()
		var cast_foot: Vector2 = shadow.cast_sprite.transform * (shadow.cast_sprite.offset + scene.player.FEET[index])
		feet_ok = feet_ok and shadow.global_position == scene.player.global_position and cast_foot.length() < 0.001
		directions_ok = directions_ok and shadow.cast_sprite.region_rect == scene.player.sprite.region_rect and shadow.current_direction == index
	check("all_eight_static_directions_keep_shadow_on_foot", feet_ok)
	check("shadow_reuses_exact_idle_source_regions", directions_ok)
	var tip: Vector2 = shadow.cast_sprite.transform * Vector2(0, -48.9451892353 / scene.player.ART_SCALE)
	var expected: Vector2 = shadow.SHADOW_SCREEN_PER_METRE_HEIGHT * 1.8 * shadow.CAST_LENGTH_GAIN
	check("projection_matches_environment_right_up_light", tip.distance_to(expected) < 0.001 and tip.x > 0 and tip.y < 0, {"tip_pixel_for_1p8m": [tip.x, tip.y], "length_gain": shadow.CAST_LENGTH_GAIN})
	check("shadow_is_subtle_non_additive", shadow.CAST_OPACITY <= 0.22 and shadow.CONTACT_OPACITY <= 0.30 and "blend_mix" in shadow.cast_material.shader.code and "blend_mix" in shadow.contact_material.shader.code)
	check("contact_quad_small_and_below_actor", shadow.contact_mesh.mesh.size == Vector2(32, 12) and shadow.contact_mesh.position == Vector2.ZERO)
	var front: Vector2 = scene.point(scene.manifest.gate_check.front_foot_screen_pixel)
	var rear: Vector2 = scene.point(scene.manifest.gate_check.rear_foot_screen_pixel)
	check("gate_sweep_unchanged", not scene.player.test_move(Transform2D(0, front), rear - front))
	check("physics_nodes_unchanged", scene.collider_nodes.size() == 20 and scene.collider_nodes.object_00.get_child_count() == 2 and is_equal_approx(scene.player.footprint.shape.radius, 14.2222222222))
	scene.reset_player()
	shadow.update_from_player()
	check("reset_reanchors_both_shadow_parts", shadow.global_position == scene.SPAWN_POINT and shadow.current_direction == 2)
	var shadow_ref: WeakRef = weakref(shadow)
	var material_ref: WeakRef = weakref(shadow.cast_material)
	scene.queue_free()
	await process_frame
	await process_frame
	check("shadow_freed_with_scene", shadow_ref.get_ref() == null and material_ref.get_ref() == null)
	var report := {"scope": "Focused static-character ground-shadow checks only", "passed": failures == 0, "failures": failures, "checks": checks, "native_visual_review": "pending_parent", "lighting_source": "v108-professional-environment/build_scene.py:167 and projection-godot.json", "limits": ["Fixed-direction 2D alpha projection, artistically shortened to 62 percent; not real-time 3D lighting", "No animation, collision, game-flow or asset change", "No screenshot, FPS, broad 27+74 suite or long-duration rerun"]}
	var file := FileAccess.open("res://qa/shadow-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("RESULT: %d focused checks, %d failures" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)
