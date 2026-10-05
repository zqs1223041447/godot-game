extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const EmberSupport = preload("res://scripts/combat/ember_proliferation_support_rules.gd")
const EmberSpread = preload("res://scripts/combat/ember_proliferation_rules.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var base := {"ok":true,"burn_profile":{"enabled":true,"duration":3.0,"roles":{"direct":{"dps":10.0,"total":30.0}}}}
	var old := Preview.burn_lines(base)
	expect(old.size() == 3, "Original burn preview is unchanged")
	base.burn_profile.proliferation = EmberSpread.POLICY.duplicate(true)
	var before := var_to_bytes(base)
	var lines := Preview.burn_lines(base)
	expect(lines.size() == 5, "Spread adds exactly two compact lines")
	expect(lines[3].contains(str(int(EmberSpread.POLICY.radius))) and lines[3].contains(str(int(EmberSpread.POLICY.max_targets))), "Range and count read policy")
	expect(lines[3].contains("墙体") and lines[4].contains("剩余时间") and lines[4].contains("不再传播"), "Limits are explicit")
	expect(var_to_bytes(base) == before, "Preview is read-only")
	var model := Model.new()
	var uid := model.award_gem("support:ember_proliferation")
	expect(not uid.is_empty(), "New gem has a real model identity")
	var card := Presenter.view(model, uid)
	expect(card.function.contains("死亡") and card.function.contains("仅传播一次"), "Standalone card explains mechanism")
	expect(card.base_stats.size() == 4, "Base duration rate range count separated")
	expect(str(card.requirements).contains("不能与点燃辅助") and not str(card.tags).contains("陨星"), "Exclusion and compatibility stay outside tags")
	expect(card.description.contains("剩余时间") and card.description.contains("不叠加"), "No duration refresh or stacking implication")
	expect(card.modifiers.size() == 2, "Damage and mana costs are separate modifiers")
	for skill: String in ["meteor", "tornado"]:
		var cast := Compiler.compile_skill(skill, Combat.snapshot({"damage":100.0}, []), ["ember_proliferation"])
		expect(cast.get("ok", false) and cast.get("burn_profile", {}).get("proliferation", {}).get("enabled", false), "Compiled spread profile " + skill)
		expect(str(Preview.burn_lines(cast)).contains("死亡扩散"), "Actual compiled cast reaches presentation " + skill)
	print("Ember presentation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
