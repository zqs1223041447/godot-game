extends SceneTree
## Focused contract + draw callback checks; no main-scene wiring or saved progress.
## Optional actual viewport PNGs: -- --capture /absolute/evidence/directory
## Capture explicitly rejects the headless/dummy rendering backend.

const Renderer = preload("res://scripts/visuals/telegraph_renderer.gd")
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const FloorArt = preload("res://scripts/visuals/fantasy_environment.gd")
const Actors = preload("res://scripts/visuals/fantasy_actors.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")

var checks: int = 0
var failures: int = 0
var draw_callbacks: int = 0
var draw_states: Array[Dictionary] = []


class DrawProbe extends Node2D:
	var test: SceneTree
	func _draw() -> void:
		var before: Array[Dictionary] = test.draw_states.duplicate(true)
		seed(824131)
		var expected: int = randi()
		seed(824131)
		for level: int in range(3):
			var preferences := Settings.new()
			preferences.effects_level = level
			Renderer.draw(self, test.draw_states, preferences)
		Renderer.draw(self, [])
		Renderer.draw(self, null)
		test._expect(randi() == expected, "Native drawing leaves global RNG unchanged")
		test._expect(test.draw_states == before, "Native drawing leaves copied states unchanged")
		test.draw_callbacks += 1


class CaptureArena extends Node2D:
	const ARENA: Rect2 = View.WORLD_ARENA
	var _font: Font = load("res://assets/fonts/arena_sans.otf")
	var player_pos: Vector2 = ARENA.get_center()
	var elapsed: float = 0.0
	var demo_mode: bool = false
	var preferences := Settings.new()
	var states: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	func _draw() -> void:
		FloorArt.draw(self)
		Renderer.draw(self, states, preferences)
		for enemy: Dictionary in enemies:
			Actors.draw_enemy(self, enemy, preferences, false)


class CaptureLabels extends Node2D:
	var font: Font = load("res://assets/fonts/arena_sans.otf")
	var caption: String = ""
	var crowd: bool = false
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 94), Color("483b2d"))
		draw_string(font, Vector2(30, 36), "重击地面预警 / " + caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("e9d4aa"))
		draw_string(font, Vector2(30, 65), "独立 QA 绘制夹具，未接入主流程；圆心和半径来自实际运行时副本",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c4b58f"))
		if not crowd:
			for index: int in range(4):
				var x: float = 228 + index * 276
				_text(Vector2(x, 159), "蓄力 %d%%" % [0, 30, 65, 99][index])
				_text(Vector2(x, 347), "恢复 %d%%" % [0, 30, 65, 95][index])
		draw_rect(Rect2(0, 594, 1280, 126), Color("483b2d"))
		draw_string(font, Vector2(30, 630), "世界半径 90 · 相机 0.65 · 无发光材质、无旋转圆环、恢复只在原地消退",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("e0c696"))
		draw_string(font, Vector2(30, 661), "低特效保留完整边界与蓄力符文；石庭及怪物复用既有 FantasyEnvironment / FantasyActors",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("c4b58f"))
	func _text(at: Vector2, value: String) -> void:
		var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string_outline(font, at - Vector2(width * 0.5, 0), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 3, Color("493a2d"))
		draw_string(font, at - Vector2(width * 0.5, 0), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("e9d4aa"))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_runtime_clock_and_radius()
	_test_display_settings()
	_test_invalid_inputs()
	_test_capacity_and_layering()
	_test_copy_and_rng()
	await _test_draw_and_camera()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--capture") and failures == 0:
		var index: int = args.find("--capture")
		if index + 1 >= args.size():
			_expect(false, "--capture requires an evidence directory")
		else:
			await _capture(args[index + 1])
	print("telegraph_renderer_test: %d checks, %d failures, %d draw callbacks" % [checks, failures, draw_callbacks])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)


func _enemy(id: int = 1) -> Dictionary:
	return {"id": id, "health": 100.0, "shield": 10.0, "spawn": 0.0,
		"damage": 20.0, "contact_weights": {"physical": 0.5, "fire": 0.5}}


func _state(id: int = 1, age: float = 0.35, overrides: Dictionary = {}) -> Dictionary:
	var runtime := Runtime.new()
	var enemy: Dictionary = _enemy(id)
	var started: Dictionary = runtime.start(enemy, Vector2(183.25, 276.5), overrides)
	_expect(started.ok, "Runtime admits renderer fixture")
	runtime.advance(age, [enemy])
	return runtime.state_for(id)


func _role(values: Array[Dictionary], role: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for primitive: Dictionary in values:
		if primitive.role == role:
			found.append(primitive)
	return found


func _length(points: PackedVector2Array) -> float:
	var length: float = 0.0
	for index: int in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	return length


func _test_runtime_clock_and_radius() -> void:
	for radius: float in [0.001, 22.0, 90.0, 4096.0]:
		var runtime := Runtime.new()
		var enemy: Dictionary = _enemy()
		var center := Vector2(-42.5, 901.25)
		var overrides := {"radius": radius, "windup_seconds": 2.0, "recovery_seconds": 0.4}
		_expect(runtime.start(enemy, center, overrides).ok, "Actual radius and asymmetric duration fixture")
		var previous_length: float = -1.0
		for delta: float in [0.0, 0.25, 0.5, 1.0]:
			runtime.advance(delta, [enemy])
			var state: Dictionary = runtime.state_for(1)
			var values: Array[Dictionary] = Renderer.primitives([state])
			var edges: Array[Dictionary] = _role(values, "danger_boundary")
			_expect(edges.size() == 2, "Complete danger boundary throughout windup")
			for edge: Dictionary in edges:
				_expect(edge.kind == "circle" and edge.center == center and edge.radius == radius and not edge.filled,
					"Exact locked world center and radius; charge never shrinks range")
			var glyph: Array[Dictionary] = _role(values, "rune_charge")
			var length: float = _length(glyph[0].points) if not glyph.is_empty() else 0.0
			_expect(length >= previous_length, "Charge rune monotonically traces forward")
			previous_length = length
			_check_geometry(values, {1: state})
		var events: Array[Dictionary] = runtime.advance(0.25, [enemy])
		var state: Dictionary = runtime.state_for(1)
		_expect(events.size() == 1 and state.phase == "recovery" and is_equal_approx(state.elapsed, 2.0),
			"Boundary uses the runtime's phase transition and cumulative clock")
		var values: Array[Dictionary] = Renderer.primitives([state])
		_expect(_role(values, "danger_boundary").is_empty(), "Recovery is classified as spent ground artwork")
		var previous_alpha: float = _role(values, "recovery_boundary")[0].color.a
		for delta: float in [0.05, 0.1, 0.15]:
			runtime.advance(delta, [enemy])
			state = runtime.state_for(1)
			values = Renderer.primitives([state])
			var edge: Dictionary = _role(values, "recovery_boundary")[0]
			var progress: float = (float(state.elapsed) - 2.0) / 0.4
			_expect(absf(edge.color.a - 0.78 * pow(1.0 - progress, 2.0)) < 0.000001,
				"Recovery subtracts windup before normalizing its own duration")
			_expect(edge.color.a < previous_alpha and edge.center == center and edge.radius == radius,
				"Recovery fades monotonically without drift or expanding shockwaves")
			previous_alpha = edge.color.a
		var stale: Dictionary = state.duplicate(true)
		stale.elapsed = 2.4
		_expect(Renderer.primitives([stale]).is_empty(), "Expired stale copy produces no retained visual")
		runtime.advance(0.1, [enemy])
		_expect(Renderer.primitives([runtime.state_for(1)]).is_empty(), "Removed state produces no visual")
	var runtime := Runtime.new()
	var enemy: Dictionary = _enemy()
	runtime.start(enemy, Vector2.ZERO)
	runtime.cancel(1)
	_expect(Renderer.primitives([runtime.state_for(1)]).is_empty(), "Cancelled state leaves no terminal flash")
	runtime.start(enemy, Vector2.ZERO)
	runtime.reset()
	_expect(Renderer.primitives([runtime.state_for(1)]).is_empty(), "Reset is reflected without a renderer cache")


func _test_display_settings() -> void:
	var state: Dictionary = _state()
	var baseline: Array[Dictionary] = Renderer.primitives([state])
	for level: int in range(3):
		var settings := Settings.new()
		settings.effects_level = level
		var values: Array[Dictionary] = Renderer.primitives([state], settings)
		_expect(_role(values, "danger_boundary") == _role(baseline, "danger_boundary"),
			"Effects level preserves identical complete danger boundary")
		_expect(_role(values, "rune_charge") == _role(baseline, "rune_charge"),
			"Low effects preserves charge information")
		_expect(_role(values, "earth_mark").size() == [0, 1, 3][level], "Only cosmetic earth cuts change by level")
		settings.motion = false
		settings.ui_scale = 1.1
		settings.font_scale = 1.2
		settings.damage_numbers = false
		_expect(Renderer.primitives([state], settings) == values, "Display preferences do not scale world geometry or stop charge")
	var settings := Settings.new()
	settings.effects_level = -10
	_expect(_role(Renderer.primitives([state], settings), "earth_mark").is_empty(), "Effects below minimum clamp safely")
	settings.effects_level = 10
	_expect(Renderer.primitives([state], settings) == baseline, "Effects above maximum clamp safely")
	var start: Dictionary = _state(1, 0.0)
	_expect(_role(Renderer.primitives([start]), "rune_charge").is_empty(), "Zero-length charge line is omitted")


func _test_invalid_inputs() -> void:
	var valid: Dictionary = _state()
	for invalid: Variant in [null, {}, 12, "states", Vector2.ZERO]:
		_expect(Renderer.primitives(invalid).is_empty(), "Non-array snapshot input rejected")
	for invalid: Variant in [null, {}, 2, "state", RefCounted.new()]:
		_expect(Renderer.primitives([invalid]).is_empty(), "Non-state element skipped")
	var mutations: Array = [
		["source_id", 0], ["source_id", true], ["source_id", 1.5], ["center", Vector2(INF, 0)],
		["center", Vector2(0, NAN)], ["center", Vector3.ZERO], ["phase", "hit"], ["phase", 1],
		["elapsed", -0.01], ["elapsed", NAN], ["elapsed", INF], ["elapsed", true],
		["elapsed", "0.3"], ["elapsed", 0.9], ["profile", null], ["profile", []]]
	for mutation: Array in mutations:
		var malformed: Dictionary = valid.duplicate(true)
		malformed[mutation[0]] = mutation[1]
		_expect(Renderer.primitives([malformed]).is_empty(), "Reject invalid state field " + str(mutation[0]))
	for field: String in ["radius", "windup_seconds", "recovery_seconds"]:
		for invalid: Variant in [null, true, "90", NAN, INF, -1.0, 0.0, float(Profiles.LIMITS[field].maximum) + 1.0]:
			var malformed: Dictionary = valid.duplicate(true)
			malformed.profile[field] = invalid
			_expect(Renderer.primitives([malformed]).is_empty(), "Reject invalid profile scalar " + field)
		var missing: Dictionary = valid.duplicate(true)
		missing.profile.erase(field)
		_expect(Renderer.primitives([missing]).is_empty(), "Missing timing/radius does not invent defaults")
	var premature: Dictionary = valid.duplicate(true)
	premature.phase = "recovery"
	_expect(Renderer.primitives([premature]).is_empty(), "Inconsistent early recovery rejected")
	var tolerated: Dictionary = _state(1, 0.7)
	tolerated.elapsed = 0.7 - Runtime.TIME_EPSILON * 0.5
	_expect(not Renderer.primitives([tolerated]).is_empty(), "Runtime transition epsilon remains readable")
	var mixed: Array = [null, {}, valid, "bad"]
	_expect(Renderer.primitives(mixed) == Renderer.primitives([valid]), "Bad rows do not obscure a valid source")


func _test_capacity_and_layering() -> void:
	var runtime := Runtime.new()
	var enemies: Array[Dictionary] = []
	for index: int in range(Renderer.MAX_SOURCES):
		var enemy: Dictionary = _enemy(index + 1)
		enemies.append(enemy)
		_expect(runtime.start(enemy, Vector2(index * 13.0, index * 7.0)).ok, "One hundred actual runtime sources admitted")
	runtime.advance(0.35, enemies)
	var states: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for enemy: Dictionary in enemies:
		var state: Dictionary = runtime.state_for(enemy.id)
		states.append(state)
		by_id[state.source_id] = state
	var before: Array[Dictionary] = states.duplicate(true)
	for level: int in range(3):
		var settings := Settings.new()
		settings.effects_level = level
		var values: Array[Dictionary] = Renderer.primitives(states, settings)
		_expect(values.size() <= Renderer.MAX_PRIMITIVES, "Global bounded primitive budget")
		_expect(values.size() == 100 * [5, 6, 8][level], "Explicit hundred-source command bound at each level")
		_expect(_role(values, "danger_boundary").size() == 200, "No danger boundary evicted at capacity")
		var counts: Dictionary = {}
		var floor_done: bool = false
		var marks_started: bool = false
		for primitive: Dictionary in values:
			counts[primitive.source_id] = int(counts.get(primitive.source_id, 0)) + 1
			if primitive.role == "ground_tint":
				_expect(not floor_done, "All translucent floor fills precede every boundary")
			else:
				floor_done = true
			if primitive.kind == "polyline":
				marks_started = true
			elif primitive.role == "danger_boundary":
				_expect(not marks_started, "Boundaries precede cosmetic/rune marks")
		for count: int in counts.values():
			_expect(count <= Renderer.MAX_PRIMITIVES_PER_SOURCE, "Per-source primitive budget")
		_check_geometry(values, by_id)
		var reversed: Array[Dictionary] = states.duplicate()
		reversed.reverse()
		_expect(Renderer.primitives(reversed, settings) == values, "Stable source order independent of enemy list order")
		for iteration: int in range(30):
			_expect(Renderer.primitives(states, settings) == values, "Repeated draw builds retain no history or drift")
	_expect(states == before, "Capacity stress leaves input states untouched")
	var oversized: Array[Dictionary] = states.duplicate()
	oversized.append(states[0])
	_expect(Renderer.primitives(oversized).is_empty(), "Oversized arrays rejected without unbounded scanning")
	_expect(Renderer.primitives([states[0], states[0]]) == Renderer.primitives([states[0]]), "Duplicate source cannot amplify its artwork")
	draw_states = states.duplicate(true)


func _check_geometry(values: Array[Dictionary], states: Dictionary) -> void:
	for primitive: Dictionary in values:
		var color: Color = primitive.color
		_expect(is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)
			and color.a >= 0.0 and color.a <= 1.0, "Finite restrained pigment alpha")
		var state: Dictionary = states[primitive.source_id]
		if primitive.kind == "circle":
			_expect(primitive.center == state.center and primitive.radius == state.profile.radius,
				"Every circular primitive reads the same actual range")
			_expect(primitive.filled or (primitive.width > 0.0 and primitive.width <= 3.8), "Bounded positive boundary stroke")
		else:
			_expect(primitive.kind == "polyline" and primitive.points.size() >= 2
				and primitive.points.size() <= Renderer.MAX_POLYLINE_POINTS, "Bounded polyline point count")
			_expect(primitive.width > 0.0 and primitive.width <= 3.0, "Bounded positive rune stroke")
			for point: Vector2 in primitive.points:
				_expect(point.is_finite() and point.distance_to(state.center) <= float(state.profile.radius) + 0.0001,
					"Earth and rune vertices remain inside the true boundary")


func _test_copy_and_rng() -> void:
	var state: Dictionary = _state()
	# This unrelated packet remains entirely outside the visual authority.
	state.packet.base.physical = 99999.0
	state.unused = {"values": [1, {"sentinel": "unchanged"}]}
	var before: Dictionary = state.duplicate(true)
	var settings := Settings.new()
	seed(729815)
	var expected: int = randi()
	seed(729815)
	var first: Array[Dictionary] = Renderer.primitives([state], settings)
	Renderer.draw(null, [state], settings)
	_expect(randi() == expected, "Geometry and null-safe draw consume no global RNG")
	_expect(state == before and settings.effects_level == 2, "Inputs, damage packet, and preferences are read-only")
	var original: Array[Dictionary] = first.duplicate(true)
	first[0].radius = 4.0
	first[0].color = Color.MAGENTA
	var glyph: Dictionary = _role(first, "rune_base")[0]
	glyph.points[0] = Vector2(1, 2)
	_expect(Renderer.primitives([state], settings) == original and state == before, "Caller mutation of output cannot leak into future draws")
	var changed_packet: Dictionary = state.duplicate(true)
	changed_packet.packet = {"base": {"cold": INF}, "tags": ["unrelated"]}
	_expect(Renderer.primitives([changed_packet], settings) == original, "Damage packet contents never influence presentation")


func _test_draw_and_camera() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var probe := DrawProbe.new()
	probe.test = self
	root.add_child(probe)
	View.setup_camera(probe)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = resolution
		for frame: int in range(3):
			probe.queue_redraw()
			await process_frame
		var state: Dictionary = draw_states[0]
		var center: Vector2 = View.world_to_screen(probe, state.center)
		var end: Vector2 = View.world_to_screen(probe, state.center + Vector2.RIGHT * float(state.profile.radius))
		_expect(absf(center.distance_to(end) - float(state.profile.radius) * View.DEFAULT_ZOOM) < 0.001,
			"World range uses existing camera zoom exactly once")
		_expect(View.screen_to_world(probe, center).distance_to(state.center) < 0.001,
			"Telegraph locked center survives the existing view transform")
	_expect(draw_callbacks > 0, "Engine executes actual CanvasItem draw callbacks")
	probe.queue_free()
	await process_frame


func _capture(destination: String) -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() == "dummy":
		_expect(false, "Viewport capture requires a real display and rendering driver; no headless screenshot claim")
		return
	_expect(destination.is_absolute_path(), "Evidence directory is absolute")
	if not destination.is_absolute_path():
		return
	_expect(DirAccess.make_dir_recursive_absolute(destination) == OK, "Evidence directory can be created")
	var arena := CaptureArena.new()
	root.add_child(arena)
	View.setup_camera(arena)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var labels := CaptureLabels.new()
	layer.add_child(labels)
	var samples: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	for row: int in range(2):
		for column: int in range(4):
			var id: int = row * 4 + column + 1
			var center: Vector2 = View.from_reference(Vector2(228 + column * 276, 241 + row * 188))
			var enemy: Dictionary = Monsters.make_enemy(id, "ember_guard", 3, center + Vector2(-82, -42), "demo", "rare", [])
			enemy.spawn = 0.0
			var runtime := Runtime.new()
			_expect(runtime.start(enemy, center).ok, "Capture fixture uses actual catalog source and runtime")
			var age: float = float(Profiles.DEFAULTS.windup_seconds) * [0.0, 0.3, 0.65, 0.99][column] if row == 0 else \
				float(Profiles.DEFAULTS.windup_seconds) + float(Profiles.DEFAULTS.recovery_seconds) * [0.0, 0.3, 0.65, 0.95][column]
			runtime.advance(age, [enemy])
			samples.append(runtime.state_for(id))
			enemies.append(enemy)
	var crowd_runtime := Runtime.new()
	var crowd_enemies: Array[Dictionary] = []
	for index: int in range(100):
		var center: Vector2 = View.from_reference(Vector2(130 + index % 10 * 112, 151 + floori(index / 10.0) * 43))
		var enemy: Dictionary = Monsters.make_enemy(index + 1, "brute", 3, center - Vector2(28, 17), "demo", "normal", [])
		enemy.spawn = 0.0
		crowd_enemies.append(enemy)
		_expect(crowd_runtime.start(enemy, center).ok, "Hundred-source native capture admission")
	crowd_runtime.advance(0.455, crowd_enemies)
	var crowd_states: Array[Dictionary] = []
	for enemy: Dictionary in crowd_enemies:
		crowd_states.append(crowd_runtime.state_for(enemy.id))
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = resolution
		for mode: String in ["high", "low", "100-low"]:
			var crowd: bool = mode == "100-low"
			arena.states = crowd_states if crowd else samples
			arena.enemies = crowd_enemies if crowd else enemies
			arena.preferences.effects_level = 2 if mode == "high" else 0
			arena.preferences.motion = false
			labels.crowd = crowd
			labels.caption = "100 来源 / 低特效 / 500 图元" if crowd else "完整特效" if mode == "high" else "低特效"
			arena.queue_redraw()
			labels.queue_redraw()
			for frame: int in range(6):
				await process_frame
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			_expect(image != null and not image.is_empty() and image.get_size() == resolution, "Actual native viewport has requested pixels")
			if image == null or image.is_empty():
				continue
			var path: String = destination.path_join("telegraph-%s-%dx%d.png" % [mode, resolution.x, resolution.y])
			_expect(image.save_png(path) == OK, "Actual native viewport PNG saved")
			print("TELEGRAPH_CAPTURE ", path, " ", image.get_size(), " driver=", DisplayServer.get_name(),
				" renderer=", RenderingServer.get_current_rendering_method(), " primitives=", Renderer.primitives(arena.states, arena.preferences).size())
	arena.queue_free()
	layer.queue_free()
	await process_frame
