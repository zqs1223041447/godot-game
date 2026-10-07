extends Node2D
## Real exported module sprites, no scene-sized baked props and no fake lights.
## Pixel-space variant of the manifest contract: no Camera2D zoom conversion.

var manifest: Dictionary
var collision_data: Dictionary
var layout: Dictionary
var modules: Dictionary = {}
var colliders: Dictionary = {}
var textures: Dictionary = {}
var physical_bodies: Array[StaticBody2D] = []
var ground: Sprite2D
var debug_layer: Node2D
var debug_visible := false
var report: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	manifest = _read_json("res://exports/manifest.json")
	collision_data = _read_json("res://exports/collisions.json")
	layout = _read_json("res://exports/assembly-layout.json")
	for entry: Dictionary in manifest.modules:
		modules[str(entry.id)] = entry
	for entry: Dictionary in collision_data.modules:
		colliders[str(entry.module_id)] = entry
	ground = _sprite(str(layout.background), Vector2.ZERO)
	ground.name = "IndependentGroundOnlyRender"
	ground.z_index = -4
	add_child(ground)
	var shadow_root := Node2D.new()
	shadow_root.name = "NeutralGroundShadowDecals"
	shadow_root.z_index = -3
	add_child(shadow_root)
	var ground_details := Node2D.new()
	ground_details.name = "WalkableSillGroundLayer"
	ground_details.z_index = -2
	add_child(ground_details)
	var visual_root := Node2D.new()
	visual_root.name = "FootSortedAbovegroundModules"
	visual_root.y_sort_enabled = true
	add_child(visual_root)
	for inst: Dictionary in layout.instances:
		var module: Dictionary = modules[str(inst.module)]
		var foot := point(inst.foot_screen_pixel)
		_add_part(shadow_root, module.shadow, foot, str(inst.id) + "_shadow")
		if module.has("ground_detail"):
			_add_part(ground_details, module.ground_detail, foot, str(inst.id) + "_sill")
		_add_part(visual_root, module.sprite, foot, str(inst.id) + "_visual")
		var index := 0
		for poly: Dictionary in colliders[str(inst.module)].polygons:
			var body := StaticBody2D.new()
			body.name = str(inst.id) + "_blocker_" + str(index)
			body.position = foot
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("instance_id", inst.id)
			body.set_meta("polygon_index", index)
			add_child(body)
			var shape := CollisionPolygon2D.new()
			shape.polygon = points(poly.outer.foot_relative_screen_pixel)
			body.add_child(shape)
			physical_bodies.append(body)
			index += 1
	debug_layer = Node2D.new()
	debug_layer.name = "QADebugOnly"
	debug_layer.z_index = 10
	add_child(debug_layer)
	debug_layer.draw.connect(_draw_debug)
	_add_caption()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run_physics_checks()
	var args := OS.get_cmdline_user_args()
	if "--qa" in args:
		get_tree().quit(0 if report.result == "PASS" else 1)
	else:
		for arg: String in args:
			if arg.begins_with("--capture="):
				await RenderingServer.frame_post_draw
				var destination := arg.trim_prefix("--capture=")
				var capture := get_viewport().get_texture().get_image()
				print("NATIVE_CAPTURE: ", capture.save_png(destination), " ", destination)


func _read_json(path: String) -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(result is Dictionary, "Missing or invalid JSON: " + path)
	return result


func _sprite(path: String, offset: Vector2) -> Sprite2D:
	if not textures.has(path):
		var image := Image.load_from_file("res://" + path)
		assert(image != null and not image.is_empty(), "Missing export " + path)
		textures[path] = ImageTexture.create_from_image(image)
	var result := Sprite2D.new()
	result.texture = textures[path]
	result.centered = false
	result.offset = offset
	return result


func _add_part(parent: Node2D, record: Dictionary, foot: Vector2, label: String) -> void:
	var anchor := Node2D.new()
	anchor.name = label
	anchor.position = foot
	anchor.set_meta("physical_foot_screen_pixel", foot)
	parent.add_child(anchor)
	anchor.add_child(_sprite(str(record.image), -point(record.foot_local_pixel)))


func _add_caption() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	var panel := ColorRect.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(700, 64)
	panel.color = Color(0.05, 0.08, 0.065, 0.87)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	var text := Label.new()
	text.position = Vector2(30, 24)
	text.text = "3 REAL MODULES  |  native Godot assembly\n55 deg / fixed sunlight / flat ground   |   F1 colliders   F2 ground   Esc close"
	text.add_theme_font_size_override("font_size", 17)
	canvas.add_child(text)


func _run_physics_checks() -> void:
	var px := float(manifest.projection.source_pixel_per_ground_m_x)
	var py := float(manifest.projection.source_pixel_per_ground_m_y)
	# A projected metre-space circle is an ellipse, not a same-radius screen circle.
	# Circumscribe 64 sides to remain conservative by less than 0.13%.
	var character := ConvexPolygonShape2D.new()
	var ellipse := PackedVector2Array()
	var inflation := 1.0 / cos(PI / 64.0)
	for index in range(64):
		var angle := TAU * float(index) / 64.0
		ellipse.append(Vector2(cos(angle)*0.3*px, sin(angle)*0.3*py)*inflation)
	character.points = ellipse
	var gate: Dictionary = {}
	for inst: Dictionary in layout.instances:
		if inst.module == "walkable_arch":
			gate = inst
	var foot := point(gate.foot_screen_pixel)
	var line: Dictionary = collision_data.portal_validation.verified_centerline
	var start := foot + point(line.start.foot_relative_screen_pixel)
	var finish := foot + point(line.end.foot_relative_screen_pixel)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = character
	query.collision_mask = 1
	query.margin = 0.0
	query.transform = Transform2D(0.0, start)
	query.motion = finish - start
	var space := get_world_2d().direct_space_state
	var forward := space.cast_motion(query)
	query.transform = Transform2D(0.0, finish)
	query.motion = start - finish
	var reverse := space.cast_motion(query)
	var probes: Array = []
	var probes_pass := true
	for inst: Dictionary in layout.instances:
		var index := 0
		for raw: Array in inst.probe_points_screen_pixel:
			var probe := PhysicsPointQueryParameters2D.new()
			probe.position = point(raw)
			probe.collision_mask = 1
			var hits := space.intersect_point(probe)
			var expected_hit := false
			for hit: Dictionary in hits:
				var body: Object = hit.collider
				if body.get_meta("instance_id", "") == inst.id and int(body.get_meta("polygon_index", -1)) == index:
					expected_hit = true
			probes_pass = probes_pass and expected_hit
			probes.append({"instance": inst.id, "polygon_index": index, "blocked": expected_hit})
			index += 1
	var samples_clear := true
	for index in range(201):
		query.motion = Vector2.ZERO
		query.transform = Transform2D(0.0, start.lerp(finish, float(index)/200.0))
		if not space.intersect_shape(query).is_empty():
			samples_clear = false
	var passed := forward[0] == 1.0 and reverse[0] == 1.0 and probes_pass and samples_clear
	report = {
		"result": "PASS" if passed else "FAIL",
		"godot_version": Engine.get_version_info().string,
		"module_instances": layout.instances.size(),
		"static_blocker_bodies": physical_bodies.size(),
		"loaded_png_images": textures.size(),
		"arch_two_separate_blockers": colliders.walkable_arch.polygons.size() == 2,
		"character_radius_metres": 0.3,
		"projected_body_shape": "64-sided conservative projected ellipse, <0.13% radius inflation",
		"forward_safe_fraction": forward[0], "reverse_safe_fraction": reverse[0],
		"all_201_portal_sweep_poses_clear": samples_clear,
		"solid_blocker_probes": probes,
		"scope": "Native Godot PhysicsServer2D on the assembled layout; no actor animation, 3D stepping or complete game integration test",
		"visual_capture": false,
	}
	var file := FileAccess.open("res://qa/godot-physics-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("GODOT_ASSEMBLY_PHYSICS_", report.result, ": ", JSON.stringify(report))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F1:
		debug_visible = not debug_visible
		debug_layer.queue_redraw()
	elif event.physical_keycode == KEY_F2:
		ground.visible = not ground.visible
	elif event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()


func _draw_debug() -> void:
	if not debug_visible:
		return
	for inst: Dictionary in layout.instances:
		var foot := point(inst.foot_screen_pixel)
		for poly: Dictionary in colliders[str(inst.module)].polygons:
			var outline := points(poly.outer.foot_relative_screen_pixel)
			for index in range(outline.size()):
				outline[index] += foot
			debug_layer.draw_colored_polygon(outline, Color(0.2,0.9,1.0,0.24))
			outline.append(outline[0])
			debug_layer.draw_polyline(outline, Color(0.2,0.9,1.0,1), 2.0, true)
		debug_layer.draw_line(foot-Vector2(8,0),foot+Vector2(8,0),Color.WHITE,2)
		debug_layer.draw_line(foot-Vector2(0,8),foot+Vector2(0,8),Color.WHITE,2)


static func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


static func points(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for value: Array in raw:
		out.append(point(value))
	return out
