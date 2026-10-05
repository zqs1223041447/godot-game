extends SceneTree
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 560056
	var item := Gear.generate_for_pool(rng,"gear_000561",1,"normal","forgeblade_v34")
	if item.is_empty():
		push_error("Fixture item must be a legal generated equipment instance")
		quit(1)
		return
	var definition := Gear.definition(item)
	expect(definition.description.contains("单目标近战挥击"), "Base card explains delivery change")
	expect(definition.weapon_damage_summary.contains("普通近战攻击与裂刃斩"), "Local contribution scope includes both consumers")
	var snapshot := Combat.snapshot({"damage":18.0},[])
	snapshot.weapon_profile = definition.weapon_profile
	var cast := Compiler.compile_basic(snapshot)
	expect(cast.get("ok",false) and cast.recipe.get("delivery","") == "melee", "Actual short blade basic compiles melee")
	var before := var_to_bytes(cast)
	var description := Preview.details(cast)
	expect(description.contains("普通近战攻击：距离 60") and description.contains("最多 1 个目标"), "Range and target limit shown")
	expect(description.contains("不发射投射物"), "No projectile behavior implied")
	expect(var_to_bytes(cast) == before, "Preview does not mutate combat")
	var normal := Compiler.compile_basic(Combat.snapshot({"damage":18.0},[]))
	expect(not Preview.details(normal).contains("普通近战攻击："), "Legacy basic is not mislabeled melee")
	print("Melee basic presentation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
