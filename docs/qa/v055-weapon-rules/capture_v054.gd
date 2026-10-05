extends SceneTree
## Run this unchanged probe against the complete, unedited v0.54 project.
## Every oracle value is a complete returned Variant, never a derived subset.
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const SKILLS: Array[String] = ["basic", "cleave", "tornado", "bolt", "frost", "shade_bolt", "nova", "meteor", "chain", "dash", "ward"]


static func bow(flat: float = 2.0, increased: float = 0.2) -> Dictionary:
	var sources: Array[Dictionary] = []
	if flat != 0.0:
		sources.append({"affix_id": "whetstone_edge", "stat": "weapon_added_physical", "value": flat})
	if increased != 0.0:
		sources.append({"affix_id": "tempered_edge", "stat": "weapon_physical_increased", "value": increased})
	return {"stage": "weapon_local", "item_id": "gear_000123", "base_id": "ashwood_bow",
		"base": {"physical": 4.0}, "flat": {"physical": flat}, "increased": {"physical": increased}, "sources": sources}


static func compile(skill: String, snapshot: Dictionary, supports: Array = []) -> Dictionary:
	return Compiler.compile_basic(snapshot) if skill == "basic" else Compiler.compile_skill(skill, snapshot, supports)


static func invalid_profiles() -> Array:
	var values: Array = [null, [], "profile", 1, true, {"stage": "weapon_local"}]
	for key: String in bow():
		var value: Dictionary = bow()
		value.erase(key)
		values.append(value)
	for pair: Array in [["stage", "hit_base"], ["stage", 2], ["base_id", "unknown"], ["base_id", "cinder_reed"],
		["base_id", &"ashwood_bow"], ["item_id", "gear_1"], ["item_id", "gear_000000"], ["item_id", true],
		["base", {"physical": 5.0}], ["base", {}], ["base", {"physical": true}], ["flat", {"fire": 2.0}],
		["flat", {"physical": NAN}], ["increased", {"physical": INF}], ["flat", {"physical": -1.0}],
		["flat", {"physical": "2"}], ["flat", {&"physical": 2.0}], ["flat", {"physical": 3.0}],
		["increased", {"physical": 0.200000001}], ["increased", {"physical": 0.2, "fire": 0.0}],
		["sources", {}], ["sources", [null]], ["sources", []], ["quality", 0.2]]:
		var value: Dictionary = bow()
		value[pair[0]] = pair[1]
		values.append(value)
	for pair: Array in [["affix_id", "unknown"], ["stat", "attack_added_physical"], ["stat", "weapon_physical_increased"],
		["value", -2.0], ["value", NAN], ["value", "2"], ["scope", "global"]]:
		var value: Dictionary = bow()
		value.sources[0][pair[0]] = pair[1]
		values.append(value)
	var duplicate: Dictionary = bow()
	duplicate.sources.append(duplicate.sources[0].duplicate(true))
	duplicate.flat.physical = 4.0
	values.append(duplicate)
	values.append(bow(1e308, 1e308))
	return values


static func recipe(skill: String = "tornado", role: String = "parent", tags: Variant = ["hit", "attack", "projectile"]) -> Dictionary:
	return {"stage": "hit_base", "intrinsic_distribution": {"physical": 0.6, "fire": 0.4},
		"base_coefficient": 2.0, "added_effectiveness": 0.5, "tags": tags, "skill_id": skill, "role": role}


static func capture() -> Dictionary:
	var result: Dictionary = {}
	var number: int = 0
	for stats: Dictionary in [{"damage": 18.0}, {"damage": 0}, {"damage": 0.0},
		{"damage": 100.0, "attack_added_physical": 10.0, "attack_added_fire": 20.0, "spell_added_cold": 30.0, "spell_added_lightning": 40.0},
		{"damage": 18.0, "crit_base_chance": 0.05, "crit_base_multiplier": 1.5, "crit_chance_increased": 0.4,
			"crit_multiplier_add": 0.15, "max_health": 120.0, "max_mana": 80.0,
			"attack_life_leech": 0.02, "attack_mana_leech": 0.01, "attack_physical_increased": 0.15,
			"melee_physical_increased": 0.2, "physical_increased": 0.1, "area_increased": 0.1, "mana_cost_efficiency_increased": 0.2}]:
		for profile: Variant in [null, bow(0.0, 0.0), bow(), bow(6.0, 0.3)]:
			var snapshot: Dictionary = Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])
			if profile != null:
				snapshot.weapon_profile = profile
			for skill: String in SKILLS:
				result["cast:%d:%s" % [number, skill]] = compile(skill, snapshot)
				if skill in ["cleave", "nova", "meteor"]:
					result["support:%d:%s" % [number, skill]] = compile(skill, snapshot, ["concentrate"])
				elif skill == "tornado":
					result["support:%d:%s" % [number, skill]] = compile(skill, snapshot, ["focus"])
			number += 1
	for index: int in range(invalid_profiles().size()):
		var profile: Variant = invalid_profiles()[index]
		result["invalid-profile:%d" % index] = Weapon.resolve(profile)
		var snapshot: Dictionary = Combat.snapshot({"damage": 18.0}, [])
		snapshot.weapon_profile = profile
		for skill: String in ["basic", "cleave", "tornado", "bolt", "ward"]:
			result["invalid-cast:%d:%s" % [index, skill]] = compile(skill, snapshot)
		result["invalid-assemble:%d" % index] = Base.assemble(18.0, recipe(), {}, [], profile)
		# Invalid base damage must still precede invalid weapon provenance.
		snapshot.base_damage = NAN
		result["precedence:%d" % index] = compile("cleave", snapshot)
	var packet: Dictionary = Base.assemble(100.0, recipe(), {"attack": {"physical": 10.0, "fire": 20.0}}, [], bow())
	var traces: Array = [null, {}, [], "trace", packet.assembly.weapon]
	for field: String in ["profile", "components", "coefficient", "contribution"]:
		var trace: Dictionary = packet.assembly.weapon.duplicate(true)
		trace.erase(field)
		traces.append(trace)
	for pair: Array in [["profile", {}], ["profile", null], ["components", {"physical": 7.3}],
		["contribution", {"physical": 14.5}], ["coefficient", NAN], ["coefficient", 1.0], ["conversion", true]]:
		var trace: Dictionary = packet.assembly.weapon.duplicate(true)
		trace[pair[0]] = pair[1]
		traces.append(trace)
	for malformed: Variant in invalid_profiles():
		var trace: Dictionary = packet.assembly.weapon.duplicate(true)
		trace.profile = malformed
		traces.append(trace)
	for event: Array in [["basic", "projectile", ["hit", "attack", "projectile"]],
		["tornado", "parent", ["hit", "attack", "projectile"]], ["tornado", "child", ["hit", "attack", "projectile"]],
		["cleave", "direct", ["hit", "attack", "melee", "area"]], ["bolt", "projectile", ["hit", "spell", "projectile"]],
		["tornado", "secondary", ["hit", "area", "secondary", "explosion"]], ["tornado", "parent", null],
		["basic", "projectile", ["hit", "attack", "projectile", "area"]], ["basic", "projectile", ["hit", "attack", "projectile", "projectile"]]]:
		for index: int in range(traces.size()):
			var mutated: Dictionary = packet.duplicate(true)
			mutated.skill_id = event[0]
			mutated.role = event[1]
			mutated.tags = event[2]
			mutated.assembly.weapon = traces[index]
			result["trace:%d:%d" % [number, index]] = Base.packet_error(mutated)
		number += 1
	for profile: Dictionary in [{}, bow(0.0, 0.0), bow()]:
		for amount: Variant in [0, 0.0, -0.0, 18, 18.0, 1.0e300]:
			result["raw:%d" % number] = Base.assemble(amount, recipe(), {"attack": {"physical": 0, "fire": 0.0}}, [], profile)
			number += 1
	return result


func _initialize() -> void:
	var output: String = OS.get_environment("V055_ORACLE_OUTPUT")
	if output.is_empty():
		quit(78)
		return
	var rows: Dictionary = capture()
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_buffer(var_to_bytes(rows))
	file.close()
	print("Frozen v054 weapon oracle: %d complete result rows" % rows.size())
	quit(0)
