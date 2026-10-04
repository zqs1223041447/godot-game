extends SceneTree
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
var checks := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var cast := Compiler.compile_skill("tornado", Combat.snapshot({"damage": 100.0}, []), [])
	cast.erase("critical")
	expect(Preview.critical_lines(cast).is_empty(), "Legacy cast has no invented critical profile")
	expect(Preview.summary(cast).begins_with("命中预估"), "Legacy heading remains unchanged")
	cast.critical = {"primary": {"chance": 0.075, "multiplier": 1.8}, "secondary": {"chance": 0.05, "multiplier": 1.5}}
	var before := var_to_bytes(cast)
	var lines := Preview.critical_lines(cast)
	expect(lines.size() == 1, "Inactive explosion stays hidden")
	expect(lines[0] == "暴击几率 7.5% · 暴击伤害 180.0%", "Final profile is formatted directly")
	expect(Preview.summary(cast).begins_with("非暴击命中预估"), "Damage preview is not a critical average")
	expect(Preview.details(cast).contains(lines[0]), "Existing detail path shares the profile formatter")
	expect(var_to_bytes(cast) == before, "Formatting does not alter profiles or consume a roll")
	cast.snapshot.effects.append("explode_on_flight_end")
	lines = Preview.critical_lines(cast)
	expect(lines.size() == 2 and lines[1] == "独立爆炸 · 暴击几率 5.0% · 暴击伤害 150.0%", "Secondary uses its own profile")
	cast.critical.primary.chance = 0.0
	expect(Preview.critical_lines(cast)[0].contains("0.0%"), "Explicit zero is displayed honestly")
	var utility := Compiler.compile_skill("ward", Combat.snapshot({"damage": 100.0}, []), [])
	expect(Preview.critical_lines(utility).is_empty(), "Utility does not invent a critical line")
	expect(Preview.critical_lines({"ok": false}).is_empty(), "Invalid cast is hidden")
	print("Critical preview: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
