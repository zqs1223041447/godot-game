extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Embers = preload("res://scripts/visuals/burn_status_renderer.gd")
const Telegraph = preload("res://scripts/visuals/telegraph_renderer.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var cast := {"ok":true,"burn_profile":{"enabled":true,"duration":3.0,"rate_fraction":0.30,"hit_multiplier":0.75,"mana_multiplier":1.20,"roles":{"parent":{"dps":9.0,"total":27.0},"child":{"dps":6.3,"total":18.9}}}}
	var before := var_to_bytes(cast)
	var lines := Preview.burn_lines(cast)
	expect(lines.size() == 4 and lines[0].contains("非暴击、未计火抗"), "Preview explicitly states its estimate basis")
	expect(lines[1].contains("9.00") and lines[1].contains("27.00") and lines[2].contains("6.30"), "Role values are read directly without recalculation")
	expect(not str(lines).contains("爆炸"), "Independent explosion is not given burn preview")
	expect(Preview.burn_lines({"ok":true}).is_empty(), "Unmodified skill has no invented burn")
	expect(var_to_bytes(cast) == before, "Preview does not change compiled data")
	var states: Array = [{"target_kind":"monster","target_id":1,"position":Vector2(20,30),"remaining_seconds":2.5,"immune":false}, {"target_kind":"player","target_id":0,"position":Vector2(80,90),"remaining_seconds":1.0,"immune":true}]
	before = var_to_bytes(states)
	seed(45001)
	var expected := randf()
	seed(45001)
	expect(Embers.primitives(states, 2).size() == 6, "At most three small embers per target")
	expect(Embers.primitives(states, 0).size() == 2, "Lowest effects keeps one legible status mark")
	expect(Embers.primitives([states[0],states[0]], 2).size() == 3, "Duplicate target draws only once")
	var expired: Dictionary = states[0].duplicate(true)
	expired.remaining_seconds = 0.0
	expect(Embers.primitives([expired]).is_empty(), "Expired statuses draw nothing")
	expect(randf() == expected and var_to_bytes(states) == before, "VFX leaves gameplay RNG and state unchanged")
	var telegraph := {"source_id":1,"center":Vector2(200,200),"phase":"windup","elapsed":0.3,"profile":Profiles.DEFAULTS.duplicate(true),"visual_pattern":"ember_burn"}
	var preferences := Settings.new()
	preferences.effects_level = 0
	var marks := Telegraph.primitives([telegraph], preferences)
	expect(marks.size() <= Telegraph.MAX_PRIMITIVES_PER_SOURCE, "Burn warning preserves existing primitive budget")
	var boundaries := 0
	for mark: Dictionary in marks:
		if mark.role == "danger_boundary":
			boundaries += 1
			expect(mark.radius == 90.0 and mark.center == Vector2(200,200), "Warning keeps exact gameplay radius and center")
	expect(boundaries == 2, "Boundary remains visible at minimum VFX")
	var model := Model.new()
	var uid := model.award_gem("support:ignite")
	expect(not uid.is_empty(), "Real current model accepts new support identity")
	var card := Presenter.view(model, uid)
	expect(card.function.contains("点燃") and card.base_stats.size() == 2, "Standalone support shows benefit and authored duration/rate")
	expect(card.modifiers.size() == 2 and not str(card.tags).contains("陨星"), "Costs and compatibility remain distinct from tags")
	for skill: String in ["meteor", "tornado"]:
		var actual := Compiler.compile_skill(skill, Combat.snapshot({"damage":100.0}, []), ["ignite"])
		expect(actual.get("ok", false) and actual.has("burn_profile"), "Actual compiler exports burn profile " + skill)
		var displayed := Preview.burn_lines(actual)
		expect(displayed.size() >= 3 and displayed[0].contains("3.0"), "Compiled burn profile reaches readonly display " + skill)
	print("Burn presentation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
