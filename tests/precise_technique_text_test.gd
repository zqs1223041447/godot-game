extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Sheet = preload("res://scripts/ui/canonical_character_panel.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var profile := {"enabled":true,"accuracy":284.0,"max_health":141.0,"condition_met":true,"attack_more":0.4,"cannot_deal_critical_strikes":true,"attack_applies":true}
	var cast := {"ok":true,"precise_technique_profile":profile}
	var before := var_to_bytes(cast)
	var lines := Preview.precise_technique_lines(cast)
	expect(lines.size() == 3 and lines[0].contains("284.00") and lines[0].contains("141.00"), "Uses actual gate inputs")
	expect(lines[1].contains("40%") and lines[1].contains("已计入"), "Avoid double applying advertised bonus")
	expect(lines[2].contains("严格高于") and lines[2].contains("也不能暴击"), "Gate and unconditional penalty explicit")
	expect(lines[2].contains("此天赋不绕过闪避"), "Does not promise Resolute Technique")
	expect(var_to_bytes(cast) == before, "Read only")
	profile.attack_applies = false
	expect(Preview.precise_technique_lines(cast)[1].contains("未获得"), "Spells do not gain attack bonus")
	profile.accuracy = 141.0
	profile.condition_met = false
	profile.attack_more = 0.0
	expect(Preview.precise_technique_lines(cast)[0].contains("门槛未成立"), "Equality does not satisfy gate")
	expect(Sheet.precise_technique_tooltip(profile,"max_health").contains("始终不能暴击"), "C page penalty persists on failed gate")
	expect(Sheet.precise_technique_tooltip({},"max_health").is_empty(), "Old health tooltip preserved")
	expect(Sheet.precise_technique_tooltip({},"accuracy") == "攻击命中率取决于目标闪避；法术不进行闪避判定。", "Old accuracy tooltip preserved")
	expect(Preview.precise_technique_lines({"ok":true}).is_empty(), "Absent node preserves old text")
	print("Precise Technique text: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
