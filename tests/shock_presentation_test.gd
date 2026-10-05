extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	expect(Preview.shock_lines({"ok":false}).is_empty(), "Invalid cast has no shock preview")
	expect(Preview.shock_lines({"ok":true}).is_empty(), "Existing non-shock cast adds no lines")
	var profile := Shock.PLAYER_POLICY.duplicate(true)
	profile.enabled = true
	var fixture := {"ok":true,"shock_profile":profile}
	var before := var_to_bytes(fixture)
	var lines := Preview.shock_lines(fixture)
	expect(lines.size() == 2, "Compact two-line preview")
	expect(lines[0].contains("%.1f" % Shock.PLAYER_POLICY.duration) and lines[0].contains("%.0f%%" % (Shock.PLAYER_POLICY.hit_damage_taken_increased * 100.0)), "Preview reads authoritative duration and magnitude")
	expect(lines[1].contains("结算后") and lines[1].contains("不追溯") and lines[1].contains("持续伤害"), "Current hit and DOT limits explicit")
	expect(var_to_bytes(fixture) == before, "Preview never mutates cast")
	profile.enabled = false
	expect(Preview.shock_lines(fixture).is_empty(), "Disabled profile hidden")
	var model := Model.new()
	var uid := model.award_gem("support:shock")
	expect(not uid.is_empty(), "Actual support gem can be presented")
	var card := Presenter.view(model, uid)
	expect(card.base_stats.size() == 2, "Duration and magnitude separated into base stats")
	expect(card.function.contains("闪电命中") and card.function.contains("后续"), "Function explains trigger and effect")
	expect(card.description.contains("不追溯") and card.description.contains("不叠加或传播"), "Standalone limits explicit")
	expect(card.modifiers.size() == 2, "Damage and mana tradeoffs remain separate")
	expect(not str(card.requirements).is_empty() and not str(card.tags).contains("适用技能"), "Compatibility outside TAG")
	for skill: String in ["bolt", "nova", "chain"]:
		var cast := Compiler.compile_skill(skill, Combat.snapshot({"damage":100.0}, []), ["shock"])
		expect(cast.get("ok", false) and cast.get("shock_profile", {}).get("enabled", false), "Compiled shock profile " + skill)
		expect(Preview.shock_lines(cast).size() == 2, "Real cast reaches compact preview " + skill)
	print("Shock presentation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
