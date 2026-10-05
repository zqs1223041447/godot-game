extends SceneTree
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
class DisplayModel extends RefCounted:
	signal changed
	var level := 1
	var xp := 0
	var talent_points := 0
	var profile: Dictionary = {"ok":true,"reason":"","base_cap":0.75,"safety_cap":0.83,"raw_resistances":{"fire":0.91,"cold":0.40,"lightning":0.75},"maximum_resistances":{"fire":0.83,"cold":0.83,"lightning":0.83},"effective_resistances":{"fire":0.83,"cold":0.40,"lightning":0.75}}
	func get_stats() -> Dictionary: return {"fire_resistance":0.91,"cold_resistance":0.40,"lightning_resistance":0.75}
	func get_resistance_profile() -> Dictionary: return profile.duplicate(true)
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var model := DisplayModel.new()
	var panel := CharacterSheet.new()
	root.add_child(panel)
	var before := var_to_bytes(model.profile)
	panel.setup(model)
	expect(panel._values.fire_resistance.text == "83%", "Raised fire cap is not clamped back to75")
	expect(panel._values.cold_resistance.text == "40%", "Insufficient raw resistance receives no free bonus")
	expect(panel._values.lightning_resistance.text == "75%", "Raw75 stays75 under cap83")
	var tip: String = panel._resistance_cards.fire_resistance.tooltip_text
	expect(tip.contains("91.0%") and tip.contains("83%"), "Raw and current cap are distinct")
	expect(tip.contains("不会直接增加"), "Cap does not claim free resistance")
	expect(var_to_bytes(model.profile) == before, "UI does not mutate authoritative profile")
	model.profile.maximum_resistances.fire = 0.75
	model.profile.effective_resistances.fire = 0.75
	model.changed.emit()
	panel.refresh()
	expect(panel._values.fire_resistance.text == "75%", "Refund restores actual effective value")
	expect(panel._resistance_cards.fire_resistance.tooltip_text.contains("当前上限 75%"), "Tooltip refreshes with cap")
	expect(panel._resistance_cards.size() == 3, "Original three resistance rows retained")
	panel.free()
	print("Resistance cap presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
