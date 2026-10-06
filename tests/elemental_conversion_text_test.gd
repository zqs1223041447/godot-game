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
	var cast := {"ok":true,"conversion_profile":{"enabled":true,"version":2,"requested":{"fire":0.4,"cold":0.4,"lightning":0.4},"effective":{"fire":1.0/3.0,"cold":1.0/3.0,"lightning":1.0/3.0},"physical_fraction":0.0,"normalized":true},"support_ids":["fire_focus"]}
	var before := var_to_bytes(cast)
	var lines := Preview.conversion_lines(cast)
	expect(lines[0].contains("40%") and lines[1].contains("33.33%"), "Requested and effective percentages distinct")
	expect(lines[1].contains("保留物理 0.00%"), "Uses authoritative residual")
	expect(lines[2].contains("按比例分配"), "Overflow rule stated")
	expect(lines[-1].contains("转冰与转雷部分仅×0.80"), "Fire focus not mislabelled .96 on every type")
	expect(var_to_bytes(cast) == before, "Read-only conversion display")
	cast.support_ids = ["physical_focus"]
	expect(Preview.conversion_lines(cast)[-1].contains("各转化部分"), "Physical focus scope distinct")
	var old := {"ok":true,"conversion_profile":{"enabled":true,"fraction":0.4},"support_ids":[]}
	expect(Preview.conversion_lines(old).size() == 1 and Preview.conversion_lines(old)[0].begins_with("40% 物理伤害转为火焰"), "Old fire preview retained")
	cast.penetration_profile = {"enabled":true,"fractions":{"cold":0.06,"lightning":0.06},"minimum_resistance":-1.0}
	lines = Preview.penetration_lines(cast)
	expect(lines[0].contains("6 个百分点") and lines[1].contains("最低-100%"), "Penetration points and floor")
	expect(lines[1].contains("不作用于持续伤害"), "No DOT penetration promise")
	var detail := {"type":"cold","base":10.0,"increased":0.0,"more":1.0,"final":10.6,"effective_resistance":0.0,"penetration":0.06,"resistance":-0.06}
	lines = Preview.component_detail_lines(detail)
	expect(lines.size() == 2 and lines[1].contains("-6.00%"), "F6 shows resistance actually used")
	expect(Preview.penetration_detail_lines({}).is_empty(), "Old F6 receives no extra line")
	expect(Preview.penetration_lines({"ok":true}).is_empty(), "No profile no text")
	var live_cast: Dictionary = Compiler.compile_skill("frost", Combat.snapshot({"damage":100.0,"cold_penetration":0.06},[]),[])
	expect(bool(live_cast.get("ok",false)), "Actual compiler accepts native frost penetration")
	expect(Preview.summary(live_cast).contains("零抗性、零护甲目标，含穿透"), "Penetrating preview is not mislabeled pre-defense")
	var plain_cast: Dictionary = Compiler.compile_skill("frost", Combat.snapshot({"damage":100.0},[]),[])
	expect(Preview.summary(plain_cast).contains("未计敌方防御"), "Legacy heading unchanged")
	print("Elemental conversion text: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
