extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Rules = preload("res://scripts/combat/long_stride_support_rules.gd")
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
	profile["enabled"] = true
	var cast := {"long_stride_profile":profile}
	var original := var_to_bytes(cast)
	var lines := Preview.long_stride_lines(cast)
	expect(lines.size() == 2 and lines[0].contains("175") and lines[0].contains("280"), "Distance from authoritative profile")
	expect(lines[0].contains("截断") and lines[0].contains("不能穿墙"), "Requested distance not guaranteed movement")
	expect(lines[1].contains("0.6") and lines[1].contains("0.0") and lines[1].contains("已有保护保留"), "Loss of grant never clears existing protection")
	expect(lines[1].contains("120%") and lines[1].contains("冷却不变"), "Resource tradeoff clear")
	expect(Preview.long_stride_lines({}).is_empty(), "Old dash preview unchanged")
	expect(var_to_bytes(cast) == original, "Read-only preview")
	var texture: Texture2D = Emblem.ICONS.long_stride
	expect(texture != null and texture.get_width() <= 512 and texture.get_image().get_pixel(0,0).a == 0.0, "Bounded alpha icon")
	var model := Model.new()
	var uid: String = model.award_gem("support:long_stride")
	expect(not uid.is_empty(), "Legal new support item")
	var view := Presentation.view(model,uid)
	expect(str(view.function).contains("不再获得"), "Protection tradeoff is visible")
	expect(view.base_stats.size() >= 2, "Distance and granted protection separated")
	expect(not "冲刺" in view.tags and str(view.requirements).contains("冲刺"), "Compatibility in requirements not TAG")
	print("Long stride presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
