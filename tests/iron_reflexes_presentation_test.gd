extends SceneTree
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
class DisplayModel extends RefCounted:
	signal changed
	var level := 1
	var xp := 0
	var talent_points := 0
	var profile := {"enabled":true,"armour":780.0,"evasion":0.0,"converted_armour":600.0,"dexterity_evasion_disabled":true}
	func get_stats() -> Dictionary: return {"armour":profile.armour,"evasion":profile.evasion,"accuracy":150.0}
	func get_defense_conversion_profile() -> Dictionary: return profile.duplicate(true)
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
	expect(panel._values.armour.text == "780.00", "Displays final armour without adding conversion twice")
	expect(panel._values.evasion.text == "0.00", "Converted evasion shows zero")
	expect(panel._values.accuracy.text == "150", "Accuracy remains authoritative")
	expect(panel._defense_cards.armour.tooltip_text.contains("600.00") and panel._defense_cards.armour.tooltip_text.contains("已计入"), "Conversion contribution distinguished from final total")
	expect(panel._defense_cards.armour.tooltip_text.contains("只减少物理命中"), "Does not promise elemental or burn reduction")
	expect(panel._defense_cards.evasion.tooltip_text.contains("敏捷不再提高闪避值，仍提高命中值"), "Dexterity tradeoff visible")
	expect(var_to_bytes(model.profile) == before, "Presentation does not mutate profile")
	model.profile = {"enabled":false,"armour":180.0,"evasion":630.0,"converted_armour":0.0,"dexterity_evasion_disabled":false}
	model.changed.emit()
	panel.refresh()
	expect(panel._values.armour.text == "180.00" and panel._values.evasion.text == "630.00", "Refund refreshes both existing rows")
	expect(not panel._defense_cards.armour.tooltip_text.contains("转为"), "Refund clears conversion explanation")
	expect(panel._defense_cards.evasion.tooltip_text == CharacterSheet.defense_tooltips({}).evasion, "Refund restores legacy evasion explanation")
	expect(panel._defense_cards.size() == 2, "No new stat row or layout")
	panel.free()
	print("Iron Reflexes presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
