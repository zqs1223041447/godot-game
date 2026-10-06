extends SceneTree
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
class DisplayModel extends RefCounted:
	signal changed
	var level := 1
	var xp := 0
	var talent_points := 0
	var profile := {"enabled":true,"life_rate":0.0,"shield_rate":12.4}
	func get_stats() -> Dictionary: return {"life_regen":99.0,"shield_recharge_rate":13.0,"max_shield":200.0}
	func get_regeneration_profile() -> Dictionary: return profile.duplicate(true)
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var model := DisplayModel.new()
	var panel := CharacterSheet.new()
	root.add_child(panel)
	panel.setup(model)
	var before := var_to_bytes(model.profile)
	expect(panel._values.life_regen.text == "0.00", "Uses final regeneration profile")
	expect(panel._values.shield_regeneration_rate.text == "12.40", "Shield regeneration is displayed directly")
	expect(panel._values.shield_recharge_rate.text == "13.00", "Recharge remains separate")
	var regen_card = panel.find_child("CharacterStat_shield_regeneration_rate", true, false)
	expect(regen_card.tooltip_text.contains("无需等待充能"), "Explains continuous regeneration")
	expect(regen_card.tooltip_text.contains("百分比按护盾上限"), "Percentage base is explicit")
	expect(regen_card.tooltip_text.contains("不转换药剂或偷取"), "Does not imply all recovery is transferred")
	expect(var_to_bytes(model.profile) == before, "UI is read only")
	model.profile = {"enabled":false,"life_rate":15.0,"shield_rate":0.0}
	model.changed.emit()
	panel.refresh()
	expect(panel._values.life_regen.text == "15.00", "Refund restores life regeneration")
	expect(panel._values.shield_regeneration_rate.text == "0.00", "Refund clears converted regeneration")
	expect(panel._values.shield_recharge_rate.text == "13.00", "Refund does not invent recharge changes")
	panel.free()
	print("Zealot's Oath presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
