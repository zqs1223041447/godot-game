extends SceneTree
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
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
	var wall := Rect2(660,230,520,250)
	var profile := EnvironmentArt.ginkgo_planter_regions(wall)
	expect(profile.outline == wall, "Visual footprint exactly collision wall")
	expect(wall.encloses(profile.rim) and wall.encloses(profile.inner), "Detail confined to collision rectangle")
	expect(profile.garden, "Large center planter distinct")
	expect(not EnvironmentArt.ginkgo_planter_regions(Rect2(420,310,90,90)).garden, "Small plinth is not a garden obstacle")
	expect(EnvironmentArt.ginkgo_planter_regions(Rect2(0,0,2,2)).is_empty(), "Invalid small shapes rejected")
	var state := {"source_id":1,"center":Vector2(1530,330),"phase":"windup","elapsed":0.7,"profile":{"radius":240.0,"windup_seconds":1.4,"recovery_seconds":1.9},"visual_pattern":"ginkgo_shelter_slam"}
	var before := var_to_bytes(state)
	var settings := Settings.new()
	settings.effects_level = 0
	var shapes := Telegraph.primitives([state],settings)
	var boundaries := 0
	var rune := false
	for shape: Dictionary in shapes:
		if shape.role == "danger_boundary":
			boundaries += 1
			expect(shape.center == state.center and shape.radius == 240.0,"Danger remains exact and fixed")
		if shape.role == "rune_base": rune = shape.points.size() == 6
	expect(boundaries == 2 and rune, "Low effects retains true outline and leaf mark")
	expect(shapes.size() <= Telegraph.MAX_PRIMITIVES_PER_SOURCE, "No new primitive budget")
	expect(var_to_bytes(state) == before, "Drawing never mutates timing or collision")
	print("Ginkgo visuals: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
