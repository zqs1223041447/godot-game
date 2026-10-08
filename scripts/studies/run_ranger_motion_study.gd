extends SceneTree
## Explicit movement-only native study. Formal gameplay never selects this asset.
const Session = preload("res://scripts/studies/modular_study_session.gd")
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const DEFINITION := "res://assets/actors/studies/ranger_v125_east.json"
var arena: Node2D
var checks := 0
var failures: Array[String] = []

class Driver extends Node:
	var arena: Node2D
	var automatic := false
	var travel := 0.0
	var limit := 0.0
	func _process(delta: float) -> void:
		if arena.hud.is_blocking(): return
		var step := minf(delta, 0.1)
		if automatic:
			Input.action_press("move_right")
			travel += step * 240.0
			if travel >= limit:
				automatic = false
				Input.action_release("move_right")
		arena._move_player(step)
		arena._update_effects(step)
		arena.retained_actors.advance(step)
		# Main._draw owns the single pose observation for each rendered move.
		arena.queue_redraw()

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func fail(reason: String) -> void:
	printerr("RANGER_MOTION_STUDY_FAILED: ", reason); quit(1)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ranger-v125-"):
		printerr("Use tools/run_ranger_motion_study.sh for isolated study data")
		quit(78); return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFINITION))
	if not decoded is Dictionary: fail("Missing single-heading definition"); return
	var definition: Dictionary = decoded
	var prepared: Dictionary = Catalog.prepare_presentation(definition)
	if not prepared.ok: fail(prepared.reason); return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for unused in 4: arena.hud.close_panel()
	if not arena.save_build(): fail("Isolated initial save failed"); return
	var draft: Dictionary = arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision)
	if not draft.ok: fail(draft.reason); return
	var session = Session.new()
	var ready: Dictionary = await session.prepare_entry(arena, false)
	if not ready.ok: fail(ready.reason); return
	var entered: Dictionary = session.enter(arena)
	if not entered.ok: fail(entered.reason); return
	var selected: Dictionary = arena.retained_actors.set_hero_presentation(definition)
	if not selected.ok: fail(selected.reason); return
	arena.set_process_unhandled_key_input(false)
	arena.hud.visible = false
	# Only east exists. Keep unavailable movement headings out of this process.
	for action: String in ["move_left", "move_up", "move_down"]: InputMap.action_erase_events(action)
	arena.retained_actors.sync(arena)
	var badge_layer := CanvasLayer.new(); badge_layer.layer = 40; root.add_child(badge_layer)
	var badge := Label.new()
	badge.text = "游侠向右步态研究 · 80% Walk / 20% Jog · D / → 移动 · 战斗暂停\n停止时保持步态第 0 帧；没有 Idle / Attack 或其他方向素材"
	badge.position = Vector2(52, 76); badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", Color(0.94, 0.86, 0.63))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE; badge_layer.add_child(badge)
	var args := OS.get_cmdline_user_args()
	if args.has("--verify"):
		var output := ""
		var captures := ""
		for argument: String in args:
			if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
			if argument.begins_with("--capture-dir="): captures = argument.trim_prefix("--capture-dir=")
		await verify(definition, output, captures)
		return
	var driver := Driver.new(); driver.arena = arena
	driver.automatic = args.has("--auto")
	driver.limit = 4.0 * 240.0 * float(definition.provenance.cycle_seconds)
	root.add_child(driver)
	print("RANGER_MOTION_STUDY_READY heading=east frames=16 roots=25 combat_paused=true speed=240 zoom=0.65")

func present(native: bool) -> void:
	arena.queue_redraw()
	if native:
		await process_frame
		await RenderingServer.frame_post_draw
	else:
		arena.retained_actors.sync(arena)

func verify(definition: Dictionary, output: String, captures: String) -> void:
	var layer: Node2D = arena.retained_actors
	var hero: Node2D = layer._hero
	var cycle: float = definition.provenance.cycle_seconds
	var disk_before := FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var authority_before := var_to_bytes([arena.state.snapshot(), arena.enemies, arena.monster_runtime.next_id,
		arena.health, arena.mana, arena.shield, arena.attack_timer, arena.cooldowns, arena.world_geometry()])
	check(hero.atlas.direction_count == 1 and hero.atlas.frames.size() == 16 and not hero.atlas.clips.has("attack"), "One real heading and 16 source phases; no authored attack clip")
	check(is_equal_approx(16.0 / hero.atlas.fps, cycle) and is_equal_approx(arena._stats.move_speed, 240.0), "Authored cycle and unchanged actual Main movement speed")
	check(arena.enemies.size() == 25 and not arena.is_processing(), "All map roots exist together while combat is paused")
	var camera: Camera2D = arena.get_node("WorldCamera")
	check(camera.zoom.is_equal_approx(Vector2.ONE * 0.65), "Actual game camera uses 0.65")
	var destination := Rect2(-Vector2(64, 158) * float(hero.atlas.display_scale), Vector2(128, 192) * float(hero.atlas.display_scale))
	var canvas: Transform2D = hero.body.get_global_transform_with_canvas()
	var projected := Vector2((canvas * Vector2(destination.size.x, 0) - canvas * Vector2.ZERO).length(),
		(canvas * Vector2(0, destination.size.y) - canvas * Vector2.ZERO).length())
	check(projected.is_equal_approx(Vector2(64, 96)) and hero.scale == Vector2.ONE, "Source cell projects to 64x96 with one scale")
	check((destination.position + Vector2(64, 158) * hero.atlas.display_scale).is_zero_approx()
		and hero.visual_bounds().encloses(Rect2(-Vector2(32, 10), Vector2(64, 20))), "Fixed foot maps to root and bounds contain contact shadow")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Session.HERO))
	check(Catalog.prepare_presentation(legacy).entry.direction_count == 8, "Existing definitions still default to eight headings")
	var invalid := definition.duplicate(true); invalid.direction_count = 2
	check(not Catalog.prepare_presentation(invalid).ok, "Unsupported heading counts reject")
	if not captures.is_empty():
		if DisplayServer.get_name() == "headless": fail("Native capture needs a graphical renderer"); return
		DirAccess.make_dir_recursive_absolute(captures)
	Input.action_press("move_right")
	arena._move_player(1.0 / 60.0); layer.advance(1.0 / 60.0)
	await present(not captures.is_empty())
	var frames: Array[int] = []
	var samples: Array[Dictionary] = []
	var shadow_requests: int = hero.shadow_redraw_requests
	for index in 16:
		# Sample inside each held frame, not at a floating-point phase boundary.
		var step := cycle * (0.1 if index == 0 else 1.0) / 16.0
		var before: Vector2 = arena.player_pos
		arena._move_player(step); layer.advance(step)
		await present(not captures.is_empty())
		var speed: float = (Vector2(arena.player_pos) - before).length() / step
		check(absf(speed - 240.0) < 0.05 and hero.direction == 0 and hero.frame == index, "Actual east movement and source phase %d" % index)
		check(hero.position == arena.player_pos and hero.rotation == 0.0 and hero.shadow_redraw_requests == shadow_requests, "Ground root and retained static shadow phase %d" % index)
		frames.append(hero.frame)
		samples.append({"frame": hero.frame, "world_speed": speed, "projected_speed": speed * camera.zoom.x,
			"foot_world": [hero.position.x, hero.position.y]})
		if not captures.is_empty():
			var error := root.get_texture().get_image().save_png(captures.path_join("frame-%02d.png" % index))
			check(error == OK, "Native image saved phase %d" % index)
	Input.action_release("move_right")
	layer.advance(1.0 / 60.0)
	await present(not captures.is_empty())
	check(hero.animation == "idle" and hero.frame == 0, "Stopping holds source frame zero")
	check(Catalog.presentation_frame(hero.atlas, 0, "walk", cycle + 0.000001) == 0, "Sixteen phases wrap at the authored cycle")
	hero.configure_hero(arena, layer._visual_time + 0.05, {"id": 1000000, "direction": Vector2.RIGHT})
	check(hero.animation == "attack" and hero.frame == 0 and is_equal_approx(hero._attack_left, 0.45), "Visual attack cue keeps half-second occupancy using the declared held frame")
	for index in 6: hero.configure_hero(arena, layer._visual_time + 0.15 + index * 0.1)
	check(hero.animation == "idle" and hero.frame == 0, "Held attack cue expires without inventing attack art")
	check(authority_before == var_to_bytes([arena.state.snapshot(), arena.enemies, arena.monster_runtime.next_id,
		arena.health, arena.mana, arena.shield, arena.attack_timer, arena.cooldowns, arena.world_geometry()])
		and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == disk_before, "Movement-only preview preserves roster, combat resources/rules, model, geometry and save bytes")
	check(layer.set_hero_presentation({}).ok and hero._hero_presentation.is_empty(), "Explicit reset restores default presentation")
	var report := {"checks": checks, "failures": failures, "cycle_seconds": cycle, "heading": "east_only",
		"source_frames": frames, "projected_cell_size": [projected.x, projected.y], "movement_samples": samples,
		"scope": "Actual Main movement and renderer in an isolated native map; combat paused. No other headings or authored Idle/Attack clips; not natural combat or Windows FPS."}
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("RANGER_MOTION_STUDY_VERIFY checks=%d failures=%d" % [checks, failures.size()])
	arena.queue_free(); await process_frame
	quit(1 if not failures.is_empty() else 0)
