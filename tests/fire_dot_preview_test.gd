extends SceneTree
const Preview = preload("res://scripts/combat/damage_preview.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var cast := {"ok":true,"burn_profile":{"enabled":true,"duration":3.0,"roles":{"direct":{"dps":10.0,"total":30.0}}}}
	var original := Preview.burn_lines(cast)
	expect(original.size() == 3, "Unmodified burn wording retained")
	cast.burn_profile.fire_dot_multiplier = 0.0
	expect(Preview.burn_lines(cast) == original, "Explicit zero adds no text")
	cast.burn_profile.fire_dot_multiplier = 0.10
	var before := var_to_bytes(cast)
	var lines := Preview.burn_lines(cast)
	expect(lines.size() == 4, "One compact specialization line")
	expect(lines[2].contains("+10%") and lines[2].contains("已计入"), "Additive value shown without suggesting a second multiplier")
	expect(lines[1] == original[1], "Display does not recalculate supplied DPS")
	expect(var_to_bytes(cast) == before, "Read-only profile")
	cast.burn_profile.fire_dot_multiplier = 0.56
	expect(Preview.burn_lines(cast)[2].contains("+56%"), "Combined value uses authoritative total")
	cast.burn_profile.enabled = false
	expect(Preview.burn_lines(cast).is_empty(), "Disabled burn remains hidden")
	cast.ok = false
	expect(Preview.burn_lines(cast).is_empty(), "Invalid cast remains hidden")
	print("Fire DoT preview: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
