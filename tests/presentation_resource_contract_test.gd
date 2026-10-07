extends SceneTree
const Catalog = preload("res://scripts/visuals/actor_sprite_catalog.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); push_error(label)
	return ok
func definition() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/actors/studies/hero_direction_study.json"))
func run() -> void:
	var raw := definition()
	var input_before := var_to_bytes(raw)
	var legacy: Dictionary = Catalog.resource("hero")
	var cache_keys: Array = Catalog._resources.keys()
	var prepared: Dictionary = Catalog.prepare_presentation(raw)
	if not check(prepared.get("ok", false), "Static eight-direction source validates"):
		finish(); return
	var entry: Dictionary = prepared.entry
	if OS.get_cmdline_user_args().has("--bounds-only"):
		for direction in 8:
			check(entry.visual_bounds.encloses(Rect2(-Vector2(entry.contact_shadow_half_size), Vector2(entry.contact_shadow_half_size) * 2.0)), "Contact shadow conservatively enclosed %d" % direction)
		check(entry.visual_bounds.encloses(Catalog.HERO_WARD_BOUNDS), "Ward outline conservatively enclosed")
		finish(); return
	check(var_to_bytes(raw) == input_before and Catalog._resources.keys() == cache_keys, "Preparing does not mutate input or permanent catalog cache")
	check(entry.texture.get_size() == Vector2(1536, 1024), "Actual original full-resolution sheet loads")
	check(is_equal_approx(entry.display_scale * 0.65, 0.115), "Authored world scale maps once through reference camera")
	for direction in 8:
		for clip: String in ["idle", "walk", "attack"]:
			check(Catalog.presentation_frame(entry, direction, clip, 0.0) == direction and Catalog.presentation_frame(entry, direction, clip, 20.0) == direction, "Static %s direction %d always resolves its idle image" % [clip, direction])
		var rect: Rect2 = Catalog.presentation_source_rect(entry, direction)
		var foot: Vector2 = Catalog.presentation_foot(entry, direction)
		var destination := Rect2(-foot * float(entry.display_scale), rect.size * float(entry.display_scale))
		check((destination.position + foot * float(entry.display_scale)).is_zero_approx(), "Per-direction foot maps to exactly local origin %d" % direction)
		check(entry.visual_bounds.encloses(Rect2(-Vector2(entry.contact_shadow_half_size), Vector2(entry.contact_shadow_half_size) * 2.0)), "Contact shadow fits retained bounds %d" % direction)
	check(entry.visual_bounds.encloses(Catalog.HERO_WARD_BOUNDS), "Existing ward overlay included in optional hero culling")
	var normalized_before := var_to_bytes([entry.frames, entry.clips, entry.display_scale, entry.visual_bounds])
	raw.frames[0].foot[0] = 0
	raw.clips.idle[1] = 0
	check(var_to_bytes([entry.frames, entry.clips, entry.display_scale, entry.visual_bounds]) == normalized_before, "Mutable caller frame and clip arrays detached")
	for invalid: Dictionary in [
		{"coordinate_space": "screen_pixel"}, {"world_units_per_source_pixel": 0.0},
		{"world_units_per_source_pixel": NAN}, {"frames_per_direction": 0},
		{"frames_per_direction": 65}, {"fps": INF}, {"fps": 0.0},
		{"texture_path": "user://other.png"}, {"texture_path": "res://missing.png"},
		{"contact_shadow_half_size_world": [-1, 6]}, {"schema_version": 2},
		{"clips": {"idle": [0, 2]}}, {"clips": {"attack": [0, 1]}}, {"clips": {"idle": [0, 1], "unimplemented": [0, 1]}},
	]:
		var bad := definition(); bad.merge(invalid, true)
		var rejected: Dictionary = Catalog.prepare_presentation(bad)
		check(not rejected.ok and not str(rejected.error_code).is_empty() and not str(rejected.reason).is_empty(), "Reject invalid definition " + str(invalid.keys()))
	var bad_frame := definition(); bad_frame.frames[0].region[2] = 99999
	check(not Catalog.prepare_presentation(bad_frame).ok, "Reject out-of-texture region")
	bad_frame = definition(); bad_frame.frames[0].foot = [99999, 4]
	check(not Catalog.prepare_presentation(bad_frame).ok, "Reject nonlocal foot")
	bad_frame = definition(); bad_frame.frames.pop_back()
	check(not Catalog.prepare_presentation(bad_frame).ok, "Reject incomplete direction data")
	var animated := definition()
	animated.texture_path = "res://assets/actors/hero_atlas.png"
	animated.world_units_per_source_pixel = 0.5
	animated.frames_per_direction = 18
	animated.clips = {"idle": [0,4], "walk": [4,8], "attack": [12,6]}
	animated.frames = []
	for index in 144:
		var rect: Rect2 = Catalog.frame_rect(index)
		animated.frames.append({"region": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "foot": [64,158]})
	var future: Dictionary = Catalog.prepare_presentation(animated)
	if check(future.ok, "Existing prerendered atlas fits same optional frame resource contract"):
		for direction in 8:
			for clip: String in ["idle", "walk", "attack"]:
				for seconds: float in [0.0, 0.08333333333333333, 0.5, 10.0]:
					check(Catalog.presentation_frame(future.entry, direction, clip, seconds) == Catalog.frame_index(direction, clip, seconds), "Prerendered clip keeps existing frame sampling")
			check(Catalog.presentation_frame(future.entry, direction, "attack", 10.0, false) == direction * 18, "Motion off chooses idle first frame")
		check(Catalog.presentation_frame(future.entry, -1, "walk", NAN) == 7 * 18 + 4, "Invalid clock starts clip and direction wraps")
	for index in 144:
		check(Catalog.presentation_source_rect(legacy, index) == Catalog.frame_rect(index) and Catalog.presentation_foot(legacy, index) == legacy.foot_anchor, "Legacy draw sampling unchanged")
	check(Catalog._resources.keys() == cache_keys, "Optional resources never retained in global catalog cache")
	finish()
func finish() -> void:
	var result := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "scope": "Opt-in resource normalization, coordinates and frame sampling; no gameplay or animation acceptance"}
	FileAccess.open("res://docs/qa/v110-presentation-adapter/resource-bounds-result.json" if OS.get_cmdline_user_args().has("--bounds-only") else "res://docs/qa/v110-presentation-adapter/resource-result.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  ") + "\n")
	print("PRESENTATION_RESOURCE: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
