extends SceneTree
## Compiler-only regression contracts; isolated XDG directories are mandatory.
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog()
	_test_baselines()
	_test_combinations()
	_test_damage_scopes()
	_test_equipment_scopes()
	_test_lineage()
	_test_detachment()
	_test_recompile_rejection()
	_test_rejections()
	_test_metadata_validation()
	print("Skill compiler: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00001, "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _snapshot() -> Dictionary:
	return Recipes.snapshot({"damage": 100.0, "global_increased": 0.2,
		"projectile_increased": 0.5, "elemental_increased": 0.3},
		["return_on_range", "explode_on_flight_end"])


func _test_catalog() -> void:
	_expect(Supports.MAX_SUPPORTS == 2 and Supports.SUPPORTS.size() == 2, "Exactly two original supports and two slots")
	_expect(Supports.get_definition("volley").name == "散束辅助", "Volley stable name")
	_expect(Supports.get_definition("focus").name == "凝束辅助", "Focus stable name")
	_expect(Supports.get_definition("unknown").is_empty(), "Unknown support returns no definition")
	for id: String in Data.SKILLS:
		_expect(Supports.compatibility_reason(id, []).is_empty(), "Empty supports valid for " + id)
		var available: Array[String] = Supports.supports_for_skill(id)
		_expect(available.size() == (2 if id in ["tornado", "bolt", "frost"] else 0), "Capability eligibility for " + id)
	_expect(Supports.supports_for_skill("basic").is_empty(), "Basic attack has no support slots")
	_expect(not Data.SKILLS.tornado.capabilities.has("hit"), "Skill capability is not a damage-event tag")


func _test_baselines() -> void:
	var costs: Dictionary = {"tornado": 18.0, "bolt": 7.0, "frost": 16.0, "nova": 24.0,
		"dash": 12.0, "ward": 20.0, "meteor": 32.0, "chain": 22.0}
	var cooldowns: Dictionary = {"tornado": 2.5, "bolt": 0.8, "frost": 4.0, "nova": 6.0,
		"dash": 3.0, "ward": 7.0, "meteor": 8.0, "chain": 4.5}
	var counts: Dictionary = {"tornado": 3, "bolt": 3, "frost": 5}
	var snapshot: Dictionary = _snapshot()
	for id: String in Data.SKILLS:
		var result: Dictionary = Compiler.compile_skill(id, snapshot, [])
		_expect(result.ok and result.error.is_empty() and result.skill_id == id, "Empty baseline compiles " + id)
		if not result.ok:
			continue
		_near(result.mana, costs[id], "Unchanged mana for " + id)
		_near(result.cooldown, cooldowns[id], "Unchanged cooldown for " + id)
		_expect(result.initial_count == counts.get(id, 0) and result.support_ids.is_empty(), "Unchanged count for " + id)
		var stripped: Dictionary = result.snapshot.duplicate(true)
		stripped.erase("initial_count")
		stripped.erase("compiled_packets")
		stripped.erase("compiled_skill_id")
		_expect(stripped == snapshot, "Empty compilation preserves every snapshot value for " + id)
		if id in ["nova", "meteor"]:
			_expect(result.recipe == {"radius": 155.0 if id == "nova" else 110.0} and stripped == snapshot, "Area recipe preserves legacy radius and snapshot: " + id)
		elif not counts.has(id):
			_expect(result.recipe.is_empty() and stripped == snapshot, "Nonprojectile input values remain unchanged: " + id)
		else:
			_expect(result.recipe.initial_count == counts[id] and result.snapshot.initial_count == counts[id], "Single compiled count feeds recipe and snapshot for " + id)
	var bolt: Dictionary = Compiler.compile_skill("bolt", snapshot, []).recipe
	_expect(bolt == {"initial_count": 3, "spread": 0.16, "coefficient": 1.6, "pierce": 1,
		"slow": 0.0, "speed": 780.0, "damage_type": "lightning", "added_effectiveness": 1.6}, "Authoritative bolt recipe matches frozen v0.5 launch")
	var frost: Dictionary = Compiler.compile_skill("frost", snapshot, []).recipe
	_expect(frost == {"initial_count": 5, "spread": 0.14, "coefficient": 0.85, "pierce": 2,
		"slow": 3.0, "speed": 520.0, "damage_type": "cold", "added_effectiveness": 0.85}, "Authoritative frost recipe matches frozen v0.5 launch")
	for recipe: Dictionary in [bolt, frost]:
		var angles: Array[float] = []
		for index: int in range(recipe.initial_count):
			angles.append((index - (int(recipe.initial_count) - 1) * 0.5) * float(recipe.spread))
		_near(angles[0], -angles[-1], "Baseline spread remains symmetric")
		_near(angles[1] - angles[0], recipe.spread, "Baseline angle spacing retained")
	var tornado: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	var tornado_recipe: Dictionary = tornado.recipe.duplicate(true)
	tornado_recipe.erase("initial_count")
	_expect(tornado_recipe == Recipes.TORNADO, "Tornado recipe authority remains CombatData.TORNADO")


func _test_combinations() -> void:
	for id: String in ["tornado", "bolt", "frost"]:
		var baseline: Dictionary = Compiler.compile_skill(id, _snapshot(), [])
		var volley: Dictionary = Compiler.compile_skill(id, _snapshot(), ["volley"])
		var focus: Dictionary = Compiler.compile_skill(id, _snapshot(), ["focus"])
		var combined: Dictionary = Compiler.compile_skill(id, _snapshot(), ["volley", "focus"])
		var reversed: Dictionary = Compiler.compile_skill(id, _snapshot(), ["focus", "volley"])
		_expect(combined == reversed, "Entire compiled result is order independent for " + id)
		_expect(combined.support_ids == ["focus", "volley"], "Support IDs have canonical order for " + id)
		_near(volley.mana, baseline.mana * 1.30, "Volley cost for " + id)
		_near(focus.mana, baseline.mana * 1.20, "Focus cost for " + id)
		_near(combined.mana, baseline.mana * 1.56, "Combined multiplicative cost for " + id)
		_expect(volley.initial_count == baseline.initial_count + 2 and combined.initial_count == volley.initial_count, "Volley adds initial projectiles only for " + id)
		_expect(focus.initial_count == baseline.initial_count, "Focus preserves initial count for " + id)
		_near(combined.cooldown, baseline.cooldown, "Supports preserve cooldown for " + id)
		_near(combined.snapshot.base_damage, baseline.snapshot.base_damage, "Supports never alter base damage for " + id)
		_expect(combined.snapshot.effects == baseline.snapshot.effects, "Equipment effect grants survive compilation for " + id)
		_expect(combined.snapshot.modifiers.slice(0, baseline.snapshot.modifiers.size()) == baseline.snapshot.modifiers, "Existing modifiers survive compilation for " + id)


func _test_damage_scopes() -> void:
	var arrow: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "projectile", "attack"], "tornado")
	var blast: Dictionary = Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "area", "secondary", "explosion"], "tornado")
	var baseline: Dictionary = Compiler.compile_skill("tornado", _snapshot(), [])
	var volley: Dictionary = Compiler.compile_skill("tornado", _snapshot(), ["volley"])
	var both: Dictionary = Compiler.compile_skill("tornado", _snapshot(), ["volley", "focus"])
	_near(Damage.resolve(arrow, baseline.snapshot.modifiers).total, 370.0, "Existing 100 physical + 100 fire fixture is 370")
	_near(Damage.resolve(arrow, volley.snapshot.modifiers).total, 296.0, "Volley less scales fixture to 296")
	_near(Damage.resolve(arrow, both.snapshot.modifiers).total, 370.0, "Focus and volley multiply to original 370")
	for compiled: Dictionary in [baseline, volley, both]:
		_near(Damage.resolve(blast, compiled.snapshot.modifiers).total, 270.0, "Independent secondary fixture remains 270")
		_near(Damage.resolve(Recipes.tornado_packet(compiled.snapshot, "explosion"), compiled.snapshot.modifiers).total, 135.0, "Real tornado explosion remains independently scaled")
	for packet: Dictionary in [
		Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "projectile", "attack"], "basic"),
		Damage.packet({"physical": 100.0, "fire": 100.0}, ["hit", "projectile", "spell"], "frost"),
		Damage.packet({"physical": 100.0, "fire": 100.0}, ["projectile"], "tornado"),
	]:
		_near(Damage.resolve(packet, volley.snapshot.modifiers).total, 370.0, "Basic, wrong skill and nonhit packets exclude support more")
	for modifier: Dictionary in volley.snapshot.modifiers:
		if str(modifier.id).begins_with("support:"):
			_expect(modifier.mode == "more" and modifier.all_tags == ["hit", "projectile"] and modifier.skills == ["tornado"], "Support modifier has exact hit/projectile/skill scope")
	_near(Damage.resolve(Recipes.tornado_packet(volley.snapshot, "child"), volley.snapshot.modifiers).total,
		Damage.resolve(Recipes.tornado_packet(baseline.snapshot, "child"), baseline.snapshot.modifiers).total * 0.8, "Child hit receives volley less once")


func _test_equipment_scopes() -> void:
	var snapshot: Dictionary = Recipes.snapshot({"damage": 100.0, "projectile_count": 2,
		"spell_increased": 0.3, "fire_increased": 0.1, "cold_increased": 0.2,
		"lightning_increased": 0.4, "attack_elemental_increased": 0.5}, ["return_on_range", "explode_on_flight_end"])
	var volley: Dictionary = Compiler.compile_skill("tornado", snapshot, ["volley"])
	_expect(volley.initial_count == 7, "Equipment +2 and volley +2 give seven parents")
	for id: String in ["bolt", "frost"]:
		var result: Dictionary = Compiler.compile_skill(id, snapshot, ["volley"])
		_expect(result.initial_count == int(Data.SKILLS[id].projectile_recipe.initial_count) + 2, "Bow arrow bonus excludes " + id)
		var packet: Dictionary = Damage.packet({Data.SKILLS[id].projectile_recipe.damage_type: 100.0}, ["hit", "projectile", "spell"], id)
		_near(Damage.resolve(packet, result.snapshot.modifiers).total,
			Damage.resolve(packet, snapshot.modifiers).total * 0.8, "Typed spell affixes preserved with scoped support for " + id)
	var parent: Dictionary = Recipes.tornado_packet(snapshot, "parent")
	_near(Damage.resolve(parent, volley.snapshot.modifiers).total, Damage.resolve(parent, snapshot.modifiers).total * 0.8, "Attack/element affixes preserved with scoped support")
	var blast: Dictionary = Recipes.tornado_packet(snapshot, "explosion")
	_near(Damage.resolve(blast, volley.snapshot.modifiers).total, 99.0, "Explosion gets only matching fire modifier, not spell/attack/support")


func _test_lineage() -> void:
	var snapshot: Dictionary = _snapshot()
	snapshot.projectile_count = 2
	var compiled: Dictionary = Compiler.compile_skill("tornado", snapshot, ["volley", "focus"])
	var runtime = Runtime.new()
	var shots: Array[Dictionary] = []
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, compiled.snapshot, 100, compiled.initial_count) == 7, "Compiled request emits exactly seven parents")
	var events: Array[Dictionary] = runtime.advance(shots, 0.5, [], Vector2.ZERO, 100)
	_expect(shots.size() == 21, "Seven parents produce 21 children, never 35")
	var splits: int = 0
	for event: Dictionary in events:
		if event.type == "split":
			splits += 1
			_expect(event.count == 3, "Each split preserves authoritative child count")
	_expect(splits == 7, "Exactly one split per mother")
	_expect(compiled.snapshot.tornado_recipe.child_count == Recipes.TORNADO.child_count, "Support cannot change split recipe child count")
	var per_parent: Dictionary = {}
	for child: Dictionary in shots:
		per_parent[child.parent_id] = int(per_parent.get(child.parent_id, 0)) + 1
		_expect(child.snapshot == compiled.snapshot, "Descendant retains complete compiled snapshot")
	for count: int in per_parent.values():
		_expect(count == 3, "Each lineage contains exactly three children")
	for bonus: int in [-100, 100]:
		snapshot.projectile_count = bonus
		var bounded: Dictionary = Compiler.compile_skill("tornado", snapshot, ["volley"])
		_expect(bounded.ok and bounded.initial_count == (1 if bonus < 0 else 9), "Initial count remains within one to nine")


func _test_detachment() -> void:
	var snapshot: Dictionary = _snapshot()
	snapshot.tornado_recipe.child.speed = 123.0
	snapshot.explosion_recipe.radius = 42.0
	var ids: Array = ["volley"]
	var before: Dictionary = snapshot.duplicate(true)
	var first: Dictionary = Compiler.compile_skill("tornado", snapshot, ids)
	var second: Dictionary = Compiler.compile_skill("tornado", snapshot, ids)
	_expect(snapshot == before and ids == ["volley"], "Compiler is pure and preserves its input")
	first.snapshot.modifiers[0].value = 99.0
	first.snapshot.effects.clear()
	first.snapshot.tornado_recipe.child.speed = 900.0
	first.snapshot.explosion_recipe.radius = 900.0
	first.recipe.child.coefficient = 9.0
	first.support_ids.clear()
	_expect(snapshot == before, "Nested output mutation never aliases input snapshot")
	_expect(second.snapshot == Compiler.compile_skill("tornado", before, ["volley"]).snapshot, "Repeated compiles own independent deep snapshots")
	_near(first.recipe.child.speed, 123.0, "Recipe result is detached even from result snapshot")
	_near(first.snapshot.tornado_recipe.child.coefficient, Recipes.TORNADO.child.coefficient, "Snapshot recipe is detached from result recipe")
	_near(second.snapshot.explosion_recipe.radius, 42.0, "Custom explosion recipe survives untouched")
	var definition: Dictionary = Supports.get_definition("volley")
	definition.operations[0].value = 99
	definition.requires.clear()
	_expect(Supports.get_definition("volley").operations[0].value == 2, "Definition lookup never aliases catalog")
	var bolt: Dictionary = Compiler.compile_skill("bolt", before, ["volley"])
	bolt.recipe.speed = 1.0
	_near(Data.SKILLS.bolt.projectile_recipe.speed, 780.0, "Compiled spell recipe never aliases GameData")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(before))
	var json_ids: Array = JSON.parse_string('["focus", "volley"]')
	var from_json: Dictionary = Compiler.compile_skill("tornado", parsed, json_ids)
	_expect(from_json.ok, "Detached JSON snapshot and support arrays compile")
	parsed.tornado_recipe.child.speed = 9999.0
	parsed.modifiers[0].value = 9999.0
	json_ids.clear()
	_near(from_json.snapshot.tornado_recipe.child.speed, 123.0, "JSON nested recipe is detached")
	_expect(from_json.support_ids == ["focus", "volley"], "JSON support array is detached")
	_near(from_json.snapshot.modifiers[0].value, 0.2, "JSON modifier is detached")


func _test_recompile_rejection() -> void:
	for id: String in ["tornado", "bolt", "frost"]:
		for support_ids: Array in [[], ["volley"], ["focus"], ["volley", "focus"]]:
			var compiled: Dictionary = Compiler.compile_skill(id, _snapshot(), support_ids)
			var before: Dictionary = compiled.duplicate(true)
			var rejected: Dictionary = Compiler.compile_skill(id, compiled.snapshot, support_ids)
			_expect(not rejected.ok and rejected.size() == 2 and not rejected.error.is_empty(), "Already compiled projectile snapshot fails without partial output: " + id)
			_expect(compiled == before, "Rejected recompile leaves all prior compiled output untouched: " + id)
			var other: Dictionary = Compiler.compile_skill("nova", compiled.snapshot, [])
			_expect(not other.ok and other.size() == 2, "Compiled projectile snapshot cannot leak through another skill: " + id)
			if support_ids.is_empty():
				continue
			var stripped: Dictionary = compiled.snapshot.duplicate(true)
			stripped.erase("initial_count")
			var stripped_before: Dictionary = stripped.duplicate(true)
			var reserved: Dictionary = Compiler.compile_skill(id, stripped, support_ids)
			_expect(not reserved.ok and reserved.size() == 2, "Reserved support modifier ID rejects recompile even without count marker: " + id)
			_expect(stripped == stripped_before, "Reserved modifier rejection does not mutate input: " + id)
	var base: Dictionary = _snapshot()
	base.modifiers.append({"id": "support:unknown", "mode": "more", "value": 0.2})
	_expect(not Compiler.compile_skill("tornado", base, []).ok, "Entire support: modifier ID namespace is reserved")
	for id: String in ["nova", "dash", "ward", "meteor", "chain"]:
		var first: Dictionary = Compiler.compile_skill(id, _snapshot(), [])
		var before: Dictionary = first.duplicate(true)
		var second: Dictionary = Compiler.compile_skill(id, first.snapshot, [])
		_expect(not second.ok and second.size() == 2, "All compiled snapshots reject reentry: " + id)
		_expect(first == before, "Repeated nonprojectile baseline compile remains pure: " + id)


func _test_rejections() -> void:
	var snapshot: Dictionary = _snapshot()
	var before: Dictionary = snapshot.duplicate(true)
	for supports: Array in [["unknown"], ["volley", "volley"], ["focus", "focus"], ["volley", "focus", "volley"], [2], [null], [{}], [""], [["volley"]]]:
		var result: Dictionary = Compiler.compile_skill("tornado", snapshot, supports)
		_expect(not result.ok and result.size() == 2 and not result.error.is_empty(), "Malformed/duplicate/too-many supports fail without partial output")
		_expect(snapshot == before, "Failed compilation is atomic")
	for invalid: Variant in [null, "volley", {}, 2, PackedStringArray(["volley"])]:
		_expect(not Supports.compatibility_reason("tornado", invalid).is_empty(), "Malformed support container is rejected")
	for id: String in ["unknown", "basic", "nova", "dash", "ward", "meteor", "chain"]:
		var result: Dictionary = Compiler.compile_skill(id, snapshot, ["focus"])
		_expect(not result.ok and result.size() == 2, "Unknown or incompatible skill rejects support: " + id)
	for key: String in snapshot:
		var malformed: Dictionary = snapshot.duplicate(true)
		malformed.erase(key)
		_expect(not Compiler.compile_skill("tornado", malformed, []).ok, "Missing required snapshot field rejected: " + key)
	for pair: Array in [["base_damage", NAN], ["base_damage", "100"], ["projectile_count", 1.5], ["modifiers", [null]],
		["effects", ["unknown"]], ["tornado_recipe", {}], ["explosion_recipe", {"coefficient": INF, "radius": 1.0}]]:
		var malformed: Dictionary = snapshot.duplicate(true)
		malformed[pair[0]] = pair[1]
		var result: Dictionary = Compiler.compile_skill("tornado", malformed, ["volley"])
		_expect(not result.ok and result.size() == 2, "Malformed snapshot fails closed")


func _test_metadata_validation() -> void:
	for id: String in Supports.SUPPORTS:
		_expect(Supports.definition_error(Supports.get_definition(id)).is_empty(), "Original support passes operation allowlist")
	var original: Dictionary = Supports.get_definition("volley")
	for operation: Variant in [{"op": "arbitrary_script", "value": 1}, {"op": "add_initial_projectiles", "value": 1.5},
		{"op": "add_initial_projectiles", "value": 9}, {"op": "mana_multiplier", "value": 0},
		{"op": "projectile_hit_more", "value": NAN}, {"op": "projectile_hit_more", "value": -1.0},
		{"op": "projectile_hit_more", "value": "0.2"}, {"op": "mana_multiplier", "value": 1.3, "script": "ignored?"}, null]:
		var malformed: Dictionary = original.duplicate(true)
		malformed.operations[0] = operation
		_expect(not Supports.definition_error(malformed).is_empty(), "Unknown/invalid operation rejected before execution")
	for pair: Array in [["requires", ["explosion"]], ["requires", ["projectile_hit", "projectile_hit"]],
		["requires", "projectile_hit"], ["operations", []], ["operations", {}], ["name", null]]:
		var malformed: Dictionary = original.duplicate(true)
		malformed[pair[0]] = pair[1]
		_expect(not Supports.definition_error(malformed).is_empty(), "Malformed support metadata rejected")
	var spell: Dictionary = Data.SKILLS.bolt.projectile_recipe.duplicate(true)
	for pair: Array in [["initial_count", 0], ["initial_count", 10], ["spread", NAN], ["coefficient", -1],
		["pierce", "1"], ["slow", -1.0], ["speed", 0], ["damage_type", "unknown"]]:
		var malformed: Dictionary = spell.duplicate(true)
		malformed[pair[0]] = pair[1]
		_expect(not Compiler._projectile_recipe_error(malformed).is_empty(), "Malformed authoritative projectile metadata rejected")
	var recipe: Dictionary = Recipes.TORNADO.duplicate(true)
	recipe.child_count = 0
	var snapshot: Dictionary = _snapshot()
	snapshot.tornado_recipe = recipe
	_expect(not Compiler.compile_skill("tornado", snapshot, ["volley"]).ok, "Malformed nested tornado recipe fails before execution")
