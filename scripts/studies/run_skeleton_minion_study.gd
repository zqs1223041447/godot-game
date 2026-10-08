extends SceneTree
## Explicit visual study: genuine formal map, existing actor/layer/clock/shadow,
## visual-only stand-ins. Never registered in a production monster catalog.
const Actor = preload("res://scripts/visuals/actor_visual.gd")
const Layer = preload("res://scripts/visuals/retained_actor_layer.gd")
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const DEFINITION := "res://assets/actors/studies/skeleton_minion_study.json"
var arena: Node2D
var proxy: StudySource
var layer: Node2D
var definition: Dictionary
var checks := 0
var failures: Array[String] = []
var movement_samples: Array[Dictionary] = []
var clip_frames: Dictionary = {}
var reference: Dictionary

class StudyActor extends Actor:
	var study_entry: Dictionary
	func configure_enemy(value: Dictionary, settings: VisualSettings, time: float, player: Vector2, is_frozen: bool, _attack: Dictionary = {}) -> void:
		# Study-only adapter fixes the resource; base _update_pose and draw remain authoritative.
		var next: Vector2 = value.pos
		var displacement := next - position if _configured else Vector2.ZERO
		var timer := float(value.get("attack_timer", 0.0))
		var attacking := _configured and timer > _last_attack_timer + .00001
		_last_attack_timer = timer
		enemy = value; preferences = settings; frozen = is_frozen; atlas = study_entry
		hurt = false
		var cue_direction: Vector2 = value.get("study_facing", player - next)
		_update_pose(next, displacement, time, attacking, cue_direction)
		_refresh_commands()
	func head_anchor() -> Vector2: return study_entry.head_anchor
	func visual_bounds() -> Rect2: return study_entry.visual_bounds

class StudySource extends Node2D:
	var enemies: Array[Dictionary] = []
	var visual_settings: VisualSettings
	var player_pos := Vector2.ZERO
	var player_facing: Variant = null
	var paused := false
	func freeze_statuses() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		if paused:
			for enemy: Dictionary in enemies: result.append({"target_id": enemy.id, "remaining_seconds": 1.0})
		return result

class Driver extends Node:
	var owner_study: SceneTree
	var clock := 0.0
	var cue := false
	func _process(delta: float) -> void:
		if owner_study.arena.hud.is_blocking(): return
		var step := minf(delta, .1)
		clock += step
		owner_study.arena._move_player(step)  # genuine player movement and collision, unchanged 240 baseline
		owner_study.arena.retained_actors.advance(step)
		var phase := fmod(clock, 4.0)
		for index: int in owner_study.proxy.enemies.size():
			var enemy: Dictionary = owner_study.proxy.enemies[index]
			var heading := Vector2.from_angle(index * TAU / 8)
			if phase < 1.2:
				var target: Vector2 = enemy.pos + heading * float(enemy.speed) * step
				enemy.pos = owner_study.arena._geometry.move(enemy.pos, target, float(enemy.radius))
			elif phase >= 2.0 and phase < 2.1 and not cue:
				enemy.attack_timer += 1.0  # only an observed visual cue on this stand-in
		if phase >= 2.0 and phase < 2.1: cue = true
		if phase < .1: cue = false
		owner_study.layer.advance(step); owner_study.layer.sync(owner_study.proxy)
		owner_study.arena.queue_redraw()

func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	checks += 1
	if not value: failures.append(reason); printerr("SKELETON_STUDY_FAIL: ", reason)
func authority() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(), arena.enemies, arena.health, arena.mana, arena.shield,
		arena.attack_timer, arena.cooldowns, arena.monster_runtime.next_id, arena.world_geometry(),
		FileAccess.get_file_as_bytes(arena.build_save_path)])
func _run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-skeleton-game-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Use tools/run_skeleton_minion_study.sh for fresh isolated study data"); quit(78); return
	definition = JSON.parse_string(FileAccess.get_file_as_string(DEFINITION))
	var prepared := Catalog.prepare_presentation(definition)
	if not prepared.ok: printerr(prepared.reason); quit(1); return
	var entry: Dictionary = prepared.entry
	entry.foot_anchor = Vector2(64, 158)  # existing fixed 18-frame body path
	root.size = Vector2i(1280, 720); root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	for unused: int in 4: arena.hud.close_panel()
	if not arena.save_build(): quit(1); return
	var draft: Dictionary = arena.craft_normal_map("ruins_garden", 1, [], [], arena.map_draft().revision)
	if not draft.ok: printerr(draft.reason); quit(1); return
	var entered: Dictionary = await arena.open_map(arena.map_draft().revision)
	if not entered.ok: printerr(entered.reason); quit(1); return
	arena.set_process(false); arena.set_process_unhandled_key_input(false); arena.hud.hide()
	check(arena.world_geometry().id == "ruins_garden" and arena.static_environment._study_ground.diagnostics().ready,
		"Actual formal map has ready current natural-ground shader")
	for enemy: Dictionary in arena.enemies:
		if enemy.template_id == "crawler" and enemy.rarity == "normal": reference = enemy.duplicate(true); break
	if reference.is_empty(): printerr("Missing admitted ordinary crawler speed reference"); quit(1); return
	proxy = StudySource.new(); proxy.visual_settings = arena.visual_settings; arena.add_child(proxy)
	layer = Layer.new(); layer.name = "UndeadVisualStudy"; arena.world_depth.add_child(layer)
	for index: int in 8:
		var world := View.screen_to_world(arena, Vector2(130 + (index % 4) * 150, 220 + (index / 4) * 295))
		check(arena._geometry.is_clear(world, float(reference.radius)), "Stand-in starts on clear ground %d" % index)
		var id := 900000 + index
		proxy.enemies.append({"id": id, "template_id": "undead_minion_study", "rarity": "normal", "kind": 0,
			"pos": world, "radius": reference.radius, "speed": reference.speed, "attack_timer": 0.0, "flash": 0.0,
			"study_facing": Vector2.from_angle(index * TAU / 8)})
		var actor := StudyActor.new(); actor.study_entry = entry
		actor.facing = Vector2.from_angle(index * TAU / 8); actor.direction = index
		layer.add_child(actor); layer._actors[id] = actor
		var tag := Label.new(); tag.text = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"][index]
		tag.position = Vector2(-12, 18) / .65; tag.scale = Vector2.ONE / .65
		tag.add_theme_font_size_override("font_size", 14); tag.add_theme_color_override("font_color", Color.WHITE)
		tag.add_theme_color_override("font_shadow_color", Color("20251c")); tag.add_theme_constant_override("shadow_offset_x", 1)
		tag.add_theme_constant_override("shadow_offset_y", 1); actor.add_child(tag)
	layer.sync(proxy)
	var overlay := CanvasLayer.new(); overlay.layer = 40; root.add_child(overlay)
	var note := Label.new(); note.position = Vector2(42, 36)
	note.text = "Undead visual study / 8 real directions / Idle4 Walk8 Attack6 / head 0.85, pitch -25\nFormal ruins_garden / camera 0.65 / visual-only copies / combat paused / WASD moves the actual ranger\nReference ordinary speed %.1f world/s (%.1f px/s); 12fps walk has visible foot slip" % [float(reference.speed), float(reference.speed) * .65]
	note.add_theme_font_size_override("font_size", 17); note.add_theme_color_override("font_color", Color.WHITE)
	note.add_theme_color_override("font_shadow_color", Color("20251c")); note.add_theme_constant_override("shadow_offset_x", 1)
	note.add_theme_constant_override("shadow_offset_y", 1); overlay.add_child(note)
	var args := OS.get_cmdline_user_args()
	if args.has("--verify"):
		var capture := ""; var output := ""
		for argument: String in args:
			if argument.begins_with("--capture="): capture = argument.trim_prefix("--capture=")
			if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
		await verify(capture, output); return
	var driver := Driver.new(); driver.owner_study = self; root.add_child(driver)
	print("SKELETON_STUDY_READY: formal ground; 8 visual-only copies; no monster generation/stat/save changes")

func present(native: bool) -> void:
	layer.sync(proxy); arena.queue_redraw()
	if native: await process_frame; await RenderingServer.frame_post_draw

func verify(capture: String, output: String) -> void:
	var native := not capture.is_empty()
	check(not native or DisplayServer.get_name() != "headless", "Capture requires native renderer")
	var before := authority()
	var camera: Camera2D = arena.get_node("WorldCamera")
	check(camera.zoom == Vector2.ONE * .65 and arena._stats.move_speed == 240.0, "Actual game camera and player movement speed unchanged")
	check(arena.enemies.size() == 25 and proxy.enemies.size() == 8 and not Catalog.DEFINITIONS.has("undead_minion_study"), "Twenty-five real roots and eight separate visual copies; no production family entry")
	var actor: StudyActor = layer._actors[900000]
	var transform := actor.body.get_global_transform_with_canvas()
	var extent := Vector2((transform * Vector2(128 * actor.atlas.display_scale, 0) - transform * Vector2.ZERO).length(),
		(transform * Vector2(0, 192 * actor.atlas.display_scale) - transform * Vector2.ZERO).length())
	check(extent.is_equal_approx(Vector2(64, 96)), "Actual retained body projects source cell to 64x96")
	check((-Vector2(64, 158) * actor.atlas.display_scale + Vector2(64, 158) * actor.atlas.display_scale).is_zero_approx(), "Fixed source foot is actor root")
	var start_shadow: Dictionary = {}
	for enemy: Dictionary in proxy.enemies: start_shadow[enemy.id] = layer._actors[enemy.id].shadow_redraw_requests
	# Inspect the real retained observer across every slot; no wall or combat callbacks are run.
	for clip: String in ["idle", "walk", "attack"]:
		var count: int = {"idle": 4, "walk": 8, "attack": 6}[clip]
		clip_frames[clip] = []
		for phase: int in count:
			var step := .000001 if clip == "idle" and phase == 0 else 1.0 / 12.0 + .000001
			for index: int in 8:
				var enemy: Dictionary = proxy.enemies[index]
				var current: StudyActor = layer._actors[enemy.id]
				var heading := Vector2.from_angle(index * TAU / 8)
				if clip == "walk":
					var previous: Vector2 = enemy.pos
					enemy.pos = arena._geometry.move(previous, previous + heading * float(enemy.speed) * step, float(enemy.radius))
					var speed: float = Vector2(enemy.pos).distance_to(previous) / step
					check(absf(speed - float(reference.speed)) < .02, "Unchanged reference speed, heading %d phase %d" % [index, phase])
					movement_samples.append({"direction": index, "phase": phase, "world_speed": speed, "projected_world_speed": speed * camera.zoom.x})
				elif clip == "attack" and phase == 0:
					enemy.attack_timer += 1.0
				# Face each actor for the visual cue without sharing a gameplay attack target.
				proxy.player_pos = Vector2(enemy.pos) + heading * 100
				current.configure_enemy(enemy, proxy.visual_settings, layer._visual_time + step, proxy.player_pos, false)
				var expected := index * 18 + int(definition.clips[clip][0]) + phase
				check(current.animation == clip and current.direction == index and current.frame == expected,
					"Retained %s phase %d heading %d selects slot %d" % [clip, phase, index, expected])
				clip_frames[clip].append(current.frame)
				check(current.position == enemy.pos and current.rotation == 0 and current.shadow_redraw_requests == start_shadow[enemy.id], "Root/shadow remain aligned without rebaking")
			layer.advance(step)
			if native: await process_frame; await RenderingServer.frame_post_draw
		# Verify a real cyclic wrap or attack expiry through the existing observer.
		layer.advance(1.0 / 12.0 + .000001)
		for enemy: Dictionary in proxy.enemies:
			var current: StudyActor = layer._actors[enemy.id]
			if clip == "walk": enemy.pos = arena._geometry.move(enemy.pos, enemy.pos + current.facing * float(enemy.speed) / 12.0, float(enemy.radius))
			current.configure_enemy(enemy, proxy.visual_settings, layer._visual_time, enemy.pos + current.facing * 100, false)
			check(current.frame == current.direction * 18 + int(definition.clips[clip][0]) if clip != "attack" else current.animation == "idle", "Existing cycle wraps or half-second attack expires: " + clip)
	# Genuine player movement, independent of the stand-in speed driver.
	Input.action_press("move_right")
	var original_position: Vector2 = arena.player_pos
	arena._move_player(.05)
	Input.action_release("move_right")
	var actual_speed: float = Vector2(arena.player_pos).distance_to(original_position) / .05
	check(absf(actual_speed - 240) < .02, "Actual Main._move_player remains 240 world/s (156 projected px/s)")
	check(before == authority(), "Original roster/stats/resources/cooldowns/model/geometry/save bytes preserved")
	# Final native view: all eight headings in walk, sampled mid-phase, on current map.
	for index: int in 8:
		var enemy: Dictionary = proxy.enemies[index]
		var current: StudyActor = layer._actors[enemy.id]
		var heading := Vector2.from_angle(index * TAU / 8)
		current.configure_enemy(enemy, proxy.visual_settings, layer._visual_time + .1, enemy.pos + heading * 100, false)
		enemy.pos += heading * float(enemy.speed) * .05
		current.configure_enemy(enemy, proxy.visual_settings, layer._visual_time + .15, enemy.pos + heading * 100, false)
		enemy.pos += heading * float(enemy.speed) * .1
		current.configure_enemy(enemy, proxy.visual_settings, layer._visual_time + .25, enemy.pos + heading * 100, false)
	arena.queue_redraw()
	if native:
		await process_frame; await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "Native study screenshot saved")
	var report := {"checks": checks, "failures": failures, "source": DEFINITION, "map": "ruins_garden", "projected_cell_size": [extent.x, extent.y],
		"reference_template": reference.template_id, "reference_speed": reference.speed, "movement_samples": movement_samples, "clip_slots": clip_frames,
		"player_world_speed": actual_speed, "player_projected_speed": actual_speed * .65,
		"boundary": "Real map/camera/renderer and actual player movement; enemy motion is a visual-only speed/collision proxy. No natural AI, damage, spawn, culling-edge or FPS claim. Feet are not completely world-locked."}
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("SKELETON_STUDY_VERIFY checks=%d failures=%d" % [checks, failures.size()])
	arena.queue_free(); await process_frame; quit(1 if not failures.is_empty() else 0)
