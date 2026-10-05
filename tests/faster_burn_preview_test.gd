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
	cast.burn_profile.burn_faster = 0.0
	expect(Preview.burn_lines(cast) == original, "Zero speed preserves existing preview")
	cast.burn_profile.burn_faster = 0.25
	cast.burn_profile.base_duration = 3.0
	cast.burn_profile.duration = 2.4
	cast.burn_profile.roles.direct.dps = 12.5
	var before := var_to_bytes(cast)
	var lines := Preview.burn_lines(cast)
	expect(lines.size() == original.size()+1, "One compact speed line")
	expect(lines[0].contains("2.4"), "Shows final duration rather than base duration")
	expect(lines[1].contains("12.50") and lines[1].contains("30.00"), "Uses authoritative DPS and total without recomputation")
	expect(lines[2].contains("25%") and lines[2].contains("总量不变"), "Explains timing tradeoff")
	expect(var_to_bytes(cast) == before, "Preview is read-only")
	cast.burn_profile.fire_dot_multiplier = 0.10
	var combined := Preview.burn_lines(cast)
	expect(combined.size() == lines.size()+1, "Separate damage multiplier and speed lines")
	expect(combined[2].contains("+10%") and combined[3].contains("25%"), "Damage and speed not conflated")
	cast.burn_profile.enabled = false
	expect(Preview.burn_lines(cast).is_empty(), "Disabled burn hides speed")
	print("Faster burn preview: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
