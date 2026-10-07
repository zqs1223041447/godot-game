extends SceneTree
## Focused retained-decoration integration. No combat, migration suite or render.
const Session = preload("res://scripts/studies/modular_study_session.gd")
const Dressing = preload("res://scripts/visuals/ruins_garden_ground_dressing.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var instance_report: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("GROUND_DRESSING_FAIL: " + label)
	return value
func accepted(result: Dictionary, label: String) -> bool:
	return check(result.get("ok", false), label + ": " + str(result.get("reason", "")))
func nodes_below(node: Node) -> Array[Node]:
	var nodes: Array[Node] = [node]
	for child: Node in node.get_children(): nodes.append_array(nodes_below(child))
	return nodes
func authority() -> PackedByteArray:
	return var_to_bytes([arena.world_geometry(), arena.state.snapshot(), FileAccess.get_file_as_bytes(arena.build_save_path),
		Encounter._snapshot(arena.monster_runtime), arena.enemies, arena.rng.seed, arena.rng.state])
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v118-") or FileAccess.file_exists("user://build_save.json"):
		printerr("GROUND_DRESSING_BLOCKED: fresh isolated XDG storage required"); quit(78); return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	for unused in range(4): arena.hud.close_panel()
	if not check(arena.save_build(), "Current-schema isolated fixture saves normally"): finish(); return
	if not accepted(arena.craft_normal_map("ruins_garden", 1, [], [], arena.map_draft().revision), "Prepare native garden fixture"): finish(); return
	if not accepted(await arena.open_map(arena.map_draft().revision), "Enter actual native map once"): finish(); return
	var manager: RefCounted = arena.dimensional_props
	var dressing: Node2D = manager._ground_dressing
	if not check(is_instance_valid(dressing) and manager.diagnostics().ground_dressing_error.is_empty(), "Native map owns its retained dressing with no resource error"):
		finish(); return
	var diagnostic: Dictionary = dressing.diagnostics()
	check(diagnostic.ready and diagnostic.instance_count == 5 and diagnostic.sprite_count == 10
		and diagnostic.image_loads == 4 and diagnostic.builds == 1, "Five fixed decorations share exactly four loaded images and one build")
	check(dressing.get_parent() == arena.world_depth and dressing.z_index == -1 and not dressing.z_as_relative
		and not dressing.y_sort_enabled and not dressing.is_processing() and not dressing.is_physics_processing(),
		"Decoration subtree is fixed below the actor/monster/prop layer and runs no frame or physics callback")
	check(arena.world_depth.z_index == 0 and arena.foreground_layer.z_index >= 0 and arena.static_environment.z_index == -1,
		"Absolute ground depth is below actual actors and foreground/drop draw passes")
	var shadow_batch: Node2D = dressing.get_node("GroundShadows")
	var detail_batch: Node2D = dressing.get_node("GroundDetails")
	check(shadow_batch.get_index() < detail_batch.get_index() and shadow_batch.get_child_count() == 5
		and detail_batch.get_child_count() == 5 and not shadow_batch.y_sort_enabled and not detail_batch.y_sort_enabled,
		"Five shadows precede five details in unsorted ground batches")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Dressing.MANIFEST))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Dressing.LAYOUT))
	var definitions: Dictionary = {}
	for module: Dictionary in manifest.modules: definitions[module.id] = module
	var textures: Dictionary = {}
	var counts := {"fern_low": 0, "pebble_trio": 0}
	var origin: Vector2 = arena.world_geometry().study_origin
	for instance: Dictionary in source.instances:
		counts[instance.module] += 1
		var expected := origin + Vector2(instance.foot_screen_pixel[0], instance.foot_screen_pixel[1]) / 0.65
		for layer: String in ["shadow", "sprite"]:
			var batch := shadow_batch if layer == "shadow" else detail_batch
			var anchor: Node2D = batch.get_node(instance.id)
			var sprite: Sprite2D = anchor.get_child(0)
			var data: Dictionary = definitions[instance.module][layer]
			var foot := Vector2(data.foot_local_pixel[0], data.foot_local_pixel[1])
			check(anchor.position.is_equal_approx(expected) and sprite.position.is_equal_approx(-foot / 0.65)
				and sprite.scale.is_equal_approx(Vector2.ONE / 0.65) and not sprite.centered,
				"Approved foot and image offset convert once: " + instance.id + "/" + layer)
			check(anchor.rotation == 0 and sprite.rotation == 0 and not sprite.flip_h and not sprite.flip_v,
				"Baked orientation is unchanged: " + instance.id + "/" + layer)
			var key: String = instance.module + "/" + layer
			if textures.has(key): check(sprite.texture == textures[key], "Instances share the same image resource: " + key)
			else: textures[key] = sprite.texture
			check(sprite.texture.get_width() == data.source_pixel_rect.width and sprite.texture.get_height() == data.source_pixel_rect.height,
				"Runtime image dimensions match the approved PNG: " + key)
		instance_report.append({"id": instance.id, "module": instance.module, "world_foot": expected})
	check(counts == {"fern_low": 3, "pebble_trio": 2} and textures.size() == 4, "Exact approved three-fern/two-pebble distribution is retained")
	var harmless := true
	for node: Node in nodes_below(dressing):
		harmless = harmless and not node is CollisionObject2D and not node is NavigationObstacle2D
		harmless = harmless and not node is NavigationRegion2D and not node is CollisionShape2D and not node is CollisionPolygon2D
	check(harmless, "The complete decoration subtree contains no collision or navigation objects")
	var polygon_snapshot: Dictionary = Session.layout(arena.ARENA, "ruins_garden")
	check(arena.world_geometry().module_polygons == polygon_snapshot.polygons, "Authoritative native contours remain byte-equivalent to the original assembly")
	var before := authority()
	var sprite_ids := []
	for node: Node in nodes_below(dressing): sprite_ids.append(node.get_instance_id())
	seed(11801)
	var expected_random := randi()
	seed(11801)
	for unused in range(8): manager.configure(arena.world_depth, arena.world_geometry())
	check(randi() == expected_random and authority() == before, "Presentation refresh does not mutate geometry, save, actors or gameplay/global RNG")
	var camera: Camera2D = arena.get_node("WorldCamera")
	var old_camera := camera.position
	camera.position += Vector2(80, 40)
	manager.configure(arena.world_depth, arena.world_geometry())
	camera.position = old_camera
	var after_ids := []
	for node: Node in nodes_below(manager._ground_dressing): after_ids.append(node.get_instance_id())
	check(after_ids == sprite_ids and dressing.diagnostics() == diagnostic, "Camera movement and repeated map refresh retain every node, texture and single build")
	var texture_refs: Array[WeakRef] = []
	for texture: Texture2D in textures.values(): texture_refs.append(weakref(texture))
	textures.clear()
	if not accepted(arena.return_to_town(arena.world_context().revision), "Actual map exit switches to town"): finish(); return
	await process_frame
	check(not is_instance_valid(dressing) and manager._ground_dressing == null and manager.diagnostics().ground_dressing.is_empty(),
		"Map exit frees both ground batches and all decoration instances")
	var freed := true
	for reference: WeakRef in texture_refs: freed = freed and reference.get_ref() == null
	check(freed, "Map exit releases the four decoration image resources")
	var unrelated_depth := Node2D.new()
	root.add_child(unrelated_depth)
	var other = load("res://scripts/visuals/dimensional_prop_manager.gd").new()
	for id: String in ["old_garden", "broken_ruins", "sunwell_terrace", "ginkgo_arcade"]:
		var geometry = load("res://scripts/world/map_geometry.gd").new()
		check(geometry.configure_exploration(id, arena.View.exploration_arena()), "Original map geometry still configures: " + id)
		other.configure(unrelated_depth, geometry.snapshot())
		check(other._ground_dressing == null and other.diagnostics().ground_dressing.is_empty(), "No dressing is added to the old map: " + id)
	other.clear()
	unrelated_depth.queue_free()
	finish()
func finish() -> void:
	var result := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "instances": instance_report,
		"method": "One actual native map entry, retained ground resource/depth/placement/refresh/exit checks and four old presentation dispatches; no combat or rendering"}
	var output := FileAccess.open("res://docs/qa/v118-ground-dressing/result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n"); output.close()
	print("GROUND_DRESSING_RESULT " + JSON.stringify(result))
	if is_instance_valid(arena): arena.queue_free()
	quit(1 if not failures.is_empty() else 0)
