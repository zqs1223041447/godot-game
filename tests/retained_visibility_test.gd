extends SceneTree
## Focused command-bound and retained-visibility contract. No save or raster IO.
const Layer = preload("res://scripts/visuals/retained_actor_layer.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const ART_PATH := "res://scripts/visuals/fantasy_actors.gd"

class Fixture extends Node2D:
	var enemies: Array[Dictionary] = []
	var visual_settings = Settings.new()
	var elapsed := 0.0
	var player_pos := Vector2(320, 180)

class CommandSpy extends RefCounted:
	var commands: Array = []
	var min_point := Vector2.ZERO
	var max_point := Vector2.ZERO
	var max_radius := 0.0
	var max_width := 0.0
	var vertices := 0
	func point(value: Vector2, padding: float = 0.0) -> void:
		min_point = min_point.min(value - Vector2.ONE * padding)
		max_point = max_point.max(value + Vector2.ONE * padding)
		max_radius = maxf(max_radius, value.length() + padding)
		vertices += 1
	func draw_colored_polygon(points: PackedVector2Array, _color: Color) -> void:
		commands.append(["polygon", points])
		for value: Vector2 in points: point(value)
	func draw_polyline(points: PackedVector2Array, _color: Color, width: float = -1.0, _aa: bool = false) -> void:
		commands.append(["polyline", points, width])
		max_width = maxf(max_width, width)
		for value: Vector2 in points: point(value, maxf(width, 0.0) * 0.5)
	func draw_line(from: Vector2, to: Vector2, _color: Color, width: float = -1.0, _aa: bool = false) -> void:
		commands.append(["line", from, to, width])
		max_width = maxf(max_width, width)
		point(from, maxf(width, 0.0) * 0.5)
		point(to, maxf(width, 0.0) * 0.5)
	func draw_circle(center: Vector2, radius: float, _color: Color) -> void:
		commands.append(["circle", center, radius])
		point(center, radius)

var checks := 0
var failures := 0
var geometry_cases := 0
var command_count := 0
var vertex_count := 0
var geometry_records: Array[Dictionary] = []
var transform_records: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func _geometry() -> void:
	# Keep every production statement/formula. Only change the canvas argument's
	# static type so GDScript calls the spy, not non-virtual native draw methods.
	var source := FileAccess.get_file_as_string(ART_PATH)
	var probe := GDScript.new()
	probe.source_code = source.replace("class_name FantasyActors\n", "").replace(": CanvasItem", ": Object").replace(":CanvasItem", ":Object").replace(": Node2D", ": Object")
	var compiled: int = probe.reload()
	check(compiled == OK, "Unchanged production art formulas compile for command capture")
	if compiled != OK: return
	var settings := Settings.new()
	var covered: Dictionary = {}
	for template: String in Catalog.TEMPLATES:
		var rarities: Array[String] = ["normal", "magic", "rare"]
		if template == "rift_warden": rarities = ["boss"]
		if template == "mist_skitter": rarities = ["normal"]
		var tightest_slack := INF
		var widest_stroke := 0.0
		var cases_before := geometry_cases
		for rarity: String in rarities:
			var enemy: Dictionary = Catalog.make_enemy(37, template, 5, Vector2.ZERO, "map_boss" if rarity == "boss" else "ordinary", rarity, [])
			check(not enemy.is_empty(), "Real catalog admits %s/%s" % [template, rarity])
			if enemy.is_empty(): continue
			covered[template] = true
			for radius: float in [0.0, float(enemy.radius), 36.125, 120.25]:
				enemy.radius = radius
				for pose: int in range(4):
					settings.motion = pose != 3
					var phase: float = [-PI * 0.5, 0.0, PI * 0.5, 1.234][pose]
					var elapsed := (phase - float(enemy.id)) / 7.0
					var unhurt_geometry := PackedByteArray()
					for flash: float in [0.0, 0.1]:
						enemy.flash = flash
						var before := var_to_bytes(enemy)
						var spy := CommandSpy.new()
						probe._shadow(spy, Vector2(0, radius * 0.56), Vector2(radius + 4.0, radius * 0.36 + 3.0))
						var shadow_commands := spy.commands.size()
						probe.draw_enemy_limbs(spy, enemy, settings, elapsed)
						var limb_commands := spy.commands.size() - shadow_commands
						probe.draw_enemy_body(spy, enemy)
						var label := "%s/%s r=%s pose=%d flash=%s" % [template, rarity, radius, pose, flash]
						check(shadow_commands > 0 and limb_commands > 0 and spy.commands.size() > shadow_commands + limb_commands, "All three real art paths captured: " + label)
						var bound: float = Layer._body_extent(radius, 0.0)
						var local_bound := 1.5 * radius + 8.0 + 3.0
						check(spy.min_point.x >= -local_bound and spy.min_point.y >= -local_bound and spy.max_point.x <= local_bound and spy.max_point.y <= local_bound, "Local command bounds include shadow, wings, tail, horns and strokes: " + label)
						check(spy.max_radius <= bound + 0.0001, "Radial command bound covers every continuous facing angle: " + label)
						check(spy.max_width <= 6.0, "Widest actual stroke fits the three-unit allowance: " + label)
						check(var_to_bytes(enemy) == before, "Actual art leaves authoritative input bytes unchanged: " + label)
						if flash == 0.0: unhurt_geometry = var_to_bytes(spy.commands)
						else: check(var_to_bytes(spy.commands) == unhurt_geometry, "Flash changes tint without expanding geometry: " + label)
						if not settings.motion:
							var still := CommandSpy.new()
							probe.draw_enemy_limbs(still, enemy, settings, elapsed + 100.75)
							check(var_to_bytes(still.commands) == var_to_bytes(spy.commands.slice(shadow_commands, shadow_commands + limb_commands)), "Motion off has identical limb commands at arbitrary elapsed: " + label)
						tightest_slack = minf(tightest_slack, bound - spy.max_radius)
						widest_stroke = maxf(widest_stroke, spy.max_width)
						geometry_cases += 1
						command_count += spy.commands.size()
						vertex_count += spy.vertices
		geometry_records.append({"template": template, "legal_rarities": rarities, "cases": geometry_cases - cases_before, "minimum_radial_slack": tightest_slack, "widest_stroke": widest_stroke})
	check(covered.size() == Catalog.TEMPLATES.size(), "Every real authored template is captured")

func _authority(host: Fixture) -> PackedByteArray:
	return var_to_bytes([host.enemies, host.elapsed, host.player_pos, host.transform, host.visual_settings.motion, host.visual_settings.effects_level, host.visual_settings.font_scale, host.visual_settings.ui_scale, host.visual_settings.damage_numbers])

func _sync(layer: Node2D, host: Fixture, label: String) -> void:
	var before := _authority(host)
	layer.sync(host)
	check(_authority(host) == before, "Synchronization preserves authoritative bytes: " + label)

func _all_visible(layer: Node2D, id: int, expected: bool) -> bool:
	for piece: Node2D in layer._pieces[id]:
		if piece.visible != expected: return false
	return true

func _identities(layer: Node2D) -> Dictionary:
	var result: Dictionary = {}
	for id: int in layer._pieces:
		result[id] = []
		for piece: Node2D in layer._pieces[id]: result[id].append(piece.get_instance_id())
	return result

func _ordered(layer: Node2D, host: Fixture) -> bool:
	var ordered: Array = host.enemies.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	for index: int in range(ordered.size()):
		for part: int in range(3):
			var piece: Node2D = layer._pieces[int(ordered[index].id)][part]
			if layer.get_child(index * 3 + part) != piece or piece.part != [&"shadow", &"limbs", &"body"][part]: return false
	return layer.get_child_count() == ordered.size() * 3

func _frame_and_edges(host: Fixture, view: SubViewport) -> void:
	var transforms: Array[Transform2D] = [Transform2D.IDENTITY,
		Transform2D(0.0, Vector2(-1200, 430)),
		Transform2D(0.0, Vector2(0.35, 0.35), 0.0, Vector2(170, 90)),
		Transform2D(0.0, Vector2(2.5, 2.5), 0.0, Vector2(-410, -180)),
		Transform2D(PI * 0.25, Vector2(190, -80)),
		Transform2D(-0.73, Vector2(0.65, 1.8), 0.21, Vector2(900, 220))]
	for index: int in range(transforms.size()):
		view.canvas_transform = transforms[index]
		host.transform = Transform2D(0.17, Vector2(23, -19)) if index == 5 else Transform2D.IDENTITY
		var frame: Dictionary = Layer._visibility_frame(host)
		check(frame.ok, "Finite invertible viewport transform is admitted %d" % index)
		if not frame.ok: continue
		var canvas: Transform2D = host.get_global_transform_with_canvas()
		var inverse := canvas.affine_inverse()
		var points: Array[Vector2] = []
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for screen: Vector2 in [Vector2.ZERO, Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)]:
			var local: Vector2 = inverse * screen
			points.append(local)
			low = low.min(local)
			high = high.max(local)
			check((canvas * local).distance_to(screen) < 0.001, "Inverse corner round-trips through actual canvas %d" % index)
		check(Vector2(frame.rect.position).is_equal_approx(low) and Vector2(frame.rect.end).is_equal_approx(high), "All four inverse corners determine arena-local viewport AABB %d" % index)
		var aa: float = 2.0 * (inverse.basis_xform(Vector2.RIGHT).length() + inverse.basis_xform(Vector2.DOWN).length())
		check(is_equal_approx(float(frame.aa_margin), aa), "Two screen pixels use both inverse basis axes %d" % index)
		var enemy: Dictionary = Catalog.make_enemy(70, "skitter", 1, Vector2.ZERO)
		var margin: float = sqrt(2.0) * (1.5 * float(enemy.radius) + 8.0) + 3.0 + aa
		check(is_equal_approx(Layer._body_extent(enemy.radius, aa), margin), "Margin includes rotated geometry stroke and inverse AA %d" % index)
		# Use Rect2's stored float boundary so inclusive comparisons are not
		# confused with a double-versus-float32 rounding discrepancy.
		var padded := Rect2(low, high - low).grow(margin)
		var left: float = padded.position.x
		var right: float = padded.end.x
		var top: float = padded.position.y
		var bottom: float = padded.end.y
		for edge: Vector2 in [Vector2(left, (top + bottom) * 0.5), Vector2(right, (top + bottom) * 0.5), Vector2((left + right) * 0.5, top), Vector2((left + right) * 0.5, bottom), Vector2(left, top), Vector2(right, bottom)]:
			enemy.pos = edge
			check(Layer._actor_visible(enemy, frame), "Inclusive padded side/corner %d at %s" % [index, edge])
		for outside: Vector2 in [Vector2(left - 0.02, low.y), Vector2(right + 0.02, high.y), Vector2(low.x, top - 0.02), Vector2(high.x, bottom + 0.02)]:
			enemy.pos = outside
			check(not Layer._actor_visible(enemy, frame), "Beyond padded side is rejected %d at %s" % [index, outside])
		transform_records.append({"case": index, "canvas": str(canvas), "viewport_local": str(frame.rect), "aa_margin": aa})
	view.canvas_transform = Transform2D.IDENTITY
	host.transform = Transform2D.IDENTITY
	var invalid_enemy: Dictionary = Catalog.make_enemy(71, "crawler", 1, Vector2(10000, 10000))
	check(Layer._actor_visible(invalid_enemy, {"ok": false}), "Invalid frame fails open")
	var valid_frame: Dictionary = Layer._visibility_frame(host)
	for value: float in [INF, NAN]:
		invalid_enemy.radius = value
		check(Layer._actor_visible(invalid_enemy, valid_frame), "Non-finite radius fails open")
	invalid_enemy.radius = 14.0
	invalid_enemy.pos = Vector2(INF, NAN)
	check(Layer._actor_visible(invalid_enemy, valid_frame), "Non-finite position fails open")
	host.transform = Transform2D(Vector2(1, 0), Vector2(2, 0), Vector2.ZERO)
	check(not Layer._visibility_frame(host).ok, "Singular actual arena canvas is rejected before inversion")
	host.transform = Transform2D.IDENTITY

func _lifecycle(host: Fixture, view: SubViewport) -> void:
	var layer := Layer.new()
	host.add_child(layer)
	for index: int in range(4):
		host.enemies.append(Catalog.make_enemy(index + 1, ["crawler", "skitter", "brute", "rift_warden"][index], 3, [Vector2(100, 130), Vector2(5000, -500), Vector2(400, 210), Vector2(7000, 900)][index], "map_boss" if index == 3 else "ordinary"))
	_sync(layer, host, "initial visible and hidden admission")
	var identities := _identities(layer)
	check(layer._pieces.size() == 4 and layer.get_child_count() == 12 and _ordered(layer, host), "All visible and hidden identities own ordered shadow/limbs/body triplets")
	check(_all_visible(layer, 1, true) and _all_visible(layer, 3, true) and _all_visible(layer, 2, false) and _all_visible(layer, 4, false), "Only padded onscreen actors are visible")
	for id: int in [2, 4]:
		for piece: Node2D in layer._pieces[id]: check(piece.redraw_requests == 0 and piece.enemy.is_empty(), "Initially hidden piece skips configure")
	var old_body: Node2D = layer._pieces[1][2]
	var original_key: Array = old_body._body_key.duplicate()
	var original_transform: Transform2D = old_body.transform
	var original_elapsed: float = old_body.elapsed
	var original_requests: int = old_body.redraw_requests
	host.enemies[0] = host.enemies[0].duplicate(true)
	host.enemies[0].pos = Vector2(5000, 70)
	host.enemies[0].radius = 31.25
	host.enemies[0].flash = 0.1
	host.elapsed = 91.75
	host.player_pos = Vector2(400, 300)
	_sync(layer, host, "hidden actor changes radius flash position and elapsed")
	check(_all_visible(layer, 1, false), "Moving outside hides all three existing pieces")
	check(old_body._body_key == original_key and old_body.transform == original_transform and old_body.elapsed == original_elapsed and old_body.redraw_requests == original_requests, "Hidden actor skips configure and body invalidation")
	host.enemies.reverse()
	host.enemies[0].pos.y = -700.0
	_sync(layer, host, "hidden and visible input order changes")
	check(_identities(layer) == identities and _ordered(layer, host), "Complete y sort retains every hidden/visible Piece identity")
	view.canvas_transform = Transform2D(0.0, Vector2(-4800, 0))
	_sync(layer, host, "camera translation re-entry")
	check(_all_visible(layer, 1, true) and _all_visible(layer, 3, false), "Camera movement alone immediately changes visibility")
	var current: Dictionary = {}
	for enemy: Dictionary in host.enemies:
		if enemy.id == 1: current = enemy
	for piece: Node2D in layer._pieces[1]:
		check(piece.enemy == current and piece.elapsed == host.elapsed and piece.preferences == host.visual_settings, "Re-entry configures latest dictionary, clock and settings")
		if piece.part != &"shadow": check(piece.transform.is_equal_approx(Transform2D((host.player_pos - Vector2(current.pos)).angle(), current.pos)), "Re-entry uses current position and facing")
	check(old_body._body_key[2] == 31.25 and old_body._body_key[4] == true and old_body.redraw_requests == original_requests + 1, "First re-entry rebuild uses latest exact radius and flash")
	view.canvas_transform = Transform2D.IDENTITY
	_sync(layer, host, "camera returns and hides actor again")
	current.flash = 0.0
	current.radius = 5.0
	var frame: Dictionary = Layer._visibility_frame(host)
	current.pos = Vector2(640 + Layer._body_extent(5.0, frame.aa_margin) + 4.0, 170)
	_sync(layer, host, "small radius remains wholly outside")
	check(_all_visible(layer, 1, false), "Small radius is hidden beyond its conservative margin")
	current.radius = 80.125
	_sync(layer, host, "radius expansion re-entry without motion")
	check(_all_visible(layer, 1, true) and old_body._body_key[2] == 80.125 and old_body._body_key[4] == false, "Radius expansion immediately admits latest body and ended flash")
	var camera := Camera2D.new()
	host.add_child(camera)
	camera.position_smoothing_enabled = false
	camera.ignore_rotation = false
	camera.position = Vector2(5000, 70)
	camera.zoom = Vector2(1.7, 0.8)
	camera.rotation = 0.43
	camera.make_current()
	camera.force_update_scroll()
	_sync(layer, host, "real Camera2D pan zoom rotation")
	var moved_frame: Dictionary = Layer._visibility_frame(host)
	check(moved_frame.ok and not Rect2(moved_frame.rect).is_equal_approx(Rect2(0, 0, 640, 360)), "Real Camera2D changes arena-local view each sync")
	for enemy: Dictionary in host.enemies: check(_all_visible(layer, int(enemy.id), Layer._actor_visible(enemy, moved_frame)), "Actual camera view controls all triplets")
	camera.enabled = false
	host.remove_child(camera)
	camera.queue_free()
	view.canvas_transform = Transform2D.IDENTITY
	_sync(layer, host, "restore view before hidden death")
	check(_all_visible(layer, 4, false), "Death fixture is hidden before removal")
	var removed: Array = layer._pieces[4].duplicate()
	for index: int in range(host.enemies.size() - 1, -1, -1):
		if host.enemies[index].id == 4: host.enemies.remove_at(index)
	_sync(layer, host, "hidden actor dies")
	check(not layer._pieces.has(4) and layer.get_child_count() == 9 and _ordered(layer, host), "Hidden death immediately removes all three pieces and restores full order")
	for piece: Node2D in removed: check(piece.get_parent() == null and piece.is_queued_for_deletion(), "Hidden dead piece detached and queued for deletion")
	for id: int in [1, 2, 3]:
		for part: int in range(3): check(layer._pieces[id][part].get_instance_id() == identities[id][part], "Surviving Piece identity preserved after hidden death")
	# Fail-open must retain and configure even a far-away actor.
	host.transform = Transform2D(Vector2(1, 0), Vector2(2, 0), Vector2.ZERO)
	_sync(layer, host, "singular transform fail-open")
	for enemy: Dictionary in host.enemies: check(_all_visible(layer, int(enemy.id), true), "Invalid actual canvas never culls a live actor")
	host.transform = Transform2D.IDENTITY
	layer.clear()
	check(layer._pieces.is_empty() and layer.get_child_count() == 0, "Clear removes all retained hidden and visible identities")
	_sync(layer, host, "re-entry after clear")
	check(layer._pieces.size() == host.enemies.size() and _ordered(layer, host), "Restart reconstructs only currently live identities")
	layer.clear()

func run() -> void:
	var started := Time.get_ticks_usec()
	seed(880088)
	var expected_rng := randi()
	seed(880088)
	_geometry()
	var view := SubViewport.new()
	view.size = Vector2i(640, 360)
	root.add_child(view)
	var host := Fixture.new()
	view.add_child(host)
	_frame_and_edges(host, view)
	_lifecycle(host, view)
	check(randi() == expected_rng, "Art and visibility do not consume the global RNG stream")
	view.queue_free()
	await process_frame
	await process_frame
	var result := {"checks": checks, "failures": failures, "geometry_cases": geometry_cases, "draw_commands": command_count, "command_vertices": vertex_count, "templates": geometry_records, "transforms": transform_records, "seconds": (Time.get_ticks_usec() - started) / 1000000.0, "art_sha256": FileAccess.get_sha256(ART_PATH), "layer_sha256": FileAccess.get_sha256("res://scripts/visuals/retained_actor_layer.gd"), "test_sha256": FileAccess.get_sha256("res://tests/retained_visibility_test.gd"), "verification": "Headless geometry commands and live Node/Camera2D lifecycle; no raster or performance claim"}
	var output := OS.get_environment("RETAINED_VISIBILITY_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(result, "\t") + "\n")
		else: check(false, "Result file could be written")
	print("Retained visibility: %d checks, %d failures; %d geometry cases, %d real draw commands, %d vertices; %.3fs" % [checks, failures, geometry_cases, command_count, vertex_count, result.seconds])
	quit(1 if failures else 0)
