extends SceneTree
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Build = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
var checks := 0
var failures := 0
var combinations := 0
func _initialize() -> void:
	var state := Build.new()
	state.equip("prism_bow")
	state.equip("return_mantle")
	state.equip("detonation_charm")
	var snapshot := state.get_combat_snapshot()
	var input_before := var_to_bytes(snapshot)
	for skill: String in Data.SKILLS:
		var available := Supports.supports_for_skill(skill)
		for mask: int in range(1 << available.size()):
			var links: Array = []
			for bit: int in range(available.size()):
				if mask & (1 << bit): links.append(available[bit])
			if links.size() > 5: continue
			combinations += 1
			var result := Compiler.compile_group(skill, snapshot, links)
			check(result.get("ok", false), "five-slot subset compiles")
			if not result.get("ok", false): continue
			var reverse := links.duplicate()
			reverse.reverse()
			check(Compiler.compile_group(skill, snapshot, reverse) == result, "order independent full recipe")
			check(result.support_ids.size() == links.size(), "every link included")
			check(is_finite(result.mana) and result.mana > 0 and is_finite(result.cooldown) and result.cooldown > 0, "resource finite")
			if links.size() <= 2:
				check(Compiler.compile_skill(skill, snapshot, links) == result, "all published recipes byte-structure equal")
			else:
				check(not Compiler.compile_skill(skill, snapshot, links).ok, "legacy compiler keeps two-slot gate")
			if links.size() > 2:
				check(not Supports.saved_links_reason(skill, links, 13).is_empty(), "v13 cannot inject more links")
	check(var_to_bytes(snapshot) == input_before, "no input mutation")
	var base := Compiler.compile_group("frost", snapshot, [])
	var full := Compiler.compile_group("frost", snapshot, ["swift_projectiles","heavy_projectiles","lingering_chill","efficiency","quickcast"])
	check(full.ok, "three owned delivery modifiers accepted in five-link group")
	if full.ok:
		check(is_equal_approx(full.recipe.speed, base.recipe.speed * 1.35 * 0.75), "projectile speed has both factors")
		check(is_equal_approx(full.recipe.slow, 4.5), "chill actual duration included")
		check(full.mana != base.mana and full.cooldown != base.cooldown, "resource links affect same compiled recipe")
	check(not Compiler.compile_group("bolt", snapshot, ["volley","focus","pierce","efficiency","quickcast","swift_projectiles"]).ok, "sixth rejected")
	check(not Compiler.compile_group("bolt", snapshot, ["focus","focus"]).ok, "duplicate definition rejected")
	check(not Compiler.compile_group("ward", snapshot, ["pierce"]).ok, "incompatible skill rejected")
	print("Five support compiler: %d subsets, %d checks, %d failures" % [combinations, checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
