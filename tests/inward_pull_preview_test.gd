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
	expect(Preview.inward_pull_lines({"ok":true}).is_empty(), "Old cast text unchanged")
	var cast := {"ok":true,"area_impulse_profile":{"enabled":true,"impulse_speed":190.0,"direction":"toward_origin"}}
	var before := var_to_bytes(cast)
	var lines := Preview.inward_pull_lines(cast)
	expect(lines.size() == 1, "One compact line")
	expect(lines[0].contains("爆发圆心"), "Actual explosion center rather than moving player")
	expect(lines[0].contains("墙体与怪物分离"), "Collision limitation stated")
	expect(lines[0].contains("不改变伤害或触发半径"), "No invented damage or trigger bonus")
	expect(var_to_bytes(cast) == before, "Read-only formatting")
	cast.area_impulse_profile.enabled = false
	expect(Preview.inward_pull_lines(cast).is_empty(), "Disabled policy hides line")
	cast.ok = false
	cast.area_impulse_profile.enabled = true
	expect(Preview.inward_pull_lines(cast).is_empty(), "Invalid cast hides line")
	print("Inward pull preview: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
