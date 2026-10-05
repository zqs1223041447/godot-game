extends SceneTree
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
const Text = preload("res://scripts/passives/source_tree_localization.gd")
const Maps = preload("res://scripts/world/map_catalog.gd")
class DisplayModel extends RefCounted:
	signal changed
	var level := 1
	var xp := 0
	var talent_points := 0
	var fraction := 0.0
	func get_stats() -> Dictionary: return {"max_mana":100.0}
	func get_mana_guard_profile() -> Dictionary: return {"ok":true,"enabled":fraction>0.0,"fraction":fraction}
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var model := DisplayModel.new()
	var panel := CharacterSheet.new()
	root.add_child(panel)
	panel.setup(model)
	var key := "damage_taken_from_mana_before_life"
	expect(panel._values[key].text == "0.0%", "Disabled profile shows zero")
	model.fraction = 0.4
	model.changed.emit()
	panel.refresh()
	expect(panel._values[key].text == "40.0%", "Character sheet reads authoritative fraction")
	var tip: String = panel.get_node("CharacterSheetBody/CharacterStatsGrid/CharacterStat_"+key).tooltip_text
	expect(tip.contains("护盾吸收后") and tip.contains("燃烧") and tip.contains("魔力不足"), "Resource order and hit/burn coverage explicit")
	model.fraction = 0.0
	model.changed.emit()
	panel.refresh()
	expect(panel._values[key].text == "0.0%", "Refund clears displayed allocation")
	expect(Text.node_name("34098") == "心灵升华", "Keystone uses reviewed Chinese name")
	for value: String in ["40", "10", "8"]:
		var line := Text.source_effect_line(value+"% of Damage is taken from Mana before Life")
		expect(line == "所受伤害的"+value+"%优先由魔力承担，再由生命承担", "Whole-line translation preserves fraction and resource order")
	var storm: String = Maps.SPECIAL.storm_patrol.description
	expect(storm.contains("1秒感电") and storm.contains("15%") and not storm.contains("不产生感电"), "Storm map description matches existing shock mechanism")
	panel.free()
	print("Mana guard presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
