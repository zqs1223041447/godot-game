extends SceneTree
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var checks: int = 0
var failures: int = 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
func _initialize() -> void:
	var snapshot: Dictionary = Combat.snapshot({"damage": 100.0, "attack_added_physical": 10.0,
		"attack_added_fire": 20.0, "spell_added_cold": 30.0, "spell_added_lightning": 40.0}, ["explode_on_flight_end"])
	for id: String in ["tornado", "bolt", "frost", "nova", "meteor", "chain", "dash", "ward"]:
		var cast: Dictionary = Compiler.compile_skill(id, snapshot, ["volley", "focus"] if id in ["tornado", "bolt", "frost"] else [])
		expect(cast.ok, "Preview fixture compiles " + id)
		var before: Dictionary = cast.duplicate(true)
		var summary: String = Preview.summary(cast)
		var details: String = Preview.details(cast)
		if id in ["dash", "ward"]:
			expect(summary == "此技能不直接造成命中伤害", "Utility does not invent damage")
		else:
			expect(summary.contains("未计敌方防御"), "Preview states the mitigation boundary")
		for entry: Dictionary in Preview.entries(cast):
			var resolved: Dictionary = Damage.resolve(entry.packet, cast.snapshot.modifiers)
			expect(summary.contains("%.2f" % float(resolved.total)), "Summary uses actual resolver total " + entry.label)
			expect(details.contains(Preview.points(resolved.components)), "Details use actual resolved type components")
			expect(details.contains(Preview.assembly_line(entry.packet)), "Details expose actual intrinsic/addition trace")
			expect(not Preview.assembly_line(entry.packet).is_empty(), "Every active role has assembly trace")
		expect(cast == before, "Formatting never mutates cast snapshot")
	var tornado: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	expect(Preview.summary(tornado).contains("母箭 130.00") and Preview.summary(tornado).contains("子箭 91.00"), "Typed tornado additions remain after original distribution")
	expect(Preview.details(tornado).contains("附加效用 0.00"), "Independent explosion is visibly zero-effectiveness")
	var without_effect: Dictionary = Compiler.compile_skill("bolt", Combat.snapshot({"damage": 100.0}, []), [])
	expect(not Preview.summary(without_effect).contains("独立爆炸"), "Inactive equipment effect is not presented as active damage")
	expect(Preview.summary({"ok": false}) == "伤害配置无效", "Invalid cast cannot produce a plausible preview")
	expect(Preview.points({}) == "无", "Zero addition has explicit wording")
	print("Damage preview: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
