extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Rules = preload("res://scripts/combat/encircling_cleave_support_rules.gd")
const Emblem = preload("res://scripts/visuals/skill_emblem.gd")
const Presentation = preload("res://scripts/ui/unified_item_presentation.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var profile: Dictionary = Rules.POLICY.duplicate(true)
	profile["radius"] = 95.0
	var cast := {"encircling_cleave_profile":profile}
	var original := var_to_bytes(cast)
	var lines := Preview.encircling_cleave_lines(cast)
	expect(lines.size() == 2 and lines[0].contains("360") and lines[0].contains("25%") and lines[0].contains("125%"), "Authoritative angle and costs")
	expect(lines[1].contains("不增加半径") and lines[1].contains("最多命中一次"), "Coverage is not radius or repeated hit")
	expect(Preview.encircling_cleave_lines({}).is_empty(), "Old casts unaffected")
	expect(var_to_bytes(cast) == original, "Read-only preview")
	expect(Emblem.ICONS.has("encircling_cleave"), "Real icon mapped")
	var texture: Texture2D = Emblem.ICONS.encircling_cleave
	expect(texture != null and texture.get_width() <= 512, "Bounded imported icon")
	var image := texture.get_image()
	expect(image != null and image.get_pixel(0,0).a == 0.0, "Transparent icon corner")
	var model := Model.new()
	var uid: String = model.award_gem("support:encircling_cleave")
	expect(not uid.is_empty(), "Legal support item")
	var view := Presentation.view(model,uid)
	expect(str(view.function).contains("一整圈"), "Function separated from numerical stats")
	expect(not view.base_stats.is_empty(), "Angle in base statistics")
	expect(not "裂刃斩" in view.tags, "Applicable skill not a TAG")
	expect(str(view.requirements).contains("裂刃斩"), "Compatibility belongs in requirements")
	print("Encircling cleave presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
