extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var legacy := {"type":"cold","base":10.0,"increased":0.2,"more":1.5,"final":18.0}
	expect(Preview.component_detail_lines(legacy) == PackedStringArray(["冰冷 10.00 × (1 + 20%) × 1.50 = 18.00"]), "Old F6 formula preserved")
	var detail := {"type":"fire","before_defense":122.0,"final":61.0,"parts":[{"lineage":["physical","fire"],"base":40.0,"increased":1.2,"more":1.0,"before_defense":88.0},{"lineage":["fire"],"base":20.0,"increased":0.7,"more":1.0,"before_defense":34.0}]}
	var before := var_to_bytes(detail)
	var lines := Preview.component_detail_lines(detail)
	expect(lines.size() == 3, "Two origins plus actual merged result")
	expect(lines[0].begins_with("物理→火焰") and lines[0].contains("88.00"), "Converted part has original physical lineage")
	expect(lines[1].begins_with("原生火焰") and lines[1].contains("34.00"), "Native fire not relabelled as converted")
	expect(lines[2].contains("122.00") and lines[2].contains("61.00"), "Uses final merged defense result")
	expect(var_to_bytes(detail) == before, "No mutation or recomputation of combat result")
	var cast := {"ok":true,"conversion_profile":{"enabled":true,"fraction":0.4},"support_ids":[]}
	expect(Preview.conversion_lines(cast).size() == 1 and Preview.conversion_lines(cast)[0].contains("40%"), "Compact conversion rule")
	cast.support_ids = ["physical_focus"]
	expect(Preview.conversion_lines(cast)[1].contains("×0.96"), "Physical focus tradeoff explicit")
	cast.support_ids = ["fire_focus"]
	expect(Preview.conversion_lines(cast).size() == 2, "Fire focus also receives explanation")
	expect(Preview.conversion_lines({"ok":true}).is_empty(), "No new text on ordinary casts")
	expect(Preview.conversion_lines({"ok":false,"conversion_profile":cast.conversion_profile}).is_empty(), "Invalid cast hidden")
	print("Physical-fire preview: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
