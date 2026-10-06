extends SceneTree
const Art = preload("res://scripts/visuals/ambush_trap_renderer.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Rules = preload("res://scripts/combat/ambush_support_rules.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var states := [{"id":1,"position":Vector2(20,30),"armed":false,"remaining_seconds":11.8}]
	var before := var_to_bytes(states)
	var marks := Art.primitives(states)
	expect(marks.size() == 1 and marks[0].position == Vector2(20,30), "Uses authoritative world position")
	expect(not marks[0].armed, "Unarmed state preserved")
	expect(var_to_bytes(states) == before, "Rendering is read only")
	states[0].armed = true
	var armed := Art.primitives(states)
	expect(armed[0].color != marks[0].color and armed[0].armed, "Arming distinguishable without a glowing radius")
	states.append(states[0].duplicate(true))
	expect(Art.primitives(states).size() == 1, "Duplicate IDs not drawn twice")
	for i in range(2,7): states.append({"id":i,"position":Vector2.ZERO,"armed":true,"remaining_seconds":1.0})
	expect(Art.primitives(states).size() == 3, "Bounded to three marks")
	expect(Art.primitives([{"id":1,"position":Vector2.ZERO,"armed":true,"remaining_seconds":0.0}]).is_empty(), "Expired marks hidden")
	expect(Art.primitives([{"id":1,"position":Vector2(INF,0),"armed":true,"remaining_seconds":1.0}]).is_empty(), "Invalid positions hidden")
	expect(Art.primitives(null).is_empty(), "Invalid status container safe")
	var profile: Dictionary = Rules.POLICY.duplicate(true)
	profile.enabled = true
	var cast := {"ok":true,"trap_profile":profile}
	var old := var_to_bytes(cast)
	var lines := Preview.trap_lines(cast)
	expect(lines.size() == 3 and lines[0].contains("0.35") and lines[0].contains("70"), "Shows actual arm delay and trigger radius")
	expect(lines[1].contains("12 秒") and lines[1].contains("3 枚"), "Shows shared capacity and expiration")
	expect(lines[2].contains("放置时固定") and lines[2].contains("只改变爆发范围"), "Snapshot and area scope explicit")
	expect(var_to_bytes(cast) == old, "Text cannot mutate cast")
	expect(Preview.trap_lines({"ok":true}).is_empty(), "Ordinary casts unchanged")
	print("Ambush visual/text: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
