extends SceneTree
const Character = preload("res://scripts/ui/canonical_character_panel.gd")
const Telegraph = preload("res://scripts/visuals/telegraph_renderer.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var profile := {"ok":true,"raw":0.5,"effective":0.5,"cap":0.75}
	var original := var_to_bytes(profile)
	var display := Character.chaos_resistance_display(profile)
	expect(display.text == "50%", "Effective resistance shown")
	expect(display.tooltip.contains("50.0%") and display.tooltip.contains("75%"), "Raw and cap separate")
	expect(display.tooltip.contains("护盾仍"), "No invented shield bypass")
	expect(var_to_bytes(profile) == original, "No mutation")
	expect(Character.chaos_resistance_display({"ok":false}).text == "—", "Invalid profile not invented zero")
	var rows := Character.STAT_ROWS.filter(func(row: Dictionary): return row.id == "chaos_resistance")
	expect(rows.size() == 1 and rows[0].format == "chaos_resistance", "Separate chaos row, not elemental profile indexing")
	var state := {"source_id":1,"center":Vector2(100,200),"phase":"windup","elapsed":0.5,"visual_pattern":"chaos_guard","profile":{"radius":90.0,"windup_seconds":1.0,"recovery_seconds":1.8}}
	original = var_to_bytes(state)
	for effects: int in [0,1,2]:
		var settings := Settings.new()
		settings.effects_level = effects
		var primitives := Telegraph.primitives([state],settings)
		expect(not primitives.is_empty() and primitives.size() <= Telegraph.MAX_PRIMITIVES_PER_SOURCE, "Bounded visible telegraph")
		var boundaries := 0
		for primitive: Dictionary in primitives:
			if primitive.kind == "circle" and primitive.role == "danger_boundary":
				boundaries += 1
				expect(primitive.center == state.center and primitive.radius == 90.0, "Exact danger boundary")
			if primitive.kind == "polyline":
				expect(primitive.points.size() <= 6, "Rune remains compact")
		expect(boundaries == 2, "Boundary retained in low effects")
	expect(var_to_bytes(state) == original, "Visuals never mutate attack")
	print("Chaos presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
