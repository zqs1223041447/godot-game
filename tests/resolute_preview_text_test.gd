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
	var cast := Compiler.compile_skill("tornado", Combat.snapshot({"damage":100.0}, []), [])
	cast.snapshot.accuracy = 150.0
	cast.critical = {"primary":{"chance":0.1,"multiplier":1.5},"secondary":{"chance":0.05,"multiplier":1.5}}
	var original := Preview.details(cast)
	expect(original.contains("实际命中率读取敌方闪避"), "Ordinary accuracy wording retained")
	cast.hit_policy = {}
	expect(Preview.details(cast) == original, "Empty policy preserves old output")
	cast.hit_policy = {"id":"resolute_technique","hits_cannot_be_evaded":true,"cannot_deal_critical_strikes":true}
	cast.critical.primary.chance = 0.0
	cast.critical.secondary.chance = 0.0
	var before := var_to_bytes(cast)
	var detail := Preview.details(cast)
	expect(detail.contains("命中不能被闪避"), "Shows the evasion bypass")
	expect(not detail.contains("实际命中率读取敌方闪避"), "Hides contradictory accuracy explanation")
	expect(detail.contains("墙体、免疫、护甲与抗性"), "Does not promise bypass of other defenses")
	expect(Preview.critical_lines(cast) == PackedStringArray(["不能造成暴击（包括独立爆炸）"]), "One explicit no-critical tradeoff line")
	expect(not detail.contains("暴击伤害 150"), "Hides unusable critical multiplier")
	expect(var_to_bytes(cast) == before, "Presentation never mutates combat state")
	cast.snapshot.effects.append("explode_on_flight_end")
	expect(Preview.critical_lines(cast).size() == 1, "Explosion shares the no-critical statement")
	cast.snapshot.erase("accuracy")
	expect(Preview.details(cast).contains("命中不能被闪避"), "Policy is not dependent on an accuracy stat")
	var utility := Compiler.compile_skill("ward", Combat.snapshot({"damage":100.0}, []), [])
	utility.hit_policy = cast.hit_policy
	expect(Preview.critical_lines(utility).is_empty(), "Non-hitting utility has no critical statement")
	expect(Preview.critical_lines({"ok":false,"hit_policy":cast.hit_policy}).is_empty(), "Invalid cast has no critical statement")
	print("Resolute preview: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
