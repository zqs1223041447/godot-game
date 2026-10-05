extends SceneTree
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
const Telegraph = preload("res://scripts/visuals/telegraph_renderer.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	for wall: Rect2 in [Rect2(520,140,240,140),Rect2(1080,140,240,140),Rect2(520,430,240,140),Rect2(1080,430,240,140)]:
		var parts := EnvironmentArt.basin_geometry(wall)
		expect(parts.footprint == wall, "Opaque footprint equals actual collision")
		expect(wall.encloses(parts.rim) and wall.encloses(parts.water), "Basin details do not obscure walkable paths")
	expect(EnvironmentArt.basin_geometry(Rect2(0,0,8,8)).is_empty(), "Tiny obstacles safely use existing fallback")
	var profile: Dictionary = Profiles.DEFAULTS.duplicate(true)
	profile.radius = 85.0
	profile.windup_seconds = 0.8
	profile.recovery_seconds = 1.9
	var state := {"source_id":1,"center":Vector2(900,350),"phase":"windup","elapsed":0.4,"profile":profile,"visual_pattern":"sunwell_echo","pulse_index":0,"pulse_count":2}
	var settings := Settings.new()
	var original := var_to_bytes(state)
	seed(48001)
	var expected_rng := randf()
	seed(48001)
	for effects: int in [0,1,2]:
		settings.effects_level = effects
		var marks := Telegraph.primitives([state],settings)
		expect(marks.size() <= Telegraph.MAX_PRIMITIVES_PER_SOURCE, "Primitive budget remains bounded")
		var boundaries := 0
		var pulses := 0
		for mark: Dictionary in marks:
			if mark.role == "danger_boundary":
				boundaries += 1
				expect(mark.center == state.center and mark.radius == 85.0, "First pulse shows true hit region")
			if mark.role == "pulse_marker": pulses += 1
		expect(boundaries == 2 and pulses == 1, "Boundary and pulse count cue survive all effect levels")
	expect(var_to_bytes(state) == original and randf() == expected_rng, "Rendering leaves input and RNG untouched")
	state.pulse_index = 1
	state.elapsed = 0.0
	var second := Telegraph.primitives([state],settings)
	var second_boundaries := 0
	for mark: Dictionary in second:
		if mark.role == "danger_boundary":
			second_boundaries += 1
			expect(mark.center == Vector2(900,350) and mark.radius == 85.0, "Second pulse retains locked center/radius")
		if mark.role == "pulse_marker": expect(mark.points.size() == 4, "Second pulse has distinct double-stroke cue")
	expect(second_boundaries == 2, "Second windup starts visibly at zero age")
	state.phase = "recovery"
	state.elapsed = 0.8
	for mark: Dictionary in Telegraph.primitives([state],settings):
		expect(mark.role not in ["danger_boundary","pulse_marker"], "Recovery never signals another damaging pulse")
	state.elapsed = 2.7
	expect(Telegraph.primitives([state],settings).is_empty(), "Finished sequence leaves no telegraph")
	print("Sunwell presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
