extends SceneTree
## Bounded actual-Main presentation acceptance; isolated data and optional native PNGs.
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
var arena: Node2D
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var capture_dir := ""
var output := ""
var native := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func pause_main() -> void:
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for unused in 4: arena.hud.close_panel()
func hold(direction: Vector2) -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	if direction.x > 0.1: Input.action_press("move_right")
	if direction.x < -0.1: Input.action_press("move_left")
	if direction.y > 0.1: Input.action_press("move_down")
	if direction.y < -0.1: Input.action_press("move_up")
func authority() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(), arena.enemies, arena.world_geometry(), arena.PLAYER_RADIUS,
		arena._stats, arena.health, arena.mana, arena.shield, arena.cooldowns, arena.attack_timer,
		arena.projectiles, arena.projectile_runtime.next_projectile_id, arena.combat_trace, arena.damage_trace])
func present(delta: float) -> void:
	arena.retained_actors.advance(delta)
	arena.hud._process(delta)
	arena.hud._update_live()
	arena.queue_redraw()
	# Main._draw is the sole native pose observation: a second sync would turn
	# one movement displacement into idle before the frame is captured.
	if native:
		await process_frame
		await RenderingServer.frame_post_draw
	else: arena.retained_actors.sync(arena)
func capture(name: String) -> void:
	if not capture_dir.is_empty():
		check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Native capture: " + name)
func mouse(direction: Vector2, pressed: bool) -> void:
	var point: Vector2 = root.get_screen_transform() * View.world_to_screen(arena, arena.player_pos + direction * 200.0)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
	event.position = point; event.global_position = point; event.pressed = pressed
	Input.parse_input_event(event); Input.flush_buffered_events()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ranger-v126-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires fresh /tmp/godot-ranger-v126-* XDG_DATA_HOME"); quit(78); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	native = DisplayServer.get_name() != "headless"
	if not capture_dir.is_empty():
		if not native: printerr("Captures require a native renderer"); quit(78); return
		DirAccess.make_dir_recursive_absolute(capture_dir)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame; pause_main()
	await present(0.0)
	var layer: Node2D = arena.retained_actors
	var hero: Node2D = layer._hero
	check(arena.world_context().normal_town and not arena.world_context().test_mode, "Fresh formal town selects default hero without a saved setting")
	check(not hero._hero_presentation.is_empty() and hero.atlas.texture.resource_path == "res://assets/actors/ranger_v126.png", "Actual Main defaults to imported v126 runtime asset")
	check(hero.atlas.direction_count == 8 and hero.atlas.frames_per_direction == 45 and hero.atlas.fps == 12.0,
		"Eight directions use 45 logical frames each at 12fps")
	check(hero.atlas.clips == {"idle": Vector2i(0,30), "walk": Vector2i(30,9), "attack": Vector2i(39,6)}, "Idle/Walk/Attack contracts remain declared")
	check(hero.atlas.texture.get_image().has_mipmaps(), "Imported default atlas has mipmaps")
	check(arena.save_build(), "Fresh formal save succeeds in isolated data")
	var disk_before := FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var initial := authority()
	check(is_equal_approx(arena._stats.move_speed, 240.0) and arena.get_node("WorldCamera").zoom == Vector2.ONE * 0.65, "Original movement speed and camera scale")
	var cell := Rect2(-Vector2(80,174) * hero.atlas.display_scale, Vector2(160,224) * hero.atlas.display_scale)
	var canvas: Transform2D = hero.body.get_global_transform_with_canvas()
	check((canvas * cell.end - canvas * cell.position).is_equal_approx(Vector2(80,112)), "160x224 canvas displays at 80x112 through one world scale")
	check(hero.atlas.contact_shadow_half_size == Vector2(32,10) and hero.visual_bounds().encloses(Rect2(-32,-10,64,20)), "Independent root-centered shadow fits retained bounds")
	var shadow_requests: int = hero.shadow_redraw_requests
	for direction in 8:
		# Independent short town walks stay inside the fixed camera and bounds.
		arena.player_pos = arena.ARENA.get_center()
		await present(0.0)
		var facing := Vector2.RIGHT.rotated(direction * TAU / 8.0)
		hold(facing)
		arena.tick(1.0 / 60.0); await present(1.0 / 60.0)
		var observed: Array[int] = []
		for phase in 9:
			var before: Vector2 = arena.player_pos
			arena.tick(0.09); await present(0.09)
			var speed: float = (Vector2(arena.player_pos) - before).length() / 0.09
			check(absf(speed - 240.0) < 0.1 and hero.direction == direction and hero.animation == "walk"
				and hero.frame >= direction * 45 + 30 and hero.frame < direction * 45 + 39, "Held movement and walk region: %s/%d" % [DIRECTIONS[direction], phase])
			check(hero.position == arena.player_pos and hero.rotation == 0.0 and hero.shadow_redraw_requests == shadow_requests,
				"Fixed root and retained independent shadow: %s/%d" % [DIRECTIONS[direction], phase])
			observed.append(hero.frame)
			if phase == 4: capture("town-walk-" + DIRECTIONS[direction])
		check(observed.size() == 9 and observed.has(direction * 45 + 38), "Walk reaches final sampled region: " + DIRECTIONS[direction])
		hold(Vector2.ZERO); arena.tick(0.02); await present(0.02)
		check(hero.animation == "idle" and hero.direction == direction and hero.frame == direction * 45, "Stop selects authored Idle: " + DIRECTIONS[direction])
		for phase in 30: await present(0.09)
		check(hero.animation == "idle" and hero.frame >= direction * 45 and hero.frame < direction * 45 + 30, "Idle loops independently of world combat time: " + DIRECTIONS[direction])
		var pose_before := authority()
		var rng_before: int = arena.rng.state
		arena.visual_cues.emit_cue("cast", arena.player_pos, {"direction": facing})
		await present(0.0)
		check(hero.animation == "attack" and hero.frame == direction * 45 + 39, "Cue starts authored Attack: " + DIRECTIONS[direction])
		for phase in 5: await present(0.09)
		check(hero.frame == direction * 45 + 44, "Attack reaches offline neutral recovery endpoint: " + DIRECTIONS[direction])
		capture("town-attack-" + DIRECTIONS[direction])
		await present(0.09); await present(0.02)
		check(hero.animation == "idle", "Half-second cue recovers to Idle: " + DIRECTIONS[direction])
		check(authority() == pose_before and arena.rng.state == rng_before, "Pose-only cue leaves game authority and RNG unchanged: " + DIRECTIONS[direction])
		samples.append({"direction": DIRECTIONS[direction], "walk_frames": observed, "attack_endpoint": direction * 45 + 44})
	hold(Vector2.RIGHT); arena.tick(0.02); await present(0.02)
	arena.visual_cues.emit_cue("cast", arena.player_pos, {"direction": Vector2.RIGHT}); await present(0.0)
	check(hero.animation == "attack", "Moving attack cue interrupts Walk")
	for unused in 7: arena.tick(0.09); await present(0.09)
	check(hero.animation == "walk", "Moving attack recovery resumes Walk without changing movement")
	hold(Vector2.ZERO); arena.tick(0.02); await present(0.02)
	check(hero.animation == "idle", "Stop after moving attack resumes Idle")
	check(authority() == initial and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH) == disk_before, "Town movement/pose acceptance preserves character, combat, geometry and save bytes")
	arena.visual_settings.motion = false
	hold(Vector2.LEFT); arena.tick(0.09); await present(0.09)
	check(hero.direction == 4 and hero.frame == 4 * 45 and hero.pose_time == 0.0, "Motion off uses directional authored Idle while movement continues")
	arena.visual_cues.emit_cue("cast", arena.player_pos, {"direction": Vector2.RIGHT}); await present(0.09)
	check(hero.direction == 0 and hero.frame == 0, "Motion off suppresses attack frame motion")
	hold(Vector2.ZERO); arena.visual_settings.motion = true
	for unused in 8: await present(0.09)
	check(layer.set_hero_presentation({}).ok, "Explicit code/API fallback selects original hero")
	await present(0.0)
	check(hero._hero_presentation.is_empty() and hero.atlas == Catalog.resource("hero"), "Original catalog asset remains available")
	arena.restart_run(); pause_main(); await present(0.0)
	hero = layer._hero
	check(not hero._hero_presentation.is_empty(), "Restart restores default selection after explicit legacy fallback")
	check(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok, "Lawful free old_garden draft")
	check(arena.start_map(arena.map_draft().revision).ok, "Actual map entry")
	pause_main(); await present(0.0); hero = layer._hero
	check(hero.atlas.frames.size() == 360 and arena.enemies.size() == 25, "Map restart keeps complete default hero and original resident roster")
	var basic: Dictionary = arena.state.get_basic_cast()
	check(basic.ok, "Unmodified owned basic attack compiles")
	mouse(Vector2.RIGHT, true)
	var interval: float = 1.0 / maxf(0.2, float(arena._stats.attack_speed))
	var shots_before: int = arena.total_shots
	arena._update_auto_attack(); await present(0.0)
	check(hero.animation == "attack" and is_equal_approx(arena.attack_timer, interval), "Actual held basic attack triggers default pose with original cooldown")
	var first_timer: float = arena.attack_timer
	arena._update_auto_attack()
	check(arena.attack_timer == first_timer and arena.total_shots == shots_before + 1, "Immediate held retry cannot bypass cooldown")
	capture("map-east-attack")
	var attacks := 1
	var recovered := false
	for unused in 120:
		var prior_shots: int = arena.total_shots
		arena.tick(1.0 / 60.0); await present(1.0 / 60.0)
		if arena.total_shots > prior_shots:
			attacks += 1
			check(is_equal_approx(arena.attack_timer, interval) and hero.animation == "attack", "Held repeat resets visual pose only at original attack admission")
		if hero.animation == "idle": recovered = true
	mouse(Vector2.RIGHT, false)
	check(attacks >= 2 and recovered, "Held basic fire repeats and recovers between original cooldown admissions")
	for unused in 36:
		arena.tick(1.0 / 60.0); await present(1.0 / 60.0)
	check(hero.animation == "idle", "Actual attack release settles to Idle")
	capture("map-east-idle")
	check(arena.return_to_town(arena.world_context().revision).ok, "Actual map return")
	pause_main(); await present(0.0); hero = layer._hero
	check(arena.world_context().normal_town and not hero._hero_presentation.is_empty() and arena.enemies.is_empty(), "Town return reapplies default and clears only encounter actors")
	check(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok, "Second lawful town-to-map transition")
	pause_main(); await present(0.0); hero = layer._hero
	check(hero.atlas.texture.resource_path == "res://assets/actors/ranger_v126.png", "Second map uses default runtime texture")
	hold(Vector2.RIGHT)
	for unused in 5: arena._move_player(0.09); await present(0.09)
	hold(Vector2.ZERO); capture("map-east-walk")
	var report := {"checks": checks, "failures": failures, "samples": samples, "native_renderer": DisplayServer.get_name(),
		"actual_held_attacks": attacks, "basic_attack_interval": interval,
		"scope": "Actual Main town input, authored poses, actual held basic fire, two lawful map entries and return. Controlled finite observations; no long-run, Windows FPS or perfect foot-lock claim."}
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("RANGER_DEFAULT_MAIN checks=%d failures=%d attacks=%d" % [checks, failures.size(), attacks])
	arena.queue_free(); await process_frame
	quit(1 if not failures.is_empty() else 0)
